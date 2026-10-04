import SwiftUI
import PhotosUI

/// Shared Enable Media switch used at the top of Media Controls and in My Media.
///
/// All three surfaces (this card, the floating pill, and the other copy of this
/// card) read and write `viewModel.isMediaActive` through `setMediaActive`, so
/// they can never drift apart.
struct EnableMediaCard: View {
    @Bindable var viewModel: BrowserViewModel
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(viewModel.isMediaActive
                              ? MediaTheme.backTint.opacity(0.22)
                              : MediaTheme.well)
                        .frame(width: compact ? 34 : 40, height: compact ? 34 : 40)
                    Image(systemName: "power")
                        .font(.system(size: compact ? 14 : 16, weight: .bold))
                        .foregroundStyle(viewModel.isMediaActive ? MediaTheme.backTint : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Media")
                        .font(compact ? .subheadline.weight(.semibold) : .headline)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: Binding(
                    get: { viewModel.isMediaActive },
                    set: { viewModel.setMediaActive($0) }
                ))
                .labelsHidden()
                .tint(MediaTheme.backTint)
                .disabled(!viewModel.hasSource)
            }

            if viewModel.isMediaActive {
                Picker("Mode", selection: Binding(
                    get: { viewModel.mediaMode },
                    set: { newValue in
                        viewModel.mediaMode = newValue
                        viewModel.updateUserScripts()
                        viewModel.syncMediaToPage()
                    }
                )) {
                    ForEach(BrowserViewModel.MediaMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    if viewModel.hasFrontSource {
                        SourceBadge(text: "Front \(viewModel.frontSlotCount)", tint: MediaTheme.frontTint)
                    }
                    if viewModel.hasBackSource {
                        SourceBadge(text: "Back \(viewModel.backSlotCount)", tint: MediaTheme.backTint)
                    }
                    if !viewModel.hasFrontSource && !viewModel.hasBackSource {
                        Text("No sources loaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(compact ? 12 : 16)
        .background(MediaTheme.card, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    viewModel.isMediaActive ? MediaTheme.backTint.opacity(0.35) : MediaTheme.stroke,
                    lineWidth: 1
                )
        )
        .opacity(viewModel.hasSource ? 1 : 0.72)
    }

    private var statusLine: String {
        if !viewModel.hasSource {
            return "Load a photo or video to turn this on."
        }
        if viewModel.isMediaActive {
            if viewModel.hasFrontSource && viewModel.hasBackSource {
                return "Front and back each receive their own sequence."
            }
            return "Only one camera is loaded. The other falls back to it."
        }
        return "Off. Sites see the real camera until you switch this on."
    }
}

/// Bottom-half source tray for My Media: enable switch plus Front / Back columns.
///
/// Combination of a parked tray (rounded top, grabber) and a two-column layout
/// so both cameras stay on screen at once. Photo picks live here; videos still
/// assign from the library above.
struct SourceDeckView: View {
    @Bindable var viewModel: BrowserViewModel

    @State private var frontImagePicker1: PhotosPickerItem?
    @State private var frontImagePicker2: PhotosPickerItem?
    @State private var backImagePicker1: PhotosPickerItem?
    @State private var backImagePicker2: PhotosPickerItem?
    @State private var isSaving: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 12) {
                    EnableMediaCard(viewModel: viewModel, compact: true)

                    if viewModel.isConverting {
                        conversionBanner
                    }

                    if let status = viewModel.photoSaveStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        sourceColumn(
                            facing: .front,
                            title: "Front",
                            tint: MediaTheme.frontTint,
                            picker1: $frontImagePicker1,
                            picker2: $frontImagePicker2
                        )
                        sourceColumn(
                            facing: .back,
                            title: "Back",
                            tint: MediaTheme.backTint,
                            picker1: $backImagePicker1,
                            picker2: $backImagePicker2
                        )
                    }

                    if viewModel.behavior.settings.frontFaceButtons {
                        facePrepCard
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .safeAreaPadding(.bottom, 12)
        }
        .background {
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 22, topTrailing: 22))
                .fill(MediaTheme.card)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 22, topTrailing: 22))
                        .strokeBorder(MediaTheme.strokeStrong, lineWidth: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .onChange(of: frontImagePicker1) { _, item in
            loadPhoto(item, facing: .front, slot: .one) { frontImagePicker1 = nil }
        }
        .onChange(of: frontImagePicker2) { _, item in
            loadPhoto(item, facing: .front, slot: .two) { frontImagePicker2 = nil }
        }
        .onChange(of: backImagePicker1) { _, item in
            loadPhoto(item, facing: .back, slot: .one) { backImagePicker1 = nil }
        }
        .onChange(of: backImagePicker2) { _, item in
            loadPhoto(item, facing: .back, slot: .two) { backImagePicker2 = nil }
        }
    }

    private var conversionBanner: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(viewModel.conversionProgress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Text("\(Int(viewModel.conversionPercent * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(MediaTheme.accent)
            }
            ProgressView(value: viewModel.conversionPercent)
                .tint(MediaTheme.accent)
        }
        .padding(10)
        .background(MediaTheme.well, in: .rect(cornerRadius: 12))
    }

    private func sourceColumn(
        facing: BrowserViewModel.CameraFacing,
        title: String,
        tint: Color,
        picker1: Binding<PhotosPickerItem?>,
        picker2: Binding<PhotosPickerItem?>
    ) -> some View {
        let hasOne = facing == .front ? viewModel.frontSourceType != nil : viewModel.backSourceType != nil
        let hasTwo = facing == .front ? viewModel.frontSourceType2 != nil : viewModel.backSourceType2 != nil
        let slotCount = facing == .front ? viewModel.frontSlotCount : viewModel.backSlotCount

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(hasOne ? tint : Color.white.opacity(0.16))
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if slotCount > 0 {
                    SourceBadge(text: "\(slotCount)", tint: tint)
                }
            }

            slotCard(
                title: "Media 1",
                image: facing == .front ? viewModel.frontImage : viewModel.backImage,
                isVideo: facing == .front
                    ? viewModel.frontSourceType == .video
                    : viewModel.backSourceType == .video,
                hasSource: hasOne,
                picker: picker1,
                canPick: true,
                tint: tint,
                attention: viewModel.frameNeedsAttention(facing: facing, slot: 0),
                readiness: viewModel.frameReadiness(facing: facing, slot: 0),
                onFrameCheck: viewModel.isStill(facing: facing, slot: 0)
                    ? { viewModel.openFrameCheck(facing: facing, slot: 0) }
                    : nil,
                onSave: { save(facing: facing, slot: .one) },
                onRemove: {
                    viewModel.clearSource(facing: facing, slot: .one)
                    picker1.wrappedValue = nil
                    picker2.wrappedValue = nil
                }
            )

            slotCard(
                title: "Media 2",
                image: facing == .front ? viewModel.frontImage2 : viewModel.backImage2,
                isVideo: facing == .front
                    ? viewModel.frontSourceType2 == .video
                    : viewModel.backSourceType2 == .video,
                hasSource: hasTwo,
                picker: picker2,
                canPick: hasOne,
                tint: tint,
                attention: viewModel.frameNeedsAttention(facing: facing, slot: 1),
                readiness: viewModel.frameReadiness(facing: facing, slot: 1),
                onFrameCheck: viewModel.isStill(facing: facing, slot: 1)
                    ? { viewModel.openFrameCheck(facing: facing, slot: 1) }
                    : nil,
                onSave: { save(facing: facing, slot: .two) },
                onRemove: {
                    viewModel.clearSource(facing: facing, slot: .two)
                    picker2.wrappedValue = nil
                }
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(MediaTheme.well, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(MediaTheme.stroke, lineWidth: 1)
        )
    }

    private func slotCard(
        title: String,
        image: UIImage?,
        isVideo: Bool,
        hasSource: Bool,
        picker: Binding<PhotosPickerItem?>,
        canPick: Bool,
        tint: Color,
        attention: FrameVerdict.Kind? = nil,
        readiness: [FrameReadiness] = [],
        onFrameCheck: (() -> Void)? = nil,
        onSave: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                // The import check: a still that wants a look wears the badge,
                // and the thumbnail opens Frame Check.
                if let onFrameCheck {
                    Button {
                        Haptics.tick()
                        onFrameCheck()
                    } label: {
                        thumbnail(image: image, isVideo: isVideo, hasSource: hasSource)
                            .overlay(alignment: .topTrailing) {
                                if let attention {
                                    FrameAttentionBadge(kind: attention)
                                        .offset(x: 5, y: -5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Frame Check for \(title)")
                } else {
                    thumbnail(image: image, isVideo: isVideo, hasSource: hasSource)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(hasSource ? (isVideo ? "Video" : "Photo") : (canPick ? "Empty" : "Locked"))
                        .font(.caption.weight(.semibold))
                    Text(slotDetail(hasSource: hasSource, isVideo: isVideo, canPick: canPick, attention: attention))
                        .font(.caption2)
                        .foregroundStyle(attention == nil ? Color.secondary : FrameCheckTheme.color(for: attention ?? .fits))
                        .lineLimit(2)
                    // How this item stands against the sizes sites really ask
                    // for, so nothing has to be opened to find out.
                    if !readiness.isEmpty {
                        FrameReadinessRow(items: readiness, compact: true)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                if canPick {
                    PhotosPicker(selection: picker, matching: .images) {
                        Label(hasSource ? "Replace" : "Photo", systemImage: "photo")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(tint.opacity(0.16), in: .rect(cornerRadius: 8))
                            .foregroundStyle(tint)
                    }
                }

                if hasSource {
                    if let onFrameCheck {
                        Button {
                            Haptics.tick()
                            onFrameCheck()
                        } label: {
                            Image(systemName: "viewfinder")
                                .font(.caption.weight(.semibold))
                                .frame(width: 32, height: 28)
                                .background(MediaTheme.card, in: .rect(cornerRadius: 8))
                        }
                        .accessibilityLabel("Frame Check for \(title)")
                    }

                    if viewModel.nativePickerMode {
                        Button(action: onSave) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.caption.weight(.semibold))
                                .frame(width: 32, height: 28)
                                .background(MediaTheme.card, in: .rect(cornerRadius: 8))
                        }
                        .disabled(isSaving)
                        .accessibilityLabel("Save to Photos")
                    }

                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                            .font(.caption.weight(.semibold))
                            .frame(width: 32, height: 28)
                            .background(MediaTheme.card, in: .rect(cornerRadius: 8))
                    }
                    .accessibilityLabel("Remove \(title)")
                }
            }
        }
        .padding(8)
        .background(MediaTheme.card.opacity(0.65), in: .rect(cornerRadius: 10))
    }

    private func slotDetail(hasSource: Bool, isVideo: Bool, canPick: Bool, attention: FrameVerdict.Kind?) -> String {
        guard hasSource else { return canPick ? "Photo or video" : "Set Media 1 first" }
        if isVideo { return "From library · centred to fit" }
        switch attention {
        case .recentre: return "Frame Check: recentre or crop"
        case .expand: return "Frame Check: expand with AI"
        case .fits, .none: return "Ready for every common size"
        }
    }

    private func thumbnail(image: UIImage?, isVideo: Bool, hasSource: Bool) -> some View {
        Color(white: 0.12)
            .frame(width: 48, height: 36)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else {
                    Image(systemName: hasSource && isVideo ? "video.fill" : "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(.rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(MediaTheme.stroke, lineWidth: 1)
            )
    }

    private var facePrepCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Front face prep")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Make smirk and smile clips from a front still ahead of time. Live feed only — never on back, videos or uploads.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button {
                let slot: BrowserViewModel.SequenceSlot = viewModel.frontSourceType == .image ? .one : .two
                viewModel.prepareFaceClips(facing: .front, slot: slot)
            } label: {
                Label("Prepare smirk & smile", systemImage: "face.smiling")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(MediaTheme.frontTint.opacity(0.16), in: .rect(cornerRadius: 8))
                    .foregroundStyle(MediaTheme.frontTint)
            }
            .buttonStyle(.plain)
            .disabled(!(viewModel.frontSourceType == .image || viewModel.frontSourceType2 == .image))

            if let error = viewModel.facePrepError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if viewModel.facePrep.isReady {
                Text("Clips ready. Smirk / Smile appear on the pill during a front live feed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Until both clips exist, stills work exactly as they do today.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MediaTheme.well, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(MediaTheme.stroke, lineWidth: 1)
        )
    }

    private func save(facing: BrowserViewModel.CameraFacing, slot: BrowserViewModel.SequenceSlot) {
        guard !isSaving else { return }
        isSaving = true
        viewModel.photoSaveStatus = nil
        Task {
            await viewModel.saveSlotToPhotos(facing: facing, slot: slot)
            isSaving = false
        }
    }

    private func loadPhoto(
        _ item: PhotosPickerItem?,
        facing: BrowserViewModel.CameraFacing,
        slot: BrowserViewModel.SequenceSlot,
        clear: @escaping () -> Void
    ) {
        guard let item else { return }
        if slot == .two {
            let hasOne = facing == .front
                ? viewModel.frontSourceType != nil
                : viewModel.backSourceType != nil
            guard hasOne else {
                viewModel.photoSaveStatus = "Media 2 unlocks after Media 1 is set for that camera."
                clear()
                return
            }
        }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                viewModel.loadSource(image: image, facing: facing, slot: slot)
            }
            clear()
        }
    }
}
