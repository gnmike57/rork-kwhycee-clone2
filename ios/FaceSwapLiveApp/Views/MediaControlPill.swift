import SwiftUI

/// Floating quick-access layer over the browser.
///
/// A shortcut only — the bottom camera button and the full settings sheet are
/// untouched and remain the place for detailed setup.
/// Press feedback for the pill's round controls.
private struct PillPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct MediaControlPill: View {
    @Bindable var viewModel: BrowserViewModel
    var isHidden: Bool
    /// Front/Back thumbnails jump here now that sources live in My Media.
    var onOpenSources: (() -> Void)? = nil
    var onOpenControls: (BrowserViewModel.CameraFacing) -> Void

    @State private var drag: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var measuredWidth: CGFloat = 218
    /// Runs while a zoom button is held down, so a press ramps smoothly
    /// instead of needing one tap per step.
    @State private var zoomRepeat: Task<Void, Never>?

    private var store: MediaBehaviorStore { viewModel.behavior }
    private var placement: PillPlacement { store.pillPlacement }

    private let pillHeight: CGFloat = 58
    private let edgeInset: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let usableHeight = max(geo.size.height - pillHeight - 24, 1)
            let restingY = 12 + usableHeight * placement.verticalFraction + pillHeight / 2

            Group {
                if placement.isTucked {
                    tuckedTab
                        .position(
                            x: placement.isLeftEdge ? 26 : geo.size.width - 26,
                            y: restingY
                        )
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else {
                    pillBody
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { width in
                            if width > 0 { measuredWidth = width }
                        }
                        // Sits under the tools without changing their size, so
                        // saying what a press did can never move the buttons.
                        .overlay(alignment: placement.isLeftEdge ? .bottomLeading : .bottomTrailing) {
                            if let notice = viewModel.reinjectNotice {
                                reinjectNoticeLabel(notice)
                                    .fixedSize()
                                    .offset(y: 25)
                                    // Says what happened and nothing more: a tap
                                    // meant for the tools must never land on it.
                                    .allowsHitTesting(false)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .animation(.easeOut(duration: 0.2), value: viewModel.reinjectNotice)
                        .offset(drag)
                        .position(
                            x: pillCenterX(in: geo.size.width),
                            y: restingY
                        )
                        .gesture(dragGesture(in: geo.size))
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: placement)
        }
        .allowsHitTesting(!isHidden)
        .opacity(isHidden ? 0 : 1)
        .animation(.easeOut(duration: 0.18), value: isHidden)
        .task { Haptics.prepare() }
        .onDisappear { stopZoomRepeat() }
        // The zoom acts on the frame the page is really drawing into, so the
        // exact canvas is read back whenever a feed opens or changes camera.
        .onChange(of: viewModel.isLiveStreamActive, initial: true) { _, _ in
            viewModel.refreshLiveFrameSize()
        }
        .onChange(of: viewModel.activeStreamFacing) { _, _ in
            viewModel.refreshLiveFrameSize()
        }
    }

    private func pillCenterX(in width: CGFloat) -> CGFloat {
        let halfWidth = measuredWidth / 2
        return placement.isLeftEdge
            ? edgeInset + halfWidth
            : width - edgeInset - halfWidth
    }

    // MARK: - Pill

    /// The row tightens while the zoom cluster is on screen, so every control
    /// still fits across a phone rather than running off the far edge.
    private var controlSpacing: CGFloat {
        viewModel.canZoomLiveFeed ? 6 : 10
    }

    private var pillBody: some View {
        HStack(spacing: controlSpacing) {
            powerButton
            nextButton
            reinjectButton
            if viewModel.behavior.settings.liveMotion {
                freezeButton
            }
            if viewModel.canZoomLiveFeed {
                zoomCluster
            }
            if showFaceButtons {
                faceButton(title: "Smirk", systemImage: "face.smiling")
                faceButton(title: "Smile", systemImage: "mouth")
            }

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1, height: 30)

            cameraModule(.front)
            cameraModule(.back)
        }
        .padding(.horizontal, 12)
        .frame(height: pillHeight)
        .background(pillBackground)
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .clipShape(.capsule)
        .shadow(color: .black.opacity(0.42), radius: isDragging ? 22 : 14, y: isDragging ? 12 : 7)
        .scaleEffect(isDragging ? 1.05 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
    }

    private var pillBackground: some View {
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(Color.black.opacity(0.34))
            if viewModel.isMediaActive {
                Capsule()
                    .fill(
                        RadialGradient(
                            colors: [Color.green.opacity(0.18), .clear],
                            center: .leading,
                            startRadius: 2,
                            endRadius: 130
                        )
                    )
            }
        }
    }

    private var tuckedTab: some View {
        Button {
            Haptics.tick()
            store.pillPlacement.isTucked = false
        } label: {
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.black.opacity(0.36)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.8))

                Image(systemName: placement.isLeftEdge ? "chevron.right" : "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(viewModel.isMediaActive ? Color.green : .white.opacity(0.75))
            }
            // Minimum touch size, even though the visible capsule is slimmer.
            .frame(width: 44, height: 56)
            .contentShape(Capsule())
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Controls

    private var powerButton: some View {
        Button {
            Haptics.firm()
            viewModel.setMediaActive(!viewModel.isMediaActive)
        } label: {
            ZStack {
                Circle()
                    .fill(viewModel.isMediaActive
                          ? Color.green.opacity(0.22)
                          : Color.white.opacity(0.08))
                    .frame(width: 34, height: 34)

                Circle()
                    .strokeBorder(
                        viewModel.isMediaActive ? Color.green.opacity(0.65) : Color.white.opacity(0.18),
                        lineWidth: 1.2
                    )
                    .frame(width: 34, height: 34)

                Image(systemName: "power")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(viewModel.isMediaActive ? Color.green : .white.opacity(0.55))
            }
        }
        .buttonStyle(PillPress())
        .disabled(!viewModel.hasSource)
        .opacity(viewModel.hasSource ? 1 : 0.4)
        .accessibilityLabel(viewModel.isMediaActive ? "Disable media" : "Enable media")
    }

    private var nextButton: some View {
        let fading = viewModel.isFadingMedia

        return Button {
            Haptics.tick()
            viewModel.nextMedia()
        } label: {
            ZStack {
                Circle()
                    .fill(fading ? Color.cyan.opacity(0.18) : Color.white.opacity(0.08))
                    .frame(width: 34, height: 34)

                if fading {
                    Circle()
                        .strokeBorder(Color.cyan.opacity(0.55), lineWidth: 1.2)
                        .frame(width: 34, height: 34)
                }

                Image(systemName: "forward.end.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(fading
                                     ? Color.cyan.opacity(0.95)
                                     : Color.white.opacity(canAdvance ? 0.85 : 0.3))
                    .scaleEffect(fading ? 0.86 : 1)
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.7), value: fading)
        }
        .buttonStyle(PillPress())
        .disabled(!canAdvance)
        .accessibilityLabel("Next media")
        .accessibilityHint(fading ? "Fading the live feed to the next item" : "")
    }

