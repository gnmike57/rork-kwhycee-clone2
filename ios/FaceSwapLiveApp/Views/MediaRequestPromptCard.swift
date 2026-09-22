import SwiftUI

/// Compact card shown while a site's media request waits on the user.
///
/// Always opens on Back when that queue has media. The hold is a maximum: when
/// it runs out the request proceeds on the site's own defaults, not this preview.
struct MediaRequestPromptCard: View {
    let prompt: MediaRequestPrompt
    let viewModel: BrowserViewModel
    let holdSeconds: Double
    let onResolve: (MediaRequestDecision) -> Void
    let onSilenceHost: () -> Void

    @State private var remaining: Double
    @State private var chosenFacing: BrowserViewModel.CameraFacing
    @State private var chosenSlot: Int
    @State private var hasAppeared: Bool = false
    @State private var showDetails: Bool = true

    private let tick: Double = 0.05

    init(
        prompt: MediaRequestPrompt,
        viewModel: BrowserViewModel,
        holdSeconds: Double,
        onResolve: @escaping (MediaRequestDecision) -> Void,
        onSilenceHost: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.viewModel = viewModel
        self.holdSeconds = holdSeconds
        self.onResolve = onResolve
        self.onSilenceHost = onSilenceHost
        _remaining = State(initialValue: holdSeconds)
        let opening = viewModel.preferredPromptFacing()
        _chosenFacing = State(initialValue: opening)
        _chosenSlot = State(initialValue: viewModel.queueIndex(facing: opening))
    }

    private var progress: Double {
        guard holdSeconds > 0 else { return 0 }
        return max(0, min(1, remaining / holdSeconds))
    }

