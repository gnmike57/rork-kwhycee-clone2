import SwiftUI
import UIKit

/// The exact preview plus everything needed to frame one loaded still: drag to
/// pan, pinch to zoom, the size pill, pause, the Recentre chip, the verdict
/// strip and the zoom slider.
///
/// Shared by the request card, Media Controls and the full-screen editor so a
/// framing set in one place is the very frame shown in the others.
struct FrameCheckPanel: View {
    @Bindable var viewModel: BrowserViewModel
    let facing: BrowserViewModel.CameraFacing
    let slot: Int
    let target: FrameTarget
    var compact: Bool = false
    var truePixels: Bool = false
    var showsSlider: Bool = true
    var showsStrip: Bool = true
    /// Settings lists hold several previews at once, so they start still.
    var startsPaused: Bool = false
    /// The reminder that the crop switch is off; Media Controls says it once itself.
    var showsCropHint: Bool = true
    /// The card hands Expand off to the full editor; the editor runs it itself.
    var onExpandWithAI: (() -> Void)? = nil

    @Environment(\.displayScale) private var displayScale
    @State private var isPaused: Bool = false
    @State private var lastDrag: CGSize = .zero
    @State private var pinchStartZoom: Double?
    @State private var pinchSnapped: Bool = false
    @State private var previewSize: CGSize = .zero

    private var image: UIImage? { viewModel.previewImage(facing: facing, slot: slot) }
    private var isStill: Bool { viewModel.isStill(facing: facing, slot: slot) }
    private var isVideo: Bool { viewModel.sourceType(facing: facing, slot: slot) == .video }
    /// Framing belongs to the frame's shape, so switching frames in the picker
    /// switches to that shape's own framing rather than dragging one across.
    private var shape: FrameShape { target.shape }
    private var storedCrop: StillCrop { viewModel.stillCrop(facing: facing, slot: slot, shape: shape) }
    private var effectiveCrop: StillCrop? { viewModel.effectiveCrop(facing: facing, slot: slot, shape: shape) }
    private var cropSwitchOn: Bool { viewModel.behavior.settings.liveStillCrop }
    private var isPanned: Bool { storedCrop.panX != 0.5 || storedCrop.panY != 0.5 }
    private var cornerRadius: CGFloat { compact ? 12 : 14 }

    private var geometry: FrameGeometry? {
        guard let image, isStill else { return nil }
        return viewModel.frameGeometry(image: image, target: target, crop: effectiveCrop)
    }

    private var verdict: FrameVerdict? {
        viewModel.frameVerdict(facing: facing, slot: slot, target: target)
    }

