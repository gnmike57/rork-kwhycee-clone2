import SwiftUI

/// Live preview of the hand-held movement applied to a still in the camera feed.
///
/// Mirrors the maths used in the injected page — same travel, same crop, same
/// sudden re-grips — so what you approve here is what a site would see. Purely a
/// preview: it never touches media delivery.
struct MotionPreviewView: View {
    let image: UIImage?
    let strength: MotionStrength
    let showsGrain: Bool
    let showsWarmth: Bool

    var body: some View {
        GeometryReader { geo in
            Color.black
                .overlay {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let frame = motionFrame(
                            at: context.date.timeIntervalSinceReferenceDate,
                            size: geo.size
                        )
                        // Grain and warmth ride along with the picture, exactly as the
                        // page bakes them into the frame it moves.
                        artwork
                            .scaleEffect(frame.zoom)
                            .rotationEffect(.radians(frame.tilt))
                            .offset(x: frame.dx, y: frame.dy)
                            .allowsHitTesting(false)
                    }
                }
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    /// Drawn once. The transform above is a cheap geometry effect on top of it.
    private var artwork: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderArt
            }
        }
        .overlay {
            if showsWarmth {
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.89, blue: 0.79).opacity(0.15),
                        Color(red: 1.0, green: 0.84, blue: 0.74).opacity(0.05),
                        Color(red: 0.08, green: 0.06, blue: 0.10).opacity(0.20)
                    ],
                    center: .init(x: 0.5, y: 0.42),
                    startRadius: 6,
                    endRadius: 220
                )
                .blendMode(.softLight)
                .allowsHitTesting(false)
            }
        }
        .overlay {
            if showsGrain {
                GrainLayer(intensity: 0.05 + 0.035 * strength.multiplier)
                    .allowsHitTesting(false)
            }
        }
    }

    private var placeholderArt: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.18, blue: 0.26), Color(red: 0.32, green: 0.22, blue: 0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 6) {
                Image(systemName: "person.crop.square")
                    .font(.system(size: 34, weight: .thin))
                    .foregroundStyle(.white.opacity(0.35))
                Text("Load a photo to preview")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    private struct MotionFrame {
        var dx: CGFloat
        var dy: CGFloat
        var zoom: CGFloat
        var tilt: Double
    }

    /// Same components, same constants and the same cover zoom as the page uses.
    private func motionFrame(at time: Double, size: CGSize) -> MotionFrame {
        let k = strength.multiplier
        let t = time * 1000
        let width = max(size.width, 1)
        let height = max(size.height, 1)

        let driftX = (sin(t * 0.00037) * 0.6 + sin(t * 0.00091 + 1.7) * 0.3 + sin(t * 0.0021 + 0.4) * 0.1)
            * width * 0.010 * k
        let driftY = (cos(t * 0.00043 + 0.9) * 0.6 + cos(t * 0.00107 + 2.3) * 0.3 + sin(t * 0.0019 + 1.1) * 0.1)
            * height * 0.010 * k
        let breathe = 1 + 0.008 * k * sin(t * 0.00052 + 0.6)
        let tilt = 0.0016 * k * sin(t * 0.00061 + 2.1)

        // A sudden re-grip every few seconds, settling over about half a second.
        let period: Double = 3200
        let index = Int((t / period).rounded(.down))
        let sinceEvent = t - Double(index) * period
        let settle = max(0, 1 - sinceEvent / 540)
        let eased = settle * settle * (3 - 2 * settle)
        let jerkX = pseudoRandom(index, salt: 1) * width * 0.0060 * k * eased
        let jerkY = pseudoRandom(index, salt: 2) * height * 0.0060 * k * eased

        // Exactly enough zoom to cover the travel — no more, so a gentle setting
        // crops almost nothing.
        let coverZoom = 1 + (2 * 0.0160 + 0.008 + 0.004) * k

        return MotionFrame(
            dx: CGFloat(driftX + jerkX),
            dy: CGFloat(driftY + jerkY),
            zoom: CGFloat(coverZoom * breathe),
            tilt: tilt
        )
    }

    /// Stable per-event value in −1...1, so the preview does not jitter on redraw.
    private func pseudoRandom(_ index: Int, salt: Int) -> Double {
        var z = UInt64(bitPattern: Int64(index &* 0x9E37_79B9 &+ salt &* 0x85EB_CA6B))
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return (Double(z >> 11) / Double(UInt64(1) << 53)) * 2 - 1
    }
}

/// One still layer of noise, drawn once rather than on every frame.
private struct GrainLayer: View {
    let intensity: Double

    var body: some View {
        Canvas { context, size in
            var generator = SplitMix(seed: 0x5EED_1234)
            let step: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let value = generator.nextUnit()
                    if value > 0.55 {
                        let shade = 0.35 + value * 0.65
                        context.fill(
                            Path(CGRect(x: x, y: y, width: step, height: step)),
                            with: .color(.white.opacity(intensity * shade))
                        )
                    }
                    x += step
                }
                y += step
            }
        }
        .blendMode(.overlay)
    }
}

/// Tiny deterministic generator so the noise pattern is stable.
private struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678
    }

    mutating func nextUnit() -> Double {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
}
