import SwiftUI

/// Tiny draggable look-in at the injected feed.
///
/// Shows the web view's own native snapshot — the exact picture the page is
/// being sent — refreshed about once a second while media is active. A native
/// snapshot cannot be observed by the page, so this adds no detection surface.
/// Tapping enlarges; the parked position is remembered across launches.
struct LivePeekView: View {
    @Bindable var viewModel: BrowserViewModel

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var isEnlarged = false
    @State private var dismissed = false
    /// Distance in from the trailing edge, and down from the top. Parked in
    /// points so the thumbnail stays where the user left it.
    @AppStorage("pipeline_peek_inset") private var parkedInset: Double = 14
    @AppStorage("pipeline_peek_top") private var parkedTop: Double = 150

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldShow: Bool {
        viewModel.behavior.settings.showLivePeek
            && viewModel.isMediaActive
            && viewModel.hasSource
            && viewModel.currentURL != nil
            && !dismissed
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if shouldShow, let frame = viewModel.peekFrame {
                thumbnail(frame)
                    .transition(.opacity)
                    .fullScreenCover(isPresented: $isEnlarged) {
                        enlarged(frame)
                    }
            }
        }
        // The look-in belongs to the live feed: refresh while it is shown,
        // stop the moment it is not. One native snapshot per second.
        .task(id: shouldShow) {
            guard shouldShow else { return }
            while !Task.isCancelled {
                viewModel.capturePeekFrame()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: shouldShow)
    }

    private func thumbnail(_ frame: UIImage) -> some View {
        Image(uiImage: frame)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 72, height: 112)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                PipelineDot(state: viewModel.pipelineIndicator)
                    .offset(x: -4, y: -4)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    dismissed = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.75), .black.opacity(0.45))
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Hide look-in")
            }
            .overlay(alignment: .bottom) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.45), radius: isDragging ? 16 : 8, y: isDragging ? 8 : 4)
            .scaleEffect(isDragging ? 1.04 : 1)
            .offset(x: -parkedInset + dragOffset.width, y: parkedTop + dragOffset.height)
            .gesture(dragGesture)
            .onTapGesture { isEnlarged = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Feed look-in")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation
            }
            .onEnded { value in
                isDragging = false
                // Parked inset grows as the thumbnail moves left; the parked
                // top grows as it moves down. Both clamp on screen.
                parkedInset = (parkedInset - value.translation.width).clamped(to: 8...160)
                parkedTop = (parkedTop + value.translation.height).clamped(to: 12...520)
                dragOffset = .zero
            }
    }

    private func enlarged(_ frame: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 10) {
                Image(uiImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay(alignment: .topLeading) {
                        PipelineDot(state: viewModel.pipelineIndicator)
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                Text(viewModel.pipelineIndicator.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            Button {
                isEnlarged = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
            .accessibilityLabel("Close look-in")
        }
        .task(id: isEnlarged) {
            while !Task.isCancelled, isEnlarged {
                viewModel.capturePeekFrame()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
