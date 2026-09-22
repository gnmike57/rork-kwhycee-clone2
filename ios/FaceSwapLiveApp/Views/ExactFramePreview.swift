import SwiftUI
import UIKit

/// Colours shared by every Frame Check surface.
enum FrameCheckTheme {
    static let accent = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    static let fits = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    static let recentre = Color(red: 245 / 255, green: 179 / 255, blue: 43 / 255)
    static let expand = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    static let warning = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)

    static func color(for kind: FrameVerdict.Kind) -> Color {
        switch kind {
        case .fits: fits
        case .recentre: recentre
        case .expand: expand
        }
    }
}

/// The still exactly as the page's live feed will draw it into one frame.
///
/// Rendering is `FrameRigMath` step for step: cover-fit into the frame's
/// pixels, the still's crop, the hand-held bake zoom, then per frame the same
/// drift, breath, tilt and re-grips, the same warmth and grain baked over the
/// bitmap, and the same exposure wipe and blit opacity. What this shows is what
/// the site gets; what this cuts, the site never sees.
struct ExactFramePreview: View {
    let image: UIImage?
    let target: FrameTarget
    /// The crop the page really reads — `nil` for identity or switch off.
    let crop: StillCrop?
    let look: FramePreviewLook
    var isPaused: Bool = false
    var showsMotionEdge: Bool = true
    /// One frame pixel per device pixel, so an upscaled still looks as soft as
    /// it really will. The view then takes the frame's own size.
    var truePixels: Bool = false
    var placeholderSymbol: String = "photo"
    var placeholderText: String = "Nothing loaded"

    @Environment(\.displayScale) private var displayScale
    @State private var startedAt: Date = Date()
    @State private var pausedAt: Date?
    @State private var seed: UInt64 = UInt64.random(in: 1...UInt64.max)
    @State private var working: UIImage?
    @State private var workingSource: ObjectIdentifier?

