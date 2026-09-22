import SwiftUI
import UIKit

/// The settings groups added by the device-matched media work.
///
/// Renders inside Media Controls' ScrollView as MediaSection cards rather than
/// List sections, so header rhythm, card surface and dividers all match the
/// rest of the sheet. Behaviour is unchanged — only the chrome is new.
struct DeviceMatchedMediaSections: View {
    @Bindable var viewModel: BrowserViewModel
    var onOpenDeviceProfile: () -> Void
    /// Hands a still over to the full-screen Frame Check as the sheet closes.
    var onOpenFrameCheck: (FrameCheckRequest) -> Void

    @State private var showMotionPreview: Bool = false
    @State private var showResetConfirm: Bool = false

    /// Slider value while a drag is in flight, so the page is written once on release.
    @State private var holdDraft: Double?

    /// Version text while it is being typed, so the page is written once on commit.
    @State private var versionDraft: String?

    private var store: MediaBehaviorStore { viewModel.behavior }

    private var settings: Binding<MediaBehaviorSettings> {
        Binding(
            get: { store.settings },
            set: { newValue in
                store.settings = newValue
                viewModel.applyBehaviorSettings()
            }
        )
    }

    var body: some View {
        VStack(spacing: 22) {
            deviceProfileSection
            requestPromptSection
            motionSection
            liveCropSection
            sessionSection
            hardwareAlignmentSection
            resetSection
        }
    }

    // MARK: - 1. Device profile

