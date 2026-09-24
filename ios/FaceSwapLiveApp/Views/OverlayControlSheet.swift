import SwiftUI

struct OverlayControlSheet: View {
    @Bindable var viewModel: BrowserViewModel

    @Environment(\.dismiss) private var dismiss
    @AppStorage(KeptStillStore.noticeSeenKey) private var seenKeptNotice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if !seenKeptNotice {
                        keptStillNotice
                    }
                    EnableMediaCard(viewModel: viewModel)

                    openMyMediaSection
                    sequenceOptionsSection
                    stealthSection

                    DeviceMatchedMediaSections(
                        viewModel: viewModel,
                        onOpenDeviceProfile: {
                            viewModel.opensDeviceProfileAfterDismiss = true
                            dismiss()
                        },
                        onOpenFrameCheck: { request in
                            // The editor is presented at the app root, so the
                            // sheet hands over as it closes.
                            viewModel.frameCheckAfterDismiss = request
                            dismiss()
                        }
                    )

                    visualOverlaySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(MediaTheme.canvas)
            .navigationTitle("Media Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(MediaTheme.accent)
                }
            }
        }
        .presentationBackground(MediaTheme.canvas)
        .task { Haptics.prepare() }
    }

    private var keptStillNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "photo.on.rectangle")
                .foregroundStyle(MediaTheme.accent)
            Text(KeptStillStore.notice)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                seenKeptNotice = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14)
        .padding(.vertical, 4)
        .background(MediaTheme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MediaTheme.stroke, lineWidth: 1))
    }

    private var openMyMediaSection: some View {
        MediaSection(
            title: "Library",
            systemImage: "photo.on.rectangle.angled",
            footnote: "Opens the My Media tab. Front and back sources live there."
        ) {
            Button {
                // The tab switch waits for the sheet to actually close, the
                // same chained hand-over the audit and Frame Check paths use.
                viewModel.opensMyMediaAfterDismiss = true
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MediaTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(MediaTheme.accent.opacity(0.14), in: .rect(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open My Media")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Browse the library and assign videos to sequences")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    private var sequenceOptionsSection: some View {
        MediaSection(
            title: "Sequence Options",
            systemImage: "rectangle.stack",
            footnote: "Each camera serves media 1, then media 2 (if set), then wraps. Front and back queues are independent."
        ) {
            MediaRow(title: "Default camera if unspecified", detail: "Used when a site does not name front or back.") {
                Picker("", selection: Binding(
                    get: { viewModel.defaultFacingWhenUnspecified },
                    set: { newValue in
                        viewModel.defaultFacingWhenUnspecified = newValue
                        if viewModel.isMediaActive { viewModel.syncMediaToPage() }
                    }
                )) {
                    Text("Front").tag(BrowserViewModel.CameraFacing.front)
                    Text("Back").tag(BrowserViewModel.CameraFacing.back)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(MediaTheme.accent)
            }

            MediaRow(title: "When to advance media") {
                Picker("", selection: Binding(
                    get: { viewModel.advanceMode },
                    set: { newValue in
                        viewModel.advanceMode = newValue
                        if viewModel.isMediaActive { viewModel.syncMediaToPage() }
                    }
                )) {
                    ForEach(BrowserViewModel.AdvanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(MediaTheme.accent)
            }

            Button(role: .destructive) {
                viewModel.clearAllSequences()
            } label: {
                Label("Clear All Sequences", systemImage: "trash.circle")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
            .disabled(!viewModel.hasSource)
        }
    }

    private var stealthSection: some View {
        MediaSection(
            title: "Stealth",
            systemImage: "eye.slash",
            footnote: "A page can always tell a scripted file hand-off from a real one. Native Picker Mode is the only way to pass that check, because iOS delivers the file itself."
        ) {
            MediaRow(
                title: "Native Picker Mode",
                detail: "iOS hands the file over itself, so nothing looks automated. Costs one tap per capture.",
                withDivider: viewModel.nativePickerMode
            ) {
                Toggle("", isOn: Binding(
                    get: { viewModel.nativePickerMode },
                    set: { newValue in
                        viewModel.nativePickerMode = newValue
                        viewModel.applyLiveStealthOptions()
                    }
                ))
                .labelsHidden()
                .tint(MediaTheme.accent)
            }

            if viewModel.nativePickerMode {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Camera buttons", selection: Binding(
                        get: { viewModel.captureButtonHandling },
                        set: { newValue in
                            viewModel.captureButtonHandling = newValue
                            viewModel.applyLiveStealthOptions()
                        }
                    )) {
                        ForEach(BrowserViewModel.CaptureButtonHandling.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(MediaTheme.accent)

                    Text(viewModel.captureButtonHandling.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.5)
                }
            }

            MediaRow(
                title: "Accessor Hardening",
                detail: "Leaves the page's own file accessor and built-in input methods untouched.",
                withDivider: viewModel.accessorHardening
            ) {
                Toggle("", isOn: Binding(
                    get: { viewModel.accessorHardening },
                    set: { newValue in
                        viewModel.accessorHardening = newValue
                        if !newValue { viewModel.maskWrappersAsNative = false }
                        viewModel.applyStealthOptionsRequiringReload()
                    }
                ))
                .labelsHidden()
                .tint(MediaTheme.accent)
            }

            if viewModel.accessorHardening {
                MediaRow(
                    title: "Report wrappers as built-in",
                    detail: "Trade-off: the disguise itself can be spotted by some checks."
                ) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.maskWrappersAsNative },
                        set: { newValue in
                            viewModel.maskWrappersAsNative = newValue
                            viewModel.applyStealthOptionsRequiringReload()
                        }
                    ))
                    .labelsHidden()
                    .tint(MediaTheme.accent)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(viewModel.nativePickerMode || viewModel.accessorHardening ? MediaTheme.backTint : .orange)
                Text(viewModel.stealthStatusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)

            if let notice = viewModel.stealthNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(MediaTheme.accent)
                    .padding(.bottom, 4)
            }
        }
    }

    private var visualOverlaySection: some View {
        MediaSection(
            title: "Visual Overlay",
            systemImage: "rectangle.on.rectangle",
            footnote: "Shows the uploaded media directly on top of the browser view as a visual cover.",
            startsExpanded: false
        ) {
            MediaRow(
                title: "Visual Overlay",
                detail: "Off by default. A cover for you — sites never see it.",
                withDivider: viewModel.isOverlayActive
            ) {
                Toggle("", isOn: $viewModel.isOverlayActive)
                    .labelsHidden()
                    .tint(MediaTheme.accent)
                    .disabled(!viewModel.hasSource)
            }

            if viewModel.isOverlayActive {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Opacity")
                            .font(.subheadline.weight(.medium))
                        Slider(value: $viewModel.overlayOpacity, in: 0.1...1.0, step: 0.05)
                            .tint(MediaTheme.accent)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}