    var body: some View {
        Group {
            if truePixels {
                canvasBody
                    .frame(
                        width: CGFloat(target.width) / displayScale,
                        height: CGFloat(target.height) / displayScale
                    )
            } else {
                Color.clear
                    .aspectRatio(target.aspect, contentMode: .fit)
                    .overlay(canvasBody)
            }
        }
        .background(Color.black)
        .onAppear {
            if isPaused { pausedAt = Date() }
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                pausedAt = Date()
            } else if let pausedAt {
                startedAt = startedAt.addingTimeInterval(Date().timeIntervalSince(pausedAt))
                self.pausedAt = nil
            }
        }
        .task(id: workingKey) {
            await prepareWorkingImage()
        }
    }

    private var workingKey: String {
        guard let image else { return "none" }
        return "\(ObjectIdentifier(image).hashValue)-\(truePixels)"
    }

    private var animates: Bool {
        image != nil && look.liveMotion && !isPaused
    }

    @ViewBuilder
    private var canvasBody: some View {
        if let image {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { timeline in
                Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                    draw(image: image, in: &context, size: size, now: timeline.date)
                }
            }
            .allowsHitTesting(false)
        } else {
            VStack(spacing: 6) {
                Image(systemName: placeholderSymbol)
                    .font(.title3)
                Text(placeholderText)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.35))
            .padding(12)
        }
    }

    // MARK: - Time

    /// Milliseconds since the rig was made, frozen while paused.
    private func elapsedMilliseconds(now: Date) -> Double {
        if isPaused {
            return max(0, (pausedAt ?? startedAt).timeIntervalSince(startedAt) * 1000)
        }
        return max(0, now.timeIntervalSince(startedAt) * 1000)
    }

    // MARK: - Drawing

    private func draw(image: UIImage, in context: inout GraphicsContext, size: CGSize, now: Date) {
        let cw = Double(target.width)
        let ch = Double(target.height)
        guard cw > 0, ch > 0, size.width > 0 else { return }
        // Everything below is in frame pixels, as the page's canvas is.
        let s = size.width / cw
        context.scaleBy(x: s, y: s)

        let canvas = CGSize(width: cw, height: ch)
        let frameRect = CGRect(origin: .zero, size: canvas)
        let geometry = FrameGeometry(
            canvas: canvas,
            image: BrowserViewModel.pixelSize(of: image),
            crop: crop,
            motionK: look.motionKIfOn
        )
        let resolved = context.resolve(Image(uiImage: working ?? image))

        guard let k = look.motionKIfOn, let rig = geometry.rig else {
            // Motion off: the still covers the frame unless zoomed out, and
            // then the frame is black around it.
            context.fill(Path(frameRect), with: .color(.black))
            context.draw(resolved, in: geometry.imageRect)
            return
        }

        let t = elapsedMilliseconds(now: now)
        let motion = FrameRigMath.motion(t: t, canvas: canvas, k: k, seed: seed)

        // The wipe doubles as the exposure drift, exactly as on the page.
        var lift = 0.0
        if look.exposure {
            let exposure = FrameRigMath.exposure(t: t)
            lift = exposure.lift
            context.fill(
                Path(frameRect),
                with: .color(Color(red: exposure.red, green: exposure.green, blue: exposure.blue))
            )
        } else {
            context.fill(Path(frameRect), with: .color(.black))
        }

        let bw = rig.bitmapSize.width
        let bh = rig.bitmapSize.height
        let bitmapRect = CGRect(x: -bw * 0.5, y: -bh * 0.5, width: bw, height: bh)
        let imageInBitmap = rig.imageInBitmap.offsetBy(dx: -bw * 0.5, dy: -bh * 0.5)
        let warmth = look.warmth
        let grain = look.grain
        let grainAlpha = FrameRigMath.grainAlpha(k: k)
        let blitOpacity = 1 - abs(lift)

        // One bake, one blit: the bitmap layer is moved with one even scale, a
        // tilt and the drift, and composited at the blit's opacity.
        context.drawLayer { moving in
            moving.opacity = blitOpacity
            moving.translateBy(x: cw * 0.5 + motion.dx, y: ch * 0.5 + motion.dy)
            if motion.tilt != 0 {
                moving.rotate(by: .radians(motion.tilt))
            }
            if motion.breathe != 1 {
                moving.scaleBy(x: motion.breathe, y: motion.breathe)
            }
            moving.drawLayer { bitmap in
                bitmap.clip(to: Path(bitmapRect))
                bitmap.draw(resolved, in: imageInBitmap)
                if warmth {
                    bitmap.blendMode = .softLight
                    bitmap.fill(
                        Path(bitmapRect),
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: Color(red: 1, green: 228 / 255, blue: 201 / 255).opacity(0.15), location: 0),
                                .init(color: Color(red: 1, green: 214 / 255, blue: 188 / 255).opacity(0.05), location: 0.55),
                                .init(color: Color(red: 20 / 255, green: 15 / 255, blue: 24 / 255).opacity(0.20), location: 1)
                            ]),
                            center: CGPoint(x: 0, y: -bh * 0.03),
                            startRadius: min(bw, bh) * 0.08,
                            endRadius: max(bw, bh) * 0.78
                        )
                    )
                    bitmap.blendMode = .normal
                }
                if grain {
                    bitmap.blendMode = .overlay
                    bitmap.opacity = grainAlpha
                    bitmap.fill(
                        Path(bitmapRect),
                        with: .tiledImage(FramePreviewAssets.grainTile, origin: bitmapRect.origin, scale: 1)
                    )
                }
            }
        }

        if showsMotionEdge {
            // The band outside this line comes and goes as the picture moves.
            context.stroke(
                Path(roundedRect: geometry.safeRect, cornerRadius: 2 / s),
                with: .color(.white.opacity(0.42)),
                style: StrokeStyle(lineWidth: 1 / s, dash: [4 / s, 3 / s])
            )
        }
    }

    // MARK: - Working image

    /// A reduced copy keeps the per-frame blit cheap. True-pixels mode draws
    /// the still itself so nothing softens that the page would not soften.
    private func prepareWorkingImage() async {
        guard let image else {
            working = nil
            workingSource = nil
            return
        }
        let key = ObjectIdentifier(image)
        if truePixels {
            working = nil
            workingSource = key
            return
        }
        if workingSource == key, working != nil { return }
        let pixels = BrowserViewModel.pixelSize(of: image)
        if max(pixels.width, pixels.height) <= 1800 {
            working = nil
            workingSource = key
            return
        }
        // Resampling a large still is heavy; it runs on the concurrent pool
        // as part of this view's own `.task`, so leaving the view cancels it.
        let reduced = await Self.reduce(image, longSide: 1800)
        if !Task.isCancelled {
            working = reduced
            workingSource = key
        }
    }

    @concurrent
    nonisolated private static func reduce(_ image: UIImage, longSide: CGFloat) async -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height) * image.scale
        guard longest > 0 else { return image }
        let scale = min(1, longSide / longest)
        if scale >= 1 { return image }
        let out = CGSize(
            width: max(1, (size.width * image.scale * scale).rounded()),
            height: max(1, (size.height * image.scale * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: out, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: out))
        }
    }
}

/// Bitmaps the preview bakes once.
@MainActor
enum FramePreviewAssets {
    /// `makeNoiseTile(96)`: grey noise, `128 ± 34`, one tile repeated.
    static let grainTile: Image = {
        let side = 96
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        var generator = FrameRigMath.SeededGenerator(seed: 0x6A11_5EED)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = UInt8(min(255, max(0, 128 + (generator.unit() * 2 - 1) * 34)))
            pixels[index] = value
            pixels[index + 1] = value
            pixels[index + 2] = value
            pixels[index + 3] = 255
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: side,
                height: side,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return Image(systemName: "square.fill")
        }
        return Image(uiImage: UIImage(cgImage: cgImage, scale: 1, orientation: .up))
    }()
}
