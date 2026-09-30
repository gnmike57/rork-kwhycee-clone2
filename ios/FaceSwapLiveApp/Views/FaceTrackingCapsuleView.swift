import SwiftUI

/// Slim status capsule floating opposite the pill, at the pill's height, so
/// the two can never overlap — including under iPhone Mirroring resize.
///
/// Pure status: it never takes a touch, so even if a resize briefly brings it
/// over a button, presses pass straight through.
///
/// When the pill is tucked, the capsule shrinks to the short state word.
struct FaceTrackingCapsuleView: View {
    let placement: PillPlacement
    /// The same moments the pill hides.
    let isHidden: Bool

    @Environment(FaceTrackingController.self) private var tracking

    private static let pillHeight: CGFloat = 58
    private static let edgeInset: CGFloat = 10

    @State private var measuredWidth: CGFloat = 120

    private var mood: FaceTrackingMood { tracking.mood }

    var body: some View {
        GeometryReader { geo in
            let usableHeight = max(geo.size.height - Self.pillHeight - 24, 1)
            let y = 12 + usableHeight * placement.verticalFraction + Self.pillHeight / 2
            let halfWidth = measuredWidth / 2

            Group {
                if placement.isTucked {
                    compact
                } else {
                    full
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                if width > 0 { measuredWidth = width }
            }
            .position(
                x: placement.isLeftEdge
                    ? geo.size.width - Self.edgeInset - halfWidth
                    : Self.edgeInset + halfWidth,
                y: y
            )
            // Same spring the pill uses, so the pair moves as one when the
            // pill is dragged to a new resting spot or tucked.
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: placement)
        }
        .opacity(isHidden ? 0 : 1)
        .animation(.easeOut(duration: 0.18), value: isHidden)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Full line

    private var full: some View {
        ZStack {
            if let line = tracking.capsuleLine {
                HStack(spacing: 6) {
                    Circle()
                        .fill(mood.tint)
                        .frame(width: 7, height: 7)
                    Text(line)
                        .monospacedDigit()
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(capsuleBackground)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                .id(line)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: tracking.capsuleLine)
    }

    // MARK: - Tucked word

    private var compact: some View {
        ZStack {
            if mood != .off, let line = tracking.capsuleLine {
                Text(shortWord(for: line))
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(capsuleBackground)
                    .id(line)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: tracking.capsuleLine)
    }

    /// The tucked tab has room for one word; the longest distinct part of the
    /// state line is enough to tell the states apart at a glance.
    private func shortWord(for line: String) -> String {
        if mood == .live { return "LIVE" }
        if mood == .lost { return "LOST" }
        if mood == .error { return "ERR" }
        if line.hasPrefix("Listening") { return "LISTEN" }
        if line.hasPrefix("Receiving") { return "RECV" }
        if mood == .waiting { return "WAIT" }
        return "SCAN"
    }

    private var capsuleBackground: some View {
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(Color.black.opacity(0.36))
            Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
        }
    }
}
