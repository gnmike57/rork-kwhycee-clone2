import SwiftUI

/// Small color-coded dot beside the media pill and in the Diagnostics status
/// row. Green feed flowing, amber requested-but-silent, red hooks lost, grey
/// no media. Purely app-side: the page has no way to see it.
struct PipelineDot: View {
    let state: PipelineIndicator

    private var tint: Color {
        switch state {
        case .flowing: .green
        case .silent: .yellow
        case .lost: .red
        case .off: Color(.systemGray3)
        }
    }

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 9, height: 9)
            .overlay(
                Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.55), radius: 2.5)
            .accessibilityLabel(Text(state.label))
    }
}
