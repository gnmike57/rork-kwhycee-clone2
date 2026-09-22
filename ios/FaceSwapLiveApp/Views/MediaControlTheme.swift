import SwiftUI

/// Visual language shared by Media Controls and the My Media source deck.
///
/// True-black canvas, elevated graphite cards, one cool blue accent. Tuned for
/// the app's single dark appearance — borders carry the separation, since a
/// shadow is invisible on black.
enum MediaTheme {
    static let canvas = Color.black
    /// Baseline card surface.
    static let card = Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255)
    /// Popovers / secondary wells inside a card.
    static let well = Color(red: 35 / 255, green: 35 / 255, blue: 41 / 255)
    static let accent = Color(red: 94 / 255, green: 158 / 255, blue: 255 / 255)
    static let frontTint = Color(red: 94 / 255, green: 211 / 255, blue: 232 / 255)
    static let backTint = Color(red: 112 / 255, green: 196 / 255, blue: 128 / 255)

    static let stroke = Color.white.opacity(0.08)
    static let strokeStrong = Color.white.opacity(0.14)
}

/// One collapsible settings group: icon header, graphite card body.
///
/// Built once so Media Controls, the device-matched sections and the My Media
/// deck all share identical rhythm, radius and stroke.
struct MediaSection<Content: View>: View {
    let title: String
    let systemImage: String
    var tint: Color
    var footnote: String?
    @ViewBuilder var content: Content

    @State private var isExpanded: Bool

    init(
        title: String,
        systemImage: String,
        tint: Color = MediaTheme.accent,
        footnote: String? = nil,
        startsExpanded: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.footnote = footnote
        self.content = content()
        _isExpanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
                Haptics.tick()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 26, height: 26)
                        .background(tint.opacity(0.16), in: .rect(cornerRadius: 7))

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(MediaTheme.card, in: .rect(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(MediaTheme.stroke, lineWidth: 1)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }

            if isExpanded, let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }
}

/// A control row inside a MediaSection: title + subtitle, trailing content.
///
/// Rows carry their own separators via `withDivider`, so sections read as one
/// continuous card instead of boxed lines.
struct MediaRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var withDivider: Bool = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if withDivider {
                Divider().opacity(0.5)
            }
        }
    }
}

/// Convenience initialiser for the common plain row (no trailing content).
extension MediaRow where Trailing == EmptyView {
    init(title: String, detail: String? = nil, withDivider: Bool = true) {
        self.title = title
        self.detail = detail
        self.withDivider = withDivider
        self.trailing = EmptyView()
    }
}

/// Status capsule used for the front/back source counts.
struct SourceBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: .capsule)
    }
}
