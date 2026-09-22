import SwiftUI
import UIKit

/// Original and expanded, both drawn in the exact frame, with Use or Discard.
/// Nothing is loaded until Use is tapped.
struct FrameExpandReviewView: View {
    let original: UIImage
    let originalCrop: StillCrop?
    let expanded: UIImage
    let target: FrameTarget
    let look: FramePreviewLook
    /// Where Use may put the result. One entry means Media 2 is free.
    let placements: [BrowserViewModel.SequenceSlot]
    var onUse: (BrowserViewModel.SequenceSlot) -> Void
    var onDiscard: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Both are drawn exactly as the site would receive them at \(target.sizeText).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if target.isPortrait {
                        HStack(alignment: .top, spacing: 10) {
                            column("Original", image: original, crop: originalCrop)
                            column("Expanded", image: expanded, crop: nil)
                        }
                    } else {
                        VStack(spacing: 12) {
                            column("Original", image: original, crop: originalCrop)
                            column("Expanded", image: expanded, crop: nil)
                        }
                    }

                    Text("The person and everything already in the photo are untouched; only the new edges were painted in. The expanded copy is prepared like any other import, with photo metadata.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if placements.count > 1 {
                        Text("Media 2 is already taken. Pick which one the expanded photo replaces; the other stays as it is.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FrameCheckTheme.recentre)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    actions
                }
                .padding(16)
            }
            .background(MediaTheme.canvas)
            .navigationTitle("Expanded with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { onDiscard() }
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(MediaTheme.canvas)
        .presentationDragIndicator(.visible)
    }

    private func column(_ title: String, image: UIImage, crop: StillCrop?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ExactFramePreview(image: image, target: target, crop: crop, look: look, isPaused: true)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(FrameCheckTheme.accent.opacity(0.4), lineWidth: 0.8)
                )
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(pixelText(image))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pixelText(_ image: UIImage) -> String {
        let pixels = BrowserViewModel.pixelSize(of: image)
        return "\(Int(pixels.width))×\(Int(pixels.height))"
    }

    private var actions: some View {
        VStack(spacing: 8) {
            ForEach(placements) { slot in
                Button {
                    onUse(slot)
                } label: {
                    Text(placements.count > 1 ? "Replace Media \(slot.label)" : "Use as Media \(slot.label)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(FrameCheckTheme.accent.opacity(slot == .two ? 0.95 : 0.75)))
                }
                .buttonStyle(.plain)
            }

            Button {
                onDiscard()
            } label: {
                Text("Discard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }
}