    private var slotCount: Int { viewModel.slotCount(facing: chosenFacing) }
    private var activeSlot: Int {
        min(max(0, chosenSlot), max(slotCount - 1, 0))
    }
    private var previewImage: UIImage? {
        viewModel.previewImage(facing: chosenFacing, slot: activeSlot)
    }
    private var isVideo: Bool {
        viewModel.sourceType(facing: chosenFacing, slot: activeSlot) == .video
    }
    private var hasChosenMedia: Bool {
        viewModel.sourceType(facing: chosenFacing, slot: activeSlot) != nil
    }
    /// The exact frame the feed will report for this ask, as the page draws it.
    private var liveTarget: FrameTarget {
        viewModel.frameTarget(prompt: prompt, facing: chosenFacing)
    }
    private var wouldRefuse: Bool {
        prompt.kind == .live && viewModel.wouldRefuseAsk(prompt, facing: chosenFacing)
    }
    private var canSend: Bool {
        if wouldRefuse { return true }
        return hasChosenMedia
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))

            ScrollView {
                VStack(spacing: 12) {
                    previewBlock
                    comparisonRows
                    if showDetails { extraDetails }
                    sequenceThumbs
                    facingPicker
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 420)

            actions
        }
        .background(cardBackground)
        .clipShape(.rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.5), radius: 26, y: 14)
        .padding(.horizontal, 14)
        .scaleEffect(hasAppeared ? 1 : 0.92)
        .opacity(hasAppeared ? 1 : 0)
        .task {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { hasAppeared = true }
            Haptics.tick()
            await runCountdown()
        }
        // Frame Check or the pill can move this camera's queue while the card
        // is up (an approved expansion lands as Media 2); the card follows so
        // the thumb it highlights is the one that will go out.
        .onChange(of: viewModel.queueIndex(facing: chosenFacing)) { _, index in
            chosenSlot = index
        }
    }

    private var cardBackground: some View {
        ZStack {
            Rectangle().fill(MediaTheme.card)
            Rectangle().fill(Color.black.opacity(0.28))
            LinearGradient(
                colors: [
                    (chosenFacing == .front ? MediaTheme.frontTint : MediaTheme.backTint).opacity(0.16),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill((chosenFacing == .front ? MediaTheme.frontTint : MediaTheme.backTint).opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: prompt.kind.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(chosenFacing == .front ? MediaTheme.frontTint : MediaTheme.backTint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(prompt.host.isEmpty ? "This page" : prompt.host)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()

            Text("\(Int(remaining.rounded(.up)))s")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Preview

    /// Live asks get Frame Check: the exact frame the page will draw, the
    /// verdict and the zoom slider. File asks keep showing the untouched item.
    private var previewBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if prompt.kind == .live {
                FrameCheckPanel(
                    viewModel: viewModel,
                    facing: chosenFacing,
                    slot: activeSlot,
                    target: liveTarget,
                    compact: true,
                    onExpandWithAI: {
                        Haptics.tick()
                        viewModel.openFrameCheck(
                            facing: chosenFacing,
                            slot: activeSlot,
                            target: liveTarget,
                            autoExpand: true
                        )
                    }
                )
            } else {
                filePreview
            }

            if wouldRefuse {
                Label("This size is outside what this camera grants. Send will refuse the ask, the same as the phone would.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var filePreview: some View {
        Color.black
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .overlay {
                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: isVideo ? "video.fill" : "photo")
                            .font(.title3)
                        Text(isVideo ? "Video" : "Empty")
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.35))
                }
            }
            .clipShape(.rect(cornerRadius: 14))
            .overlay(alignment: .bottomTrailing) {
                if isVideo {
                    Image(systemName: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                Text(hasChosenMedia ? "Original file — unchanged" : "Nothing loaded")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: .capsule)
                    .padding(8)
            }
    }

    // MARK: - Requested vs. sent

    private var comparisonRows: some View {
        VStack(spacing: 0) {
            if prompt.kind == .live {
                comparisonRow(
                    label: "Camera",
                    requested: prompt.requestedFacingText,
                    sending: chosenFacing == .front ? "Front" : "Back",
                    wasAsked: prompt.requestedFacing != nil
                )
                comparisonRow(
                    label: "Size",
                    requested: exactAskedSize,
                    sending: viewModel.sendingSizeText(prompt: prompt, facing: chosenFacing),
                    wasAsked: prompt.requestedWidth != nil || prompt.requestedHeight != nil
                )
                comparisonRow(
                    label: "Frame rate",
                    requested: prompt.requestedFrameRateText,
                    sending: viewModel.sendingFrameRateText(prompt: prompt, facing: chosenFacing),
                    wasAsked: prompt.requestedFrameRate != nil
                )
                if prompt.wantsAudio {
                    comparisonRow(
                        label: "Sound",
                        requested: "Requested",
                        sending: "Silent track",
                        wasAsked: true
                    )
                }
            } else {
                comparisonRow(
                    label: "Wants",
                    requested: acceptSummary,
                    sending: viewModel.sendingItemLabel(facing: chosenFacing, slot: activeSlot),
                    wasAsked: !(prompt.accept ?? "").isEmpty
                )
                comparisonRow(
                    label: "Camera",
                    requested: prompt.requestedFacingText,
                    sending: chosenFacing == .front ? "Front" : "Back",
                    wasAsked: prompt.requestedFacing != nil
                )
            }
        }
    }

    private var exactAskedSize: String {
        switch (prompt.requestedWidth, prompt.requestedHeight) {
        case let (w?, h?): return "\(w)×\(h)"
        case let (w?, nil): return "\(w)×—"
        case let (nil, h?): return "—×\(h)"
        default: return "Any size"
        }
    }

    private func comparisonRow(
        label: String,
        requested: String,
        sending: String,
        wasAsked: Bool
    ) -> some View {
        let differs = wasAsked && requested.lowercased() != sending.lowercased()
        return HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 76, alignment: .leading)

            Text(requested)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)

            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.25))

            Text(sending)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(differs ? Color.orange : Color.white.opacity(0.9))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var extraDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            detailLine("Page", pagePath)
            detailLine("Camera permission", viewModel.cameraPermissionText(host: prompt.host))
            if prompt.wantsAudio {
                detailLine("Microphone", viewModel.microphonePermissionText(host: prompt.host))
            }
            detailLine("Page can already see", viewModel.learnedDevicesText(host: prompt.host))
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
    }

    private var pagePath: String {
        guard let url = URL(string: prompt.pageURL) else { return prompt.pageURL }
        let path = url.path
        return path.isEmpty || path == "/" ? "/" : path
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var acceptSummary: String {
        guard let accept = prompt.accept, !accept.isEmpty else { return "Any file" }
        let wantsVideo = accept.contains("video")
        let wantsImage = accept.contains("image")
        if wantsVideo && wantsImage { return "Video or image" }
        if wantsVideo { return "Video" }
        if wantsImage { return "Image" }
        return accept
    }

    // MARK: - Thumbs + facing

    private var sequenceThumbs: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(slotCount, 1), id: \.self) { slot in
                let selected = hasChosenMedia && activeSlot == slot
                Button {
                    Haptics.tick()
                    chosenSlot = slot
                    viewModel.setQueueIndex(slot, facing: chosenFacing)
                } label: {
                    thumb(slot: slot, selected: selected)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.sourceType(facing: chosenFacing, slot: slot) == nil)
            }
            Spacer(minLength: 0)
        }
    }

    private func thumb(slot: Int, selected: Bool) -> some View {
        let image = viewModel.previewImage(facing: chosenFacing, slot: slot)
        let type = viewModel.sourceType(facing: chosenFacing, slot: slot)
        return Color(white: 0.12)
            .frame(width: 52, height: 40)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.28))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if type == .video {
                    Image(systemName: "video.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                        .padding(3)
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.white.opacity(0.9) : Color.white.opacity(0.12), lineWidth: selected ? 1.6 : 0.8)
            )
            .overlay(alignment: .topLeading) {
                Text("\(slot + 1)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.45), in: .capsule)
                    .padding(3)
            }
    }

    private var facingPicker: some View {
        HStack(spacing: 8) {
            Text("Camera")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 76, alignment: .leading)

            ForEach(BrowserViewModel.CameraFacing.allCases) { facing in
                Button {
                    Haptics.tick()
                    chosenFacing = facing
                    chosenSlot = viewModel.queueIndex(facing: facing)
                } label: {
                    Text(facing == .front ? "Front" : "Back")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(chosenFacing == facing ? .black : .white.opacity(0.7))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                chosenFacing == facing
                                    ? (facing == .front ? MediaTheme.frontTint : MediaTheme.backTint).opacity(0.95)
                                    : Color.white.opacity(0.08)
                            )
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    Haptics.warning()
                    onResolve(MediaRequestDecision(facing: nil, slot: nil, cancelled: true))
                } label: {
                    Text("Block")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                Button {
                    if wouldRefuse {
                        Haptics.warning()
                        onResolve(MediaRequestDecision(facing: nil, slot: nil, cancelled: true))
                    } else {
                        Haptics.success()
                        onResolve(
                            MediaRequestDecision(
                                facing: chosenFacing,
                                slot: activeSlot,
                                cancelled: false
                            )
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(wouldRefuse ? "Refuse" : "Send")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                        countdownRing
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Capsule().fill(Color.white.opacity(canSend ? 0.92 : 0.35)))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }

            Button {
                Haptics.tick()
                onSilenceHost()
                if wouldRefuse {
                    onResolve(MediaRequestDecision(facing: nil, slot: nil, cancelled: true))
                } else {
                    onResolve(
                        MediaRequestDecision(facing: chosenFacing, slot: chosenSlot, cancelled: false)
                    )
                }
            } label: {
                Text("Don't ask again for this site")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(prompt.host.isEmpty || !canSend)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, 4)
    }

    private var countdownRing: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progress < 0.25 ? Color.orange : Color.black.opacity(0.55),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 15, height: 15)
        .animation(.linear(duration: tick), value: progress)
    }

    /// Counts against a fixed end moment, so the ring and the number on the card
    /// always agree with when the page will actually move on.
    private func runCountdown() async {
        guard holdSeconds > 0 else {
            remaining = 0
            onResolve(.proceed)
            return
        }
        let end = Date().addingTimeInterval(holdSeconds)
        while true {
            let left = end.timeIntervalSinceNow
            if left <= 0 { break }
            remaining = min(left, holdSeconds)
            try? await Task.sleep(for: .seconds(min(tick, left)))
            if Task.isCancelled { return }
        }
        remaining = 0
        // Hold expired: proceed on the site's own defaults, unchanged.
        onResolve(.proceed)
    }
}
