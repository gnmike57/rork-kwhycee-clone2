import SwiftUI

/// Tiny native overlay of what the page is told about the live feed.
///
/// The site cannot see this. Hidden while the intercept card is up.
struct ObservedHUDView: View {
    let snapshot: ObservedFeedSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(snapshot.isActive ? Color.green : Color.orange)
                .frame(width: 6, height: 6)

            Text(sizeText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))

            Text(fpsText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))

            Text(snapshot.format)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .opacity(0.8)

            if !snapshot.cameraLabel.isEmpty {
                Text(snapshot.cameraLabel)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }

            if snapshot.pageHoldsFeed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Page still has the feed")
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .allowsHitTesting(false)
    }

    private var sizeText: String {
        guard snapshot.width > 0, snapshot.height > 0 else { return "—" }
        return "\(snapshot.width)×\(snapshot.height)"
    }

    private var fpsText: String {
        snapshot.frameRate > 0 ? "\(snapshot.frameRate) fps" : "— fps"
    }
}
