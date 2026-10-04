import SwiftUI
import PhotosUI
import AVKit

struct MyMediaView: View {
    @Environment(DeviceProfileManager.self) private var profileManager
    @Bindable var videoLibrary: VideoLibraryService
    @Bindable var browserViewModel: BrowserViewModel
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var importError: String?
    @State private var videoToDelete: SavedVideo?
    @State private var showDeleteConfirm: Bool = false
    @State private var selectedVideo: SavedVideo?
    @State private var renamingVideo: SavedVideo?
    @State private var renameText: String = ""

    var onSelectVideo: ((SavedVideo, URL) -> Void)?
    /// Optional sequence-aware assign: (video, facing front/back as string via URL choice, slot).
    var onSelectSequence: ((SavedVideo, BrowserViewModel.CameraFacing, BrowserViewModel.SequenceSlot) -> Void)?
    /// Whether Media 1 is already filled for a facing — gates Media 2 assignment.
    var isSlotOneFilled: ((BrowserViewModel.CameraFacing) -> Bool)?

    private var isImporting: Bool { videoLibrary.activeJob != nil }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Group {
                        if videoLibrary.videos.isEmpty && !isImporting {
                            emptyState
                        } else {
                            videoList
                        }
                    }
                    .frame(height: geo.size.height * 0.48)

