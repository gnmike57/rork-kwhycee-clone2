import SwiftUI

/// One coloured dot, one plain-language line, at most two actions.
struct FrameVerdictStrip: View {
    let verdict: FrameVerdict
    var compact: Bool = false
    var onAction: (FrameVerdict.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(FrameCheckTheme.color(for: verdict.kind))
                    .frame(width: 8, height: 8)
                    .shadow(color: FrameCheckTheme.color(for: verdict.kind).opacity(0.6), radius: 4)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }

                VStack(alignment: .leading, spacing: 3) {
                    Text(verdict.reason)
                        .font(compact ? .caption : .footnote)
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(verdict.warnings) { warning in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle()
                                .fill(FrameCheckTheme.warning)
                                .frame(width: 5, height: 5)
                                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 3 }
                            Text(warning.text)
                                .font(.caption2)
                                .foregroundStyle(FrameCheckTheme.warning.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            if !verdict.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(verdict.actions.prefix(2)) { action in
                        Button {
                            Haptics.tick()
                            onAction(action)
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(action == .expandWithAI ? Color.black : .white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(
                                        action == .expandWithAI
                                            ? FrameCheckTheme.expand.opacity(0.95)
                                            : Color.white.opacity(0.10)
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.045), in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(FrameCheckTheme.color(for: verdict.kind).opacity(0.28), lineWidth: 0.8)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: verdict)
    }
}

/// Zoom on top of cover-fit, with a tick and a snap at 100%.
struct FrameZoomSlider: View {
    var zoom: Double
    var onChange: (Double) -> Void

    @State private var snapped: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            Text("Zoom")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 44, alignment: .leading)

            Slider(
                value: Binding(
                    get: { zoom * 100 },
                    set: { percent in
                        var next = StillCrop.clampZoom(percent / 100)
                        // Snap to today's cover-fit when the thumb passes it.
                        if abs(next - 1) < 0.012 {
                            next = 1
                            if !snapped {
                                snapped = true
                                Haptics.snap()
                            }
                        } else {
                            snapped = false
                        }
                        onChange(next)
                    }
                ),
                in: StillCrop.minZoom * 100...StillCrop.maxZoom * 100,
                step: 1
            )
            .tint(FrameCheckTheme.accent)

            Text("\(Int((zoom * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(zoomTint)
                .frame(width: 42, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }

    private var zoomTint: Color {
        if zoom < 0.999 { return FrameCheckTheme.recentre }
        return zoom == 1 ? .white.opacity(0.55) : FrameCheckTheme.accent
    }
}

/// The three sizes sites really ask for, at a glance: a tick when the still
/// lands cleanly, a caution when it needs a nudge, a wand when the shape simply
/// cannot be cropped to fit.
struct FrameReadinessRow: View {
    let items: [FrameReadiness]
    var compact: Bool = false

    var body: some View {
        WrappingRow(spacing: compact ? 5 : 7, lineSpacing: compact ? 4 : 6) {
            ForEach(items) { item in
                HStack(spacing: 3) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: compact ? 7 : 8, weight: .black))
                    Text(item.target.sizeText)
                        .font(.system(size: compact ? 8 : 9, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(FrameCheckTheme.color(for: item.kind))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, compact ? 5 : 6)
                .padding(.vertical, compact ? 2 : 3)
                .background(
                    Capsule().fill(FrameCheckTheme.color(for: item.kind).opacity(0.14))
                )
                .accessibilityLabel(item.spokenSummary)
            }
        }
    }
}

/// Lays children left to right and wraps to a new line when the width runs
/// out, so small pills never get squeezed into tall slivers.
struct WrappingRow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                totalHeight += lineHeight + lineSpacing
                widest = max(widest, lineWidth)
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += (lineWidth > 0 ? spacing : 0) + size.width
            lineHeight = max(lineHeight, size.height)
        }
        totalHeight += lineHeight
        widest = max(widest, lineWidth)
        return CGSize(width: proposal.width ?? widest, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// The small amber/orange mark for a still that would benefit from a look.
struct FrameAttentionBadge: View {
    let kind: FrameVerdict.Kind

    var body: some View {
        Image(systemName: kind == .expand ? "wand.and.sparkles" : "crop")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.black)
            .padding(3)
            .background(FrameCheckTheme.color(for: kind), in: .circle)
            .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 0.8))
    }
}