    /// Clears what the page is holding and sends the current media in again.
    ///
    /// The one button for a feed stuck on the previous item, a picture that has
    /// frozen, and media loaded while nothing was live. It repeats the item that
    /// should be showing rather than skipping ahead, so it is safe to press.
    private var reinjectButton: some View {
        let busy = viewModel.isReinjecting

        return Button {
            Haptics.firm()
            viewModel.forceReinject()
        } label: {
            ZStack {
                Circle()
                    .fill(busy ? Color.orange.opacity(0.20) : Color.white.opacity(0.08))
                    .frame(width: 34, height: 34)

                if busy {
                    Circle()
                        .strokeBorder(Color.orange.opacity(0.6), lineWidth: 1.2)
                        .frame(width: 34, height: 34)
                }

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(busy ? Color.orange : .white.opacity(viewModel.hasSource ? 0.85 : 0.3))
                    .rotationEffect(.degrees(busy ? 180 : 0))
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.72), value: busy)
        }
        .buttonStyle(PillPress())
        .disabled(!viewModel.hasSource)
        .accessibilityLabel("Send the media again")
        .accessibilityHint("Clears what the page is holding and re-sends the current item")
    }

    private func reinjectNoticeLabel(_ notice: String) -> some View {
        Text(notice)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.62)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            .accessibilityLabel(notice)
    }

    private var showFaceButtons: Bool {
        viewModel.behavior.settings.frontFaceButtons
            && viewModel.facePrep.isReady
            && viewModel.activeStreamFacing == .front
            && viewModel.isLiveStreamActive
    }

    private func faceButton(title: String, systemImage: String) -> some View {
        Button {
            Haptics.tick()
            viewModel.nextMedia()
        } label: {
            VStack(spacing: 1) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 7, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(0.08), in: .circle)
        }
        .buttonStyle(PillPress())
        .accessibilityLabel(title)
    }

    private var canAdvance: Bool {
        viewModel.frontSlotCount > 1 || viewModel.backSlotCount > 1
    }

    /// Holds the live picture perfectly still for this site. Live feed only — it
    /// never touches files, the photo chooser or the native camera.
    private var freezeButton: some View {
        let frozen = viewModel.isMotionFrozen
        let eased = viewModel.motionEasedLevel > 0
        let tint: Color = frozen ? .cyan : (eased ? .orange : .white)

        return Button {
            Haptics.firm()
            viewModel.toggleMotionFreeze()
        } label: {
            ZStack {
                Circle()
                    .fill(frozen ? Color.cyan.opacity(0.20) : Color.white.opacity(0.08))
                    .frame(width: 34, height: 34)

                if frozen || eased {
                    Circle()
                        .strokeBorder(tint.opacity(0.6), lineWidth: 1.2)
                        .frame(width: 34, height: 34)
                }

                Image(systemName: frozen ? "snowflake" : "waveform.path")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint.opacity(frozen || eased ? 0.95 : 0.6))
            }
        }
        .buttonStyle(PillPress())
        .disabled(viewModel.currentURL == nil)
        .opacity(viewModel.currentURL == nil ? 0.4 : 1)
        .accessibilityLabel(frozen ? "Let the picture move again" : "Hold the picture still")
        .accessibilityHint(eased ? "Movement eased off automatically to keep the feed smooth" : "")
    }

    // MARK: - Live zoom

    /// Minus, the current zoom, plus. Only while a site is really being sent a
    /// feed — there is nothing to zoom otherwise.
    ///
    /// Live feed only: files, the photo chooser and the native camera never see
    /// any of this.
    private var zoomCluster: some View {
        let zoom = viewModel.liveZoom
        let empties = zoom < 0.999

        return HStack(spacing: 3) {
            zoomButton(systemImage: "minus", delta: -StillCrop.zoomStep, enabled: zoom > StillCrop.minZoom + 0.001)

            // Tapping the reading goes straight back to the untouched fit, so
            // the one value worth reaching never has to be counted out.
            Button {
                guard zoom != 1 else { return }
                viewModel.setLiveZoom(1)
                Haptics.snap()
            } label: {
                VStack(spacing: 0) {
                    Text("\(Int((zoom * 100).rounded()))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .contentTransition(.numericText())
                    // Below the fit the picture no longer fills the frame, so
                    // the reading says so rather than only changing colour.
                    if empties {
                        Text("EDGES")
                            .font(.system(size: 6, weight: .heavy, design: .rounded))
                            .tracking(0.4)
                    }
                }
                .foregroundStyle(zoomTint(zoom))
                .frame(width: 36, height: 30)
                .contentShape(.rect)
            }
            .buttonStyle(PillPress())
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: zoom)
            .accessibilityLabel("Zoom \(Int((zoom * 100).rounded())) percent")
            .accessibilityHint(empties
                ? "Below the fit — the site sees empty edges. Tap to return to the fit."
                : "Tap to return to the fit")

            zoomButton(systemImage: "plus", delta: StillCrop.zoomStep, enabled: zoom < StillCrop.maxZoom - 0.001)
        }
        .padding(.horizontal, 5)
        .frame(height: 38)
        .background(
            Capsule().fill(empties ? Color.orange.opacity(0.16) : Color.white.opacity(0.06))
        )
        .overlay(
            Capsule().strokeBorder(
                empties ? Color.orange.opacity(0.5) : Color.white.opacity(0.10),
                lineWidth: 0.8
            )
        )
        .transition(.scale(scale: 0.7).combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: empties)
    }

    private func zoomTint(_ zoom: Double) -> Color {
        if zoom < 0.999 { return .orange }
        return zoom > 1.001 ? .cyan : .white.opacity(0.7)
    }

    /// A tap moves one step; holding ramps. A long press returns to the
    /// untouched fit, which is the one value worth reaching without counting.
    private func zoomButton(systemImage: String, delta: Double, enabled: Bool) -> some View {
        Button {
            applyZoomStep(delta)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.28))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(enabled ? 0.10 : 0.04), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(PillPress())
        .disabled(!enabled)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.32)
                .onEnded { _ in startZoomRepeat(delta) }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in stopZoomRepeat() }
        )
        .accessibilityLabel(delta > 0 ? "Zoom in" : "Zoom out")
        .accessibilityHint("Hold to keep zooming")
    }

    private func applyZoomStep(_ delta: Double) {
        let before = viewModel.liveZoom
        let after = viewModel.stepLiveZoom(by: delta)
        guard after != before else { return }
        // The untouched fit is the one value worth feeling on the way past.
        if after == 1 { Haptics.snap() } else { Haptics.tick() }
    }

    private func startZoomRepeat(_ delta: Double) {
        stopZoomRepeat()
        zoomRepeat = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(90))
                if Task.isCancelled { return }
                let before = viewModel.liveZoom
                let after = viewModel.stepLiveZoom(by: delta)
                if after == before { return }
                if after == 1 { Haptics.snap() }
            }
        }
    }

    private func stopZoomRepeat() {
        zoomRepeat?.cancel()
        zoomRepeat = nil
    }

    // MARK: - Camera module

    private func cameraModule(_ facing: BrowserViewModel.CameraFacing) -> some View {
        let slotCount = facing == .front ? viewModel.frontSlotCount : viewModel.backSlotCount
        let queueIndex = facing == .front ? viewModel.frontQueueIndex : viewModel.backQueueIndex
        let isActive = viewModel.activeStreamFacing == facing
        let tint: Color = facing == .front ? .cyan : .green

        return Button {
            Haptics.tick()
            if let onOpenSources {
                onOpenSources()
            } else {
                onOpenControls(facing)
            }
        } label: {
            cameraModuleLabel(facing: facing, slotCount: slotCount, queueIndex: queueIndex, isActive: isActive, tint: tint)
        }
        .buttonStyle(PillPress())
        .accessibilityLabel(facing == .front ? "Front camera controls" : "Back camera controls")
        .contextMenu {
            moduleMenu(facing: facing, slotCount: slotCount)
        }
    }

    private func cameraModuleLabel(
        facing: BrowserViewModel.CameraFacing,
        slotCount: Int,
        queueIndex: Int,
        isActive: Bool,
        tint: Color
    ) -> some View {
        VStack(spacing: 3) {
            Text(facing == .front ? "FRONT" : "BACK")
                .font(.system(size: 7, weight: .heavy, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(isActive ? tint : .white.opacity(0.42))

            ZStack {
                if slotCount == 0 {
                    emptyPlaceholder
                } else {
                    ForEach(0..<max(slotCount, 1), id: \.self) { slot in
                        let primary = isPrimary(slot: slot, queueIndex: queueIndex, count: slotCount)
                        thumbnail(facing: facing, slot: slot)
                            .frame(width: primary ? 34 : 15, height: primary ? 34 : 15)
                            .clipShape(.rect(cornerRadius: primary ? 9 : 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: primary ? 9 : 4)
                                    .strokeBorder(
                                        primary && isActive ? tint.opacity(0.9) : .white.opacity(0.16),
                                        lineWidth: primary && isActive ? 1.6 : 0.8
                                    )
                            )
                            .offset(x: primary ? 0 : 13, y: primary ? 0 : -13)
                            .zIndex(primary ? 0 : 1)
                    }
                }

                // A pending Frame Check recommendation outranks the crop mark:
                // it says the still wants a look, cropped or not.
                if let attention = viewModel.frameNeedsAttention(facing: facing, slot: queueIndex) {
                    FrameAttentionBadge(kind: attention)
                        .offset(x: 14, y: 13)
                        .zIndex(2)
                } else if showsCropMark(facing: facing, queueIndex: queueIndex) {
                    Image(systemName: "crop")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.black.opacity(0.55), in: .circle)
                        .offset(x: 14, y: 13)
                        .zIndex(2)
                }

                if isActive {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 0.8))
                        .offset(x: -14, y: 13)
                        .zIndex(2)
                }
            }
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(tint.opacity(isActive ? 0.30 : 0))
                    .frame(width: 52, height: 52)
                    .blur(radius: 10)
            )
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: queueIndex)
            .animation(.easeOut(duration: 0.25), value: isActive)
        }
        .contentShape(.rect)
    }

    private func isPrimary(slot: Int, queueIndex: Int, count: Int) -> Bool {
        guard count > 1 else { return true }
        return slot == (queueIndex % count)
    }

    private func showsCropMark(facing: BrowserViewModel.CameraFacing, queueIndex: Int) -> Bool {
        guard viewModel.isStill(facing: facing, slot: queueIndex) else {
            // A clip carries no stored framing, so only a live zoom marks it.
            return (facing == .front ? viewModel.frontVideoZoom : viewModel.backVideoZoom) != 1
        }
        guard viewModel.behavior.settings.liveStillCrop else { return false }
        return !viewModel.stillCrop(facing: facing, slot: queueIndex).isIdentity
    }

    @ViewBuilder
    private func moduleMenu(facing: BrowserViewModel.CameraFacing, slotCount: Int) -> some View {
        let queueIndex = facing == .front ? viewModel.frontQueueIndex : viewModel.backQueueIndex
        if viewModel.isStill(facing: facing, slot: queueIndex) {
            Button {
                Haptics.tick()
                viewModel.openFrameCheck(facing: facing, slot: queueIndex)
            } label: {
                Label("Frame Check", systemImage: "viewfinder")
            }
        }

        if slotCount > 1 {
            Button {
                Haptics.firm()
                viewModel.swapSlots(facing: facing)
            } label: {
                Label("Swap 1 and 2", systemImage: "arrow.left.arrow.right")
            }
        }

        if slotCount > 0 {
            Button {
                Haptics.tick()
                Task { await viewModel.saveSlotToPhotos(facing: facing, slot: .one) }
            } label: {
                Label("Save media 1 to Photos", systemImage: "square.and.arrow.down")
            }

            Button(role: .destructive) {
                Haptics.warning()
                viewModel.clearSource(facing: facing)
            } label: {
                Label("Clear \(facing == .front ? "front" : "back")", systemImage: "trash")
            }
        }

        Button {
            Haptics.tick()
            onOpenControls(facing)
        } label: {
            Label("Open controls", systemImage: "slider.horizontal.3")
        }
    }

    private var emptyPlaceholder: some View {
        RoundedRectangle(cornerRadius: 9)
            .strokeBorder(
                style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])
            )
            .foregroundStyle(.white.opacity(0.28))
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.32))
            }
    }

    @ViewBuilder
    private func thumbnail(facing: BrowserViewModel.CameraFacing, slot: Int) -> some View {
        let image: UIImage? = facing == .front
            ? (slot == 0 ? viewModel.frontImage : viewModel.frontImage2)
            : (slot == 0 ? viewModel.backImage : viewModel.backImage2)
        let type: BrowserViewModel.SourceMediaType? = facing == .front
            ? (slot == 0 ? viewModel.frontSourceType : viewModel.frontSourceType2)
            : (slot == 0 ? viewModel.backSourceType : viewModel.backSourceType2)

        if let image {
            Color.black
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
        } else {
            Color.white.opacity(0.1)
                .overlay {
                    Image(systemName: type == .video ? "video.fill" : "photo.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
        }
    }

    // MARK: - Dragging

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    Haptics.tick()
                }
                drag = value.translation
            }
            .onEnded { value in
                isDragging = false

                let usableHeight = max(size.height - pillHeight - 24, 1)
                let currentY = 12 + usableHeight * placement.verticalFraction + value.translation.height
                let fraction = min(max((currentY - 12) / usableHeight, 0), 1)

                let currentCenterX = pillCenterX(in: size.width) + value.translation.width
                let goesLeft = currentCenterX < size.width / 2

                // Only a flick that carries on OUT of the edge it is settling
                // against tucks the pill. Crossing to the other side just moves it.
                let overshoot = goesLeft
                    ? -(currentCenterX - measuredWidth / 2)
                    : (currentCenterX + measuredWidth / 2) - size.width
                let flick = value.predictedEndTranslation.width
                let flicksOutward = goesLeft ? flick < -320 : flick > 320
                let shouldTuck = overshoot > 44 || flicksOutward

                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    drag = .zero
                    store.pillPlacement.verticalFraction = fraction
                    store.pillPlacement.isLeftEdge = goesLeft
                    store.pillPlacement.isTucked = shouldTuck
                }
                Haptics.snap()
            }
    }
}
