import SwiftUI

/// Bottom toast for the browser: shows the newest download's live progress
/// and taps through to the downloads sheet.
struct DownloadToastView: View {
    let item: DownloadItem
    var onCancel: () -> Void
    var onOpenList: () -> Void

    var body: some View {
        Button(action: onOpenList) {
            HStack(spacing: 12) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.12), in: .rect(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.fileName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    statusText
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))

                    progressBar
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if item.state == .downloading {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.12), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel download")
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Download in progress. Open downloads list.")
    }

    @ViewBuilder
    private var statusText: some View {
        switch item.state {
        case .downloading:
            if let total = item.totalBytes, total > 0 {
                Text("\(Int(item.progress * 100))% · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
            } else {
                Text("Downloading…")
            }
        case .completed:
            Text("Saved to Downloads")
        case .failed:
            Text(item.errorText ?? "Download failed")
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if item.state == .downloading {
            if item.totalBytes != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule()
                            .fill(Color.blue)
                            .frame(width: geo.size.width * item.progress)
                    }
                }
                .frame(height: 3)
            } else {
                // Total size unknown: a moving shimmer instead of a fake percent.
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 3)
                    .overlay {
                        GeometryReader { geo in
                            PhaseAnimator([0.0, 1.0]) { phase in
                                Capsule()
                                    .fill(Color.blue)
                                    .frame(width: geo.size.width * 0.3)
                                    .offset(x: geo.size.width * 0.7 * phase)
                            } animation: { _ in
                                .easeInOut(duration: 1.1)
                            }
                        }
                        .clipped()
                    }
            }
        }
    }
}