                    SourceDeckView(viewModel: browserViewModel)
                        .frame(maxHeight: .infinity)
                }
            }
            .background(MediaTheme.canvas)
            .navigationTitle("My Media")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    PhotosPicker(selection: $videoPickerItem, matching: .videos) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(MediaTheme.accent)
                    }
                    .disabled(isImporting)
                }
            }
        }
        .onChange(of: videoPickerItem) { _, item in
            guard let item else { return }
            importFromPicker(item)
        }
        .alert("Delete Video?", isPresented: $showDeleteConfirm, presenting: videoToDelete) { video in
            Button("Delete", role: .destructive) {
                withAnimation(.spring(duration: 0.3)) {
                    videoLibrary.deleteVideo(video)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { video in
            Text("This will permanently remove \"\(video.name)\" and its prepared version.")
        }
        .alert("Rename Video", isPresented: .init(
            get: { renamingVideo != nil },
            set: { if !$0 { renamingVideo = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let video = renamingVideo, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    videoLibrary.renameVideo(video, to: renameText.trimmingCharacters(in: .whitespaces))
                }
                renamingVideo = nil
            }
            Button("Cancel", role: .cancel) { renamingVideo = nil }
        }
        .alert("Import Failed", isPresented: .init(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "The video could not be imported.")
        }
        .sheet(item: $selectedVideo) { video in
            VideoDetailSheet(
                video: videoLibrary.videos.first { $0.id == video.id } ?? video,
                videoLibrary: videoLibrary,
                onUse: onSelectVideo,
                onSelectSequence: onSelectSequence,
                isSlotOneFilled: isSlotOneFilled
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(MediaTheme.accent.opacity(0.14))
                    .frame(width: 88, height: 88)
                Image(systemName: "film.stack")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(MediaTheme.accent)
            }

            VStack(spacing: 6) {
                Text("Nothing imported yet")
                    .font(.headline)
                Text("Import a clip and it's prepared for\nthe camera it belongs to.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            PhotosPicker(selection: $videoPickerItem, matching: .videos) {
                Label("Import Video", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(MediaTheme.accent, in: Capsule())
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal)
    }

    private var videoList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let job = videoLibrary.activeJob {
                    importProgressCard(job)
                }

                ForEach(videoLibrary.videos) { video in
                    if videoLibrary.activeJob?.videoID != video.id {
                        videoCard(video)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    private func importProgressCard(_ job: ImportJob) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(MediaTheme.well, lineWidth: 4)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: job.progress)
                        .stroke(MediaTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: job.progress)
                    Text("\(Int(job.progress * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(MediaTheme.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(job.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(job.stage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let eta = job.etaText {
                        Text(eta)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if job.canCancel {
                    Button {
                        videoLibrary.cancelImport()
                        Haptics.tick()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(MediaTheme.well, in: .circle)
                    }
                    .buttonStyle(.plain)
                }
            }

            ProgressView(value: job.progress)
                .tint(MediaTheme.accent)
                .animation(.linear(duration: 0.25), value: job.progress)
        }
        .padding(14)
        .background(MediaTheme.card, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(MediaTheme.stroke, lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
    }

    private func videoCard(_ video: SavedVideo) -> some View {
        Button {
            selectedVideo = video
        } label: {
            HStack(spacing: 14) {
                thumbnailView(video)

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if video.originalWidth > 0 {
                            Text("\(video.originalWidth)×\(video.originalHeight)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        if video.originalDuration > 0 {
                            Text(formatDuration(video.originalDuration))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(formatFileSize(video.fileSizeBytes))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    SubjectStatusBadge(video: video)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(MediaTheme.card, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        video.preparationError != nil ? Color.orange.opacity(0.4) : MediaTheme.stroke,
                        lineWidth: 1
                    )
            )
        }
        .contextMenu {
            Button {
                renameText = video.name
                renamingVideo = video
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            if let subject = video.subject {
                Button {
                    reprepare(video, as: subject.opposite)
                } label: {
                    Label(
                        "Prepare for \(subject.opposite.cameraLabel) camera",
                        systemImage: subject.opposite.systemImage
                    )
                }
                .disabled(isImporting)
            }

            if video.preparationError != nil {
                Button {
                    reprepare(video, as: video.subject)
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .disabled(isImporting)
            }

            if video.isReady {
                let facing: BrowserViewModel.CameraFacing = video.subject == .person ? .front : .back
                Button {
                    onSelectSequence?(video, facing, .one)
                } label: {
                    Label("Use as \(facing == .front ? "Front" : "Back") 1", systemImage: "1.circle")
                }
                Button {
                    onSelectSequence?(video, facing, .two)
                } label: {
                    Label("Use as \(facing == .front ? "Front" : "Back") 2", systemImage: "2.circle")
                }
                .disabled(!(isSlotOneFilled?(facing) ?? true))
            }

            Divider()

            Button(role: .destructive) {
                videoToDelete = video
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func thumbnailView(_ video: SavedVideo) -> some View {
        Group {
            if let thumbURL = videoLibrary.thumbnailURL(for: video),
               let data = try? Data(contentsOf: thumbURL),
               let uiImage = UIImage(data: data) {
                Color(.tertiarySystemFill)
                    .frame(width: 72, height: 54)
                    .overlay {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 72, height: 54)
                    .overlay {
                        Image(systemName: "film")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }

    private func importFromPicker(_ item: PhotosPickerItem) {
        Task {
            guard let movie = try? await item.loadTransferable(type: VideoTransferable.self) else {
                videoPickerItem = nil
                importError = "The video could not be loaded from your photo library."
                return
            }

            let fileName = movie.url.lastPathComponent
            let name = fileName.components(separatedBy: ".").first ?? "Imported Video"

            let saved = await videoLibrary.importVideo(
                sourceURL: movie.url,
                name: name,
                profile: profileManager.activeProfile
            )

            // A clip that saved but could not be prepared reports itself on its
            // own row, so only a total failure needs the alert.
            if saved == nil, let error = videoLibrary.lastImportError {
                importError = error
            }
            videoPickerItem = nil
        }
    }

    private func reprepare(_ video: SavedVideo, as subject: MediaSubject?) {
        Task {
            await videoLibrary.prepare(video, as: subject, profile: profileManager.activeProfile)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// Says which camera a clip is for, or why it isn't ready.
///
/// Readiness is never implied by a row simply existing — a clip whose encode
/// failed says so, in the place the tick would otherwise be.
struct SubjectStatusBadge: View {
    let video: SavedVideo

    var body: some View {
        if let error = video.preparationError {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(2)
            }
            .foregroundStyle(.orange)
        } else if video.isPreparingNow {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Preparing…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else if let subject = video.subject {
            HStack(spacing: 6) {
                Label(
                    "\(subject.cameraLabel) camera",
                    systemImage: video.isReady ? "checkmark.circle.fill" : subject.systemImage
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(subject == .person ? MediaTheme.frontTint : MediaTheme.backTint)

                if let spec = video.preparedSpec {
                    Text(spec)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            HStack(spacing: 8) {
                if video.frontCameraFileName != nil {
                    Label("Front", systemImage: "camera.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MediaTheme.frontTint)
                }
                if video.backCameraFileName != nil {
                    Label("Back", systemImage: "camera.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MediaTheme.backTint)
                }
            }
        }
    }
}

struct VideoDetailSheet: View {
    let video: SavedVideo
    let videoLibrary: VideoLibraryService
    var onUse: ((SavedVideo, URL) -> Void)?
    var onSelectSequence: ((SavedVideo, BrowserViewModel.CameraFacing, BrowserViewModel.SequenceSlot) -> Void)?
    var isSlotOneFilled: ((BrowserViewModel.CameraFacing) -> Bool)?
    @Environment(\.dismiss) private var dismiss
    @Environment(DeviceProfileManager.self) private var profileManager
    @State private var player: AVPlayer?

    init(
        video: SavedVideo,
        videoLibrary: VideoLibraryService,
        onUse: ((SavedVideo, URL) -> Void)?,
        onSelectSequence: ((SavedVideo, BrowserViewModel.CameraFacing, BrowserViewModel.SequenceSlot) -> Void)?,
        isSlotOneFilled: ((BrowserViewModel.CameraFacing) -> Bool)?
    ) {
        self.video = video
        self.videoLibrary = videoLibrary
        self.onUse = onUse
        self.onSelectSequence = onSelectSequence
        self.isSlotOneFilled = isSlotOneFilled
    }

    private var subject: MediaSubject { video.subject ?? .person }

    private var facing: BrowserViewModel.CameraFacing {
        subject == .person ? .front : .back
    }

    private var currentURL: URL? {
        videoLibrary.preparedVideoURL(for: video) ?? videoLibrary.originalVideoURL(for: video)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    previewSection
                    subjectSection
                    specSection
                    useButton
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
            .background(MediaTheme.canvas)
            .navigationTitle(video.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(MediaTheme.canvas)
    }

    private var previewSection: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: 12))
            } else if currentURL != nil {
                RoundedRectangle(cornerRadius: 12)
                    .fill(MediaTheme.card)
                    .frame(height: 220)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(MediaTheme.card)
                    .frame(height: 220)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("This clip is no longer on the device")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        // Built here rather than inside the body: creating the player while the
        // screen is drawing would change state mid-update, which SwiftUI treats
        // as undefined behavior.
        .task { rebuildPlayer() }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    /// Builds the player once per clip, so screen updates never restart
    /// playback or leak players.
    private func rebuildPlayer() {
        guard let url = currentURL else {
            player?.pause()
            player = nil
            return
        }
        if let existing = player,
           let asset = existing.currentItem?.asset as? AVURLAsset,
           asset.url == url {
            return
        }
        player?.pause()
        player = AVPlayer(url: url)
    }

    /// Which camera this belongs to, why, and the one tap that changes it.
    private var subjectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Camera")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: subject.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(subject == .person ? MediaTheme.frontTint : MediaTheme.backTint)
                        .frame(width: 32, height: 32)
                        .background(
                            (subject == .person ? MediaTheme.frontTint : MediaTheme.backTint).opacity(0.16),
                            in: .rect(cornerRadius: 8)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(subject.label) · \(subject.cameraLabel) camera")
                            .font(.subheadline.weight(.semibold))
                        if let reason = video.subjectReason {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)
                }

                if let error = video.preparationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        prepare(as: subject)
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(MediaTheme.well, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(videoLibrary.isImporting)
                }

                Button {
                    prepare(as: subject.opposite)
                } label: {
                    Label(
                        "This is a \(subject.opposite.label.lowercased()) — prepare for \(subject.opposite.cameraLabel.lowercased()) camera",
                        systemImage: "arrow.left.arrow.right"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MediaTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(MediaTheme.accent.opacity(0.12), in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(videoLibrary.isImporting)
            }
            .padding(14)
            .background(MediaTheme.card)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(MediaTheme.stroke, lineWidth: 1)
            )
        }
    }

    private func prepare(as subject: MediaSubject) {
        Task {
            await videoLibrary.prepare(video, as: subject, profile: profileManager.activeProfile)
            dismiss()
        }
    }

    private var specSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                detailRow("Original", "\(video.originalWidth)×\(video.originalHeight)")
                Divider().padding(.leading, 16)
                detailRow("Duration", formatDuration(video.originalDuration))

                if let spec = video.preparedSpec {
                    Divider().padding(.leading, 16)
                    detailRow("Prepared", spec)
                }

                Divider().padding(.leading, 16)
                detailRow("Imported", video.importedAt.formatted(date: .abbreviated, time: .shortened))
                Divider().padding(.leading, 16)
                detailRow("Size", formatFileSize(video.fileSizeBytes))
            }
            .background(MediaTheme.card)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(MediaTheme.stroke, lineWidth: 1)
            )
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var useButton: some View {
        let isReady = video.isReady
        let tint = facing == .front ? MediaTheme.frontTint : MediaTheme.backTint
        let slotLabel = facing == .front ? "Front" : "Back"

        return VStack(spacing: 10) {
            Button {
                if onSelectSequence != nil {
                    onSelectSequence?(video, facing, .one)
                    dismiss()
                } else if let url = videoLibrary.preparedVideoURL(for: video) {
                    onUse?(video, url)
                    dismiss()
                }
            } label: {
                Label("Use as \(slotLabel) 1", systemImage: "play.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isReady ? MediaTheme.accent : MediaTheme.well, in: .rect(cornerRadius: 14))
                    .foregroundStyle(isReady ? .white : Color.secondary)
            }
            .disabled(!isReady)

            if onSelectSequence != nil {
                Button {
                    onSelectSequence?(video, facing, .two)
                    dismiss()
                } label: {
                    Text("Use as \(slotLabel) 2")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            isReady && (isSlotOneFilled?(facing) ?? true) ? tint.opacity(0.18) : MediaTheme.well,
                            in: .rect(cornerRadius: 12)
                        )
                        .foregroundStyle(isReady && (isSlotOneFilled?(facing) ?? true) ? tint : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!isReady || !(isSlotOneFilled?(facing) ?? true))

                if !(isSlotOneFilled?(facing) ?? true) {
                    Text("Media 2 unlocks once Media 1 is set for that camera.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