    private var deviceProfileSection: some View {
        MediaSection(
            title: "Hardware Reference",
            systemImage: "iphone.gen3.radiowaves.left.and.right",
            footnote: "Anything sent is checked against this sheet first and pulled back to the nearest genuine value if it falls outside."
        ) {
            MediaRow(
                title: "Use audited hardware",
                detail: "Sites see the \(store.audit.cameras.count) cameras your phone really reports, in the same order, with stable identifiers."
            ) {
                Toggle("", isOn: settings.useAuditProfile)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            Button(action: onOpenDeviceProfile) {
                HStack(spacing: 12) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MediaTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(MediaTheme.accent.opacity(0.14), in: .rect(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Device Profile")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(store.audit.deviceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) {
                Divider().opacity(0.5)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Safari version")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    TextField(
                        store.audit.web.safariVersion,
                        text: Binding(
                            get: { versionDraft ?? store.settings.safariVersionOverride },
                            set: { versionDraft = $0 }
                        )
                    )
                    .font(.system(size: 13, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(maxWidth: 110)
                    .onSubmit { commitVersion() }
                }
                Text("Reported as \(store.audit.web.safariVersion). Leave empty for the audited value. The photo stamp follows it too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if versionDraft != nil,
                   versionDraft != store.settings.safariVersionOverride {
                    Button("Apply version") { commitVersion() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MediaTheme.accent)
                }
            }
            .padding(.vertical, 9)
        }
    }

    /// Writes the typed version through, then clears the draft.
    private func commitVersion() {
        guard let draft = versionDraft else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        versionDraft = nil
        guard trimmed != store.settings.safariVersionOverride else { return }
        store.settings.safariVersionOverride = trimmed
        viewModel.applyBehaviorSettings()
    }

    // MARK: - 2. Request prompt

    private var requestPromptSection: some View {
        MediaSection(
            title: "Request Prompt",
            systemImage: "bell.badge",
            footnote: "If you don't touch the card it proceeds on the site's own defaults when the hold runs out. A request never hangs or fails because you looked away."
        ) {
            MediaRow(
                title: "Ask for live camera",
                detail: "Shows what the site asked for before the feed starts."
            ) {
                Toggle("", isOn: settings.promptLiveRequests)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            MediaRow(
                title: "Ask for photo and file requests",
                detail: "Only picks which of your items goes out. The file itself is never changed.",
                withDivider: store.settings.promptLiveRequests || store.settings.promptFileRequests
            ) {
                Toggle("", isOn: settings.promptFileRequests)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            if store.settings.promptLiveRequests || store.settings.promptFileRequests {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Hold")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int(holdDraft ?? store.settings.promptHoldSeconds))s")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { holdDraft ?? store.settings.promptHoldSeconds },
                            set: { holdDraft = $0 }
                        ),
                        in: 5...45,
                        step: 5,
                        onEditingChanged: { isEditing in
                            guard !isEditing, let draft = holdDraft else { return }
                            holdDraft = nil
                            guard draft != store.settings.promptHoldSeconds else { return }
                            store.settings.promptHoldSeconds = draft
                            viewModel.applyBehaviorSettings()
                        }
                    )
                    .tint(MediaTheme.accent)

                    if !store.silencedHosts.isEmpty {
                        Button(role: .destructive) {
                            store.clearSilencedHosts()
                        } label: {
                            Label("Clear \(store.silencedHosts.count) silenced site(s)", systemImage: "bell.badge.slash")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - 4. Motion

    private var motionSection: some View {
        MediaSection(
            title: "Live Feed Motion",
            systemImage: "waveform.path",
            footnote: "A still shown as a live camera view drifts, breathes and re-grips like a hand-held phone instead of sitting frozen. It crops by only as much as the movement needs, and eases itself off if the phone starts working too hard. Videos in the feed play exactly as before."
        ) {
            MediaRow(
                title: "Motion in the live feed",
                detail: "Live camera view only. Photo and file uploads are never touched.",
                withDivider: store.settings.liveMotion
            ) {
                Toggle("", isOn: settings.liveMotion)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            if store.settings.liveMotion {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Strength", selection: settings.motionStrength) {
                        ForEach(MotionStrength.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(store.settings.motionStrength.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        withAnimation(.spring(duration: 0.32)) {
                            showMotionPreview.toggle()
                        }
                    } label: {
                        Label(
                            showMotionPreview ? "Hide preview" : "Preview motion",
                            systemImage: showMotionPreview ? "eye.slash" : "eye"
                        )
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MediaTheme.accent)
                    }
                    .buttonStyle(.plain)

                    if showMotionPreview {
                        MotionPreviewView(
                            image: previewImage,
                            strength: store.settings.motionStrength,
                            showsGrain: store.settings.sensorGrain,
                            showsWarmth: store.settings.skinRealism
                        )
                        .frame(height: 190)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 12))
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Live still crop

    private var liveCropSection: some View {
        MediaSection(
            title: "Live Still Crop",
            systemImage: "crop",
            footnote: "Live camera view of a still only. Each preview is drawn exactly as the site will receive it, in this camera's default frame. File, photo and native camera uploads are never touched."
        ) {
            MediaRow(
                title: "Crop stills in the live feed",
                detail: "Drag to pan, pinch to zoom. Off is today's cover-fit; any change below turns it on.",
                withDivider: hasAnyStill
            ) {
                Toggle("", isOn: settings.liveStillCrop)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            if hasAnyStill {
                VStack(alignment: .leading, spacing: 18) {
                    frameEditor(title: "Front · Media 1", facing: .front, slot: 0)
                    frameEditor(title: "Front · Media 2", facing: .front, slot: 1)
                    frameEditor(title: "Back · Media 1", facing: .back, slot: 0)
                    frameEditor(title: "Back · Media 2", facing: .back, slot: 1)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var hasAnyStill: Bool {
        viewModel.isStill(facing: .front, slot: 0)
            || viewModel.isStill(facing: .front, slot: 1)
            || viewModel.isStill(facing: .back, slot: 0)
            || viewModel.isStill(facing: .back, slot: 1)
    }

    @ViewBuilder
    private func frameEditor(
        title: String,
        facing: BrowserViewModel.CameraFacing,
        slot: Int
    ) -> some View {
        if viewModel.isStill(facing: facing, slot: slot) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Haptics.tick()
                        onOpenFrameCheck(FrameCheckRequest(facing: facing, slot: slot))
                    } label: {
                        Label("Open Frame Check", systemImage: "viewfinder")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MediaTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                // The frame in play: what a site is asking for now, else the
                // running feed's own canvas, else this camera's default.
                FrameCheckPanel(
                    viewModel: viewModel,
                    facing: facing,
                    slot: slot,
                    target: viewModel.workingFrameTarget(facing: facing),
                    compact: true,
                    startsPaused: true,
                    showsCropHint: false,
                    onExpandWithAI: {
                        onOpenFrameCheck(FrameCheckRequest(facing: facing, slot: slot, autoExpand: true))
                    }
                )
            }
        }
    }

    // MARK: - Session

    private var sessionSection: some View {
        MediaSection(
            title: "Session",
            systemImage: "rectangle.on.rectangle.angled",
            footnote: "Each of these can be turned off on its own. All off leaves today's wrap, no overlay, and no recap."
        ) {
            MediaRow(
                title: "Site-observed HUD",
                detail: "Tiny readout of size, rate, format and camera name as the page is told them. The site cannot see it."
            ) {
                Toggle("", isOn: settings.showObservedHUD)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            MediaRow(
                title: "Turn off after one full pass",
                detail: "After every loaded item on cameras this page used has been served, and the live feed has stopped, Enable Media turns off. Queues do not wrap."
            ) {
                Toggle("", isOn: settings.autoOffAfterOnePass)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            MediaRow(
                title: "Show recap when injection turns off",
                detail: "Honest asked-vs-sent timeline. Does not block browsing."
            ) {
                Toggle("", isOn: settings.showSequenceRecap)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            MediaRow(
                title: "Front face buttons",
                detail: "Optional smirk/smile prep on a front still. Not generated at request time. Off = no extra buttons.",
                withDivider: store.settings.frontFaceButtons
            ) {
                Toggle("", isOn: settings.frontFaceButtons)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            if store.settings.frontFaceButtons {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        viewModel.prepareFaceClips(facing: .front, slot: .one)
                    } label: {
                        Label("Prepare smirk & smile from front still", systemImage: "face.smiling")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(MediaTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(!(viewModel.frontSourceType == .image))

                    if let error = viewModel.facePrepError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if viewModel.facePrep.isReady {
                        Text("Clips ready. Smirk / Smile appear on the pill during a front live feed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Until both clips exist, stills work exactly as they do today.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    /// Whatever is loaded, so the preview is never blank when only slot 2 is filled.
    private var previewImage: UIImage? {
        viewModel.frontImage
            ?? viewModel.frontImage2
            ?? viewModel.backImage
            ?? viewModel.backImage2
    }

    // MARK: - 6. Hardware alignment

    private var hardwareAlignmentSection: some View {
        MediaSection(
            title: "Hardware Alignment",
            systemImage: "slider.horizontal.3",
            footnote: "Everything refused is written to the request log so you can review it and switch the check back off if a site breaks."
        ) {
            MediaRow(
                title: "Skin and surface realism",
                detail: "A light warmth pass, applied once as the feed starts."
            ) {
                Toggle("", isOn: settings.skinRealism)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            MediaRow(
                title: "Exposure breathing",
                detail: "Brightness and warmth drift, plus the settle after a hand-over. Live feed only."
            ) {
                Toggle("", isOn: settings.exposureBreathing)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            MediaRow(
                title: "Sensor character",
                detail: "Grain matched to your sensor, settled into the picture rather than crawling over it."
            ) {
                Toggle("", isOn: settings.sensorGrain)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            MediaRow(
                title: "Natural frame timing",
                detail: "Irregular gaps between frames instead of a metronome."
            ) {
                Toggle("", isOn: settings.frameTimingJitter)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            MediaRow(
                title: "Graphics and screen answers",
                detail: "\(store.audit.web.glRenderer) · \(store.audit.web.screenWidth)×\(store.audit.web.screenHeight) · \(store.audit.web.hardwareConcurrency) cores."
            ) {
                Toggle("", isOn: settings.graphicsAlignment)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            MediaRow(
                title: "Capability checking",
                detail: "Refuses impossible requests exactly as your phone refused them.",
                withDivider: true
            ) {
                Toggle("", isOn: settings.capabilityValidation)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            if store.settings.capabilityValidation {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.audit.rejectedProbes.isEmpty
                             ? "No refusals recorded in the audit."
                             : "Refuses: \(store.audit.rejectedProbes.map(\.name).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let refusal = viewModel.lastRefusalSummary {
                            Text("Last refusal · \(refusal)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.5)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(MediaTheme.backTint)
                Text("None of these apply to the file picker, the photo chooser, or the native camera button.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Pill + reset

    private var resetSection: some View {
        MediaSection(title: "Controls", systemImage: "switch.2") {
            MediaRow(
                title: "Floating control pill",
                detail: "Quick access over the browser. This sheet stays the place for detailed setup.",
                withDivider: true
            ) {
                Toggle("", isOn: settings.showControlPill)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
            }

            if store.settings.showControlPill && store.pillPlacement.isTucked {
                Button {
                    store.pillPlacement.isTucked = false
                } label: {
                    Label("Bring the pill back", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MediaTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.5)
                }
            }

            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset media behaviour", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
            .overlay(alignment: .bottom) {
                Divider().opacity(0.5)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: store.settings.isPreUpgradeBehavior ? "checkmark.circle.fill" : "sparkles")
                    .font(.caption)
                    .foregroundStyle(store.settings.isPreUpgradeBehavior ? Color.secondary : MediaTheme.backTint)
                Text(store.settings.isPreUpgradeBehavior
                     ? "Everything off — the app behaves exactly as it did before."
                     : "Active. Every switch above can be turned off individually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .confirmationDialog(
            "Reset media behaviour",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Turn everything off", role: .destructive) {
                store.resetToPreUpgradeBehavior()
                viewModel.applyBehaviorSettings()
            }
            Button("Restore shipped defaults") {
                store.restoreShippedDefaults()
                viewModel.applyBehaviorSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turning everything off returns the app to exactly its pre-upgrade behaviour. Your media, sequences and stealth settings are not affected.")
        }
    }
}