    /// A drag only belongs to the frame when it can move the still. A still
    /// that needs vertical pans takes the drag ahead of the page's own scroll;
    /// one that only moves sideways leaves vertical drags to the scroll.
    private var canPan: Bool { isStill && (geometry?.canPan ?? false) }
    private var takesVerticalDrags: Bool { isStill && (geometry?.canPanVertically ?? false) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if truePixels {
                truePixelsBlock
            } else {
                fittedBlock
            }

            if showsStrip, isStill, let verdict {
                FrameVerdictStrip(verdict: verdict, compact: compact) { action in
                    perform(action)
                }
            }

            if isStill, showsSlider {
                FrameZoomSlider(zoom: storedCrop.zoom) { zoom in
                    var next = storedCrop
                    next.zoom = zoom
                    viewModel.applyFrameCrop(next, facing: facing, slot: slot, shape: shape)
                }
                .padding(.horizontal, 2)
            }

            if isStill, showsSlider, showsCropHint, !cropSwitchOn {
                cropSwitchHint
            }
        }
        .onAppear {
            if startsPaused { isPaused = true }
        }
        .task(id: image.map { ObjectIdentifier($0) }) {
            if let image, isStill {
                viewModel.ensureFrameFace(for: image)
            }
        }
        .onChange(of: viewModel.isMotionFrozen, initial: true) { _, frozen in
            // A site holding its feed still is what the site sees, so the
            // preview holds too.
            if frozen { isPaused = true }
        }
    }

    // MARK: - Preview

    private var preview: ExactFramePreview {
        ExactFramePreview(
            image: isStill ? image : nil,
            target: target,
            crop: effectiveCrop,
            look: viewModel.framePreviewLook,
            isPaused: isPaused,
            showsMotionEdge: true,
            truePixels: truePixels,
            placeholderSymbol: isVideo ? "video.fill" : "photo",
            placeholderText: isVideo ? "Video · cover-fit to \(target.sizeText)" : "Nothing loaded"
        )
    }

    /// The frame keeps its exact aspect inside a height cap, so a portrait
    /// frame stands narrow and centred rather than filling the card.
    private var fittedBlock: some View {
        preview
            .frame(maxHeight: compact ? 240 : 480)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay(frameStroke)
            .overlay(alignment: .topLeading) {
                sizePill.padding(8)
            }
            .overlay(alignment: .topTrailing) {
                if isStill, viewModel.behavior.settings.liveMotion {
                    pauseButton.padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isStill, isPanned, cropSwitchOn {
                    recentreChip.padding(8)
                }
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                previewSize = size
            }
            .contentShape(.rect)
            // The preview sits inside a ScrollView. Only a still that has to
            // move up and down takes the drag away from the scroll.
            .highPriorityGesture(dragGesture, including: takesVerticalDrags ? .all : .subviews)
            .gesture(dragGesture, including: canPan && !takesVerticalDrags ? .all : .subviews)
            .simultaneousGesture(pinchGesture, including: isStill ? .all : .subviews)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPanned)
            .frame(maxWidth: .infinity)
    }

    /// The frame at one device pixel per frame pixel, scrolling when it is
    /// larger than the screen. Pan by slider here; the scroll owns the drag.
    private var truePixelsBlock: some View {
        let width = CGFloat(target.width) / displayScale
        let height = CGFloat(target.height) / displayScale
        return ScrollView([.horizontal, .vertical]) {
            preview
                .containerRelativeFrame([.horizontal, .vertical]) { length, axis in
                    axis == .horizontal ? max(length, width) : max(length, height)
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(height, 460))
        .background(Color.black)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay(frameStroke)
        .overlay(alignment: .topLeading) {
            sizePill.padding(8)
        }
        .overlay(alignment: .topTrailing) {
            if isStill, viewModel.behavior.settings.liveMotion {
                pauseButton.padding(6)
            }
        }
    }

    private var frameStroke: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(FrameCheckTheme.accent.opacity(0.42), lineWidth: 0.8)
    }

    /// Size and where it came from; a narrow portrait frame keeps just the size.
    private var sizePill: some View {
        ViewThatFits(in: .horizontal) {
            pillLabel(showsOrigin: true)
            pillLabel(showsOrigin: false)
        }
    }

    private func pillLabel(showsOrigin: Bool) -> some View {
        HStack(spacing: 5) {
            Text(target.sizeText)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            if showsOrigin {
                Text("·")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                Text(target.originText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.6), in: .capsule)
        .overlay(Capsule().strokeBorder(FrameCheckTheme.accent.opacity(0.45), lineWidth: 0.6))
    }

    private var pauseButton: some View {
        Button {
            Haptics.tick()
            isPaused.toggle()
        } label: {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.black.opacity(0.55), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPaused ? "Let the preview move" : "Pause the preview")
    }

    private var recentreChip: some View {
        Button {
            Haptics.tick()
            perform(.recentre)
        } label: {
            Label("Recentre", systemImage: "scope")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.black.opacity(0.6), in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private var cropSwitchHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption2)
            Text("Live Still Crop is off — the feed uses cover-fit. Any change here turns it on.")
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white.opacity(0.45))
    }

    // MARK: - Gestures

    /// Pan follows the finger one-for-one in frame pixels, so the picture moves
    /// exactly as far as the drag whichever way the overflow runs.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard let geometry, previewSize.width > 0 else { return }
                let step = CGSize(
                    width: value.translation.width - lastDrag.width,
                    height: value.translation.height - lastDrag.height
                )
                lastDrag = value.translation
                let scale = geometry.canvas.width / previewSize.width
                let delta = geometry.panDelta(
                    forDrag: CGSize(width: step.width * scale, height: step.height * scale)
                )
                guard delta.dx != 0 || delta.dy != 0 else { return }
                var next = storedCrop
                next.panBy(dx: delta.dx, dy: delta.dy)
                viewModel.applyFrameCrop(next, facing: facing, slot: slot, shape: shape)
            }
            .onEnded { _ in
                lastDrag = .zero
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if pinchStartZoom == nil {
                    pinchStartZoom = storedCrop.zoom
                    pinchSnapped = false
                }
                guard let start = pinchStartZoom else { return }
                var zoom = StillCrop.clampZoom(start * value.magnification)
                if abs(zoom - 1) < 0.015 {
                    zoom = 1
                    if !pinchSnapped {
                        pinchSnapped = true
                        Haptics.snap()
                    }
                } else {
                    pinchSnapped = false
                }
                var next = storedCrop
                next.zoom = zoom
                viewModel.applyFrameCrop(next, facing: facing, slot: slot, shape: shape)
            }
            .onEnded { _ in
                pinchStartZoom = nil
            }
    }

    // MARK: - Actions

    private func perform(_ action: FrameVerdict.Action) {
        if action == .expandWithAI {
            onExpandWithAI?()
            return
        }
        viewModel.performFrameAction(action, facing: facing, slot: slot, target: target)
    }
}
