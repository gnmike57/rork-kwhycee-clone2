import Foundation
import AVFoundation
import UIKit

/// Live state of the one import that can be running at a time.
///
/// Held by the service rather than the screen, so switching tabs — or leaving
/// the app briefly — does not lose the run or its progress.
nonisolated struct ImportJob: Sendable {
    var videoID: UUID
    var name: String
    var stage: String
    var progress: Double
    var etaSeconds: Double?
    var canCancel: Bool

    var etaText: String? {
        guard let etaSeconds, etaSeconds.isFinite, etaSeconds > 1 else { return nil }
        let total = Int(etaSeconds.rounded())
        if total < 60 { return "about \(max(total, 1))s left" }
        let minutes = total / 60
        let seconds = total % 60
        return seconds == 0 ? "about \(minutes)m left" : "about \(minutes)m \(seconds)s left"
    }
}

@Observable
@MainActor
final class VideoLibraryService {
    var videos: [SavedVideo] = []

    /// Message from the most recent failed import, surfaced to the user.
    var lastImportError: String?

    /// Non-nil while an import or a re-prepare is running.
    var activeJob: ImportJob?

    private let metadataKey = "video_library_v1"
    private let libraryDirName = "VideoLibrary"

    private let converter = MediaConverterService()
    private let classifier = MediaSubjectClassifier()

    private var runningTask: Task<SavedVideo?, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    var libraryDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(libraryDirName)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    var isImporting: Bool { activeJob != nil }

    init() {
        loadMetadata()
        repairInterruptedImports()
        removeOrphanedFiles()
    }

    // MARK: - File resolution

    func fileURL(for fileName: String) -> URL {
        libraryDirectory.appendingPathComponent(fileName)
    }

    private func existingURL(_ fileName: String?) -> URL? {
        guard let fileName else { return nil }
        let url = fileURL(for: fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func frontVideoURL(for video: SavedVideo) -> URL? {
        existingURL(video.frontCameraFileName)
    }

    func backVideoURL(for video: SavedVideo) -> URL? {
        existingURL(video.backCameraFileName)
    }

    /// The prepared version, whichever camera it belongs to.
    func preparedVideoURL(for video: SavedVideo) -> URL? {
        existingURL(video.preparedFileName)
    }

    func originalVideoURL(for video: SavedVideo) -> URL? {
        existingURL(video.originalFileName)
    }

    func thumbnailURL(for video: SavedVideo) -> URL? {
        existingURL(video.thumbnailFileName)
    }

    // MARK: - Import

    /// Brings a clip in and prepares it for the one camera it belongs to.
    ///
    /// The record is written before encoding starts, so an interrupted run
    /// leaves something the app can find and repair instead of an orphan file.
    @discardableResult
    func importVideo(sourceURL: URL, name: String, profile: DeviceProfile?) async -> SavedVideo? {
        guard runningTask == nil else {
            lastImportError = "Another clip is still being prepared."
            return nil
        }

        let task = Task { @MainActor [weak self] () -> SavedVideo? in
            guard let self else { return nil }
            return await self.runImport(sourceURL: sourceURL, name: name, profile: profile)
        }
        runningTask = task
        beginBackgroundAssertion()

        let result = await task.value

        runningTask = nil
        endBackgroundAssertion()
        activeJob = nil
        return result
    }

    /// Stops the running import and clears anything it half-wrote.
    func cancelImport() {
        runningTask?.cancel()
    }

    /// Re-runs preparation for a clip that failed or was interrupted, without
    /// making the user pick the file again. Also used by the subject override.
    @discardableResult
    func prepare(_ video: SavedVideo, as subject: MediaSubject? = nil, profile: DeviceProfile?) async -> SavedVideo? {
        guard runningTask == nil else {
            lastImportError = "Another clip is still being prepared."
            return nil
        }
        guard let originalURL = originalVideoURL(for: video) else {
            lastImportError = "The original clip is no longer on this device."
            return nil
        }

        let task = Task { @MainActor [weak self] () -> SavedVideo? in
            guard let self else { return nil }
            let decision = MediaSubjectDecision(
                subject: subject ?? video.subject ?? .person,
                reason: subject != nil ? "Set by you." : (video.subjectReason ?? "Chosen on import.")
            )
            return await self.runPreparation(
                videoID: video.id,
                name: video.name,
                sourceURL: originalURL,
                decision: decision,
                profile: profile,
                baseProgress: 0,
                progressSpan: 1
            )
        }
        runningTask = task
        beginBackgroundAssertion()

        let result = await task.value

        runningTask = nil
        endBackgroundAssertion()
        activeJob = nil
        return result
    }

    // MARK: - Import stages

    private func runImport(sourceURL: URL, name: String, profile: DeviceProfile?) async -> SavedVideo? {
        lastImportError = nil

        let videoID = UUID()
        let originalExt = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let originalFileName = "\(videoID.uuidString)_original.\(originalExt)"
        let originalDest = fileURL(for: originalFileName)

        activeJob = ImportJob(
            videoID: videoID,
            name: name,
            stage: "Checking the clip…",
            progress: 0.01,
            etaSeconds: nil,
            canCancel: true
        )

        // Move rather than copy: the picker already wrote a private temp copy,
        // so copying again doubles the write for no benefit.
        do {
            if FileManager.default.fileExists(atPath: originalDest.path) {
                try FileManager.default.removeItem(at: originalDest)
            }
            try FileManager.default.moveItem(at: sourceURL, to: originalDest)
        } catch {
            do {
                try FileManager.default.copyItem(at: sourceURL, to: originalDest)
            } catch {
                lastImportError = "That clip could not be added to your library."
                return nil
            }
        }

        if Task.isCancelled {
            try? FileManager.default.removeItem(at: originalDest)
            lastImportError = "Import cancelled."
            return nil
        }

        let asset = AVURLAsset(url: originalDest, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        var origWidth = 0
        var origHeight = 0

        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            let size = (try? await track.load(.naturalSize)) ?? .zero
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            let rotated = CGRect(origin: .zero, size: size).applying(transform)
            origWidth = Int(abs(rotated.width))
            origHeight = Int(abs(rotated.height))
        }

        guard duration.isFinite, duration > 0, origWidth > 0 else {
            try? FileManager.default.removeItem(at: originalDest)
            lastImportError = TranscodeError.unreadableSource.localizedDescription
            return nil
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: originalDest.path)[.size] as? Int64) ?? 0

        activeJob?.stage = "Making a thumbnail…"
        activeJob?.progress = 0.04

        var thumbnailFileName: String?
        if let thumbnail = await generateThumbnail(from: originalDest),
           let data = thumbnail.jpegData(compressionQuality: 0.7) {
            let thumbName = "\(videoID.uuidString)_thumb.jpg"
            try? data.write(to: fileURL(for: thumbName))
            thumbnailFileName = thumbName
        }

        if Task.isCancelled {
            cleanUpFiles(originalFileName, thumbnailFileName)
            lastImportError = "Import cancelled."
            return nil
        }

        // Which camera does this belong to? A face means front, anything else
        // means back. That is the whole rule.
        activeJob?.stage = "Working out which camera this is for…"
        activeJob?.progress = 0.08

        let decision = await classifier.classify(url: originalDest)

        if Task.isCancelled {
            cleanUpFiles(originalFileName, thumbnailFileName)
            lastImportError = "Import cancelled."
            return nil
        }

        let savedVideo = SavedVideo(
            id: videoID,
            name: name,
            originalFileName: originalFileName,
            originalWidth: origWidth,
            originalHeight: origHeight,
            originalDuration: duration,
            thumbnailFileName: thumbnailFileName,
            fileSizeBytes: fileSize,
            subject: decision.subject,
            subjectReason: decision.reason,
            isPreparing: profile != nil
        )

        // Written before encoding so an interrupted run is discoverable.
        videos.insert(savedVideo, at: 0)
        saveMetadata()

        guard profile != nil else {
            activeJob = nil
            return savedVideo
        }

        let prepared = await runPreparation(
            videoID: videoID,
            name: name,
            sourceURL: originalDest,
            decision: decision,
            profile: profile,
            baseProgress: 0.12,
            progressSpan: 0.88
        )

        // The record is kept either way: a clip whose encode failed still has
        // its original, so it can be prepared again without re-picking it.
        return prepared ?? videos.first { $0.id == videoID } ?? savedVideo
    }

    /// Encodes, verifies and records one camera's version of a clip.
    private func runPreparation(
        videoID: UUID,
        name: String,
        sourceURL: URL,
        decision: MediaSubjectDecision,
        profile: DeviceProfile?,
        baseProgress: Double,
        progressSpan: Double
    ) async -> SavedVideo? {
        guard let profile else { return videos.first { $0.id == videoID } }

        let subject = decision.subject
        let camera: CameraDeviceSpec? = subject == .person
            ? (profile.frontCamera ?? profile.backCamera)
            : (profile.backCamera ?? profile.frontCamera)

        guard let camera else {
            updateRecord(videoID) { record in
                record.isPreparing = false
                record.preparationError = "This device profile has no camera to match."
            }
            lastImportError = "This device profile has no camera to match."
            return videos.first { $0.id == videoID }
        }

        let spec = profile.conversionSpec(for: camera)
        let specLabel = "\(spec.targetWidth)×\(spec.targetHeight)@\(spec.targetFrameRate)fps"
        let suffix = subject == .person ? "front" : "back"
        let outputFileName = "\(videoID.uuidString)_\(suffix).mov"
        let outputURL = fileURL(for: outputFileName)

        // Anything already prepared for this clip is superseded by this run,
        // so it is removed on success rather than lingering until next launch.
        let existing = videos.first { $0.id == videoID }
        let supersededFiles = [existing?.frontCameraFileName, existing?.backCameraFileName]
            .compactMap { $0 }
            .filter { $0 != outputFileName }

        updateRecord(videoID) { record in
            record.subject = subject
            record.subjectReason = decision.reason
            record.isPreparing = true
            record.preparationError = nil
        }

        if activeJob == nil {
            activeJob = ImportJob(
                videoID: videoID,
                name: name,
                stage: "Preparing…",
                progress: baseProgress,
                etaSeconds: nil,
                canCancel: true
            )
        }
        activeJob?.stage = "Encoding for the \(subject.cameraLabel.lowercased()) camera · \(specLabel)"
        activeJob?.progress = baseProgress

        // Encoding owns most of the bar; verifying and saving share the tail.
        let encodeSpan = progressSpan * 0.85
        let startedAt = Date()

        let onProgress: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor [weak self] in
                guard let self, var job = self.activeJob, job.videoID == videoID else { return }
                let overall = baseProgress + fraction * encodeSpan
                guard overall > job.progress else { return }
                job.progress = min(overall, baseProgress + encodeSpan)
                let elapsed = Date().timeIntervalSince(startedAt)
                if fraction > 0.03, elapsed > 1 {
                    job.etaSeconds = elapsed / fraction - elapsed
                }
                job.stage = "Encoding for the \(subject.cameraLabel.lowercased()) camera · \(Int(fraction * 100))%"
                self.activeJob = job
            }
        }

        var lastError: TranscodeError?

        for strategy in [TranscodeStrategy.fast, .compatibility] {
            if Task.isCancelled { break }
            if strategy == .compatibility {
                guard let lastError, lastError.deservesRetry else { break }
                activeJob?.stage = "Retrying on the compatibility encoder…"
                activeJob?.etaSeconds = nil
            }

            do {
                _ = try await converter.transcode(
                    source: sourceURL,
                    spec: spec,
                    outputURL: outputURL,
                    strategy: strategy,
                    onProgress: onProgress
                )

                activeJob?.stage = "Checking the result…"
                activeJob?.etaSeconds = nil
                activeJob?.progress = baseProgress + encodeSpan

                let expected = videos.first { $0.id == videoID }?.originalDuration ?? 0
                try await converter.verify(url: outputURL, spec: spec, expectedSeconds: expected)

                activeJob?.stage = "Saving…"
                activeJob?.progress = baseProgress + progressSpan * 0.97

                updateRecord(videoID) { record in
                    switch subject {
                    case .person:
                        record.frontCameraFileName = outputFileName
                        record.frontSpec = specLabel
                        // A clip belongs to one camera; clear any stale pairing.
                        record.backCameraFileName = nil
                        record.backSpec = nil
                    case .document:
                        record.backCameraFileName = outputFileName
                        record.backSpec = specLabel
                        record.frontCameraFileName = nil
                        record.frontSpec = nil
                    }
                    record.isPreparing = false
                    record.preparationError = nil
                }

                cleanUpFiles(supersededFiles)

                activeJob?.progress = baseProgress + progressSpan
                activeJob?.stage = "Ready"
                lastImportError = nil
                return videos.first { $0.id == videoID }
            } catch {
                let transcodeError = (error as? TranscodeError) ?? .writeFailed(error.localizedDescription)
                lastError = transcodeError
                try? FileManager.default.removeItem(at: outputURL)
                if transcodeError == .cancelled || Task.isCancelled { break }
            }
        }

        let message = Task.isCancelled
            ? TranscodeError.cancelled.localizedDescription
            : (lastError?.localizedDescription ?? "That clip could not be prepared.")

        // The original stays put, so the clip can be prepared again later
        // without re-picking it.
        updateRecord(videoID) { record in
            record.isPreparing = false
            record.preparationError = message
        }
        lastImportError = message
        return videos.first { $0.id == videoID }
    }

    // MARK: - Editing

    func deleteVideo(_ video: SavedVideo) {
        if activeJob?.videoID == video.id { cancelImport() }
        cleanUpFiles(
            video.originalFileName,
            video.frontCameraFileName,
            video.backCameraFileName,
            video.thumbnailFileName
        )
        videos.removeAll { $0.id == video.id }
        saveMetadata()
    }

    func renameVideo(_ video: SavedVideo, to newName: String) {
        updateRecord(video.id) { $0.name = newName }
    }

    private func updateRecord(_ id: UUID, _ mutate: (inout SavedVideo) -> Void) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        mutate(&videos[index])
        saveMetadata()
    }

    // MARK: - Housekeeping

    /// A record still marked as preparing was cut short by a crash, a force
    /// quit, or the system reclaiming the app. Its half-written output is
    /// dropped and the clip is flagged so it can be prepared again.
    private func repairInterruptedImports() {
        var changed = false
        for index in videos.indices where videos[index].isPreparingNow {
            let record = videos[index]
            cleanUpFiles(record.frontCameraFileName, record.backCameraFileName)
            videos[index].frontCameraFileName = nil
            videos[index].frontSpec = nil
            videos[index].backCameraFileName = nil
            videos[index].backSpec = nil
            videos[index].isPreparing = false
            videos[index].preparationError = "Preparing was interrupted. Tap to try again."
            changed = true
        }
        if changed { saveMetadata() }
    }

    /// Deletes files in the library folder that no record points at, which is
    /// what an interrupted import leaves behind.
    private func removeOrphanedFiles() {
        let referenced = Set(videos.flatMap { record in
            [
                record.originalFileName,
                record.frontCameraFileName,
                record.backCameraFileName,
                record.thumbnailFileName
            ].compactMap { $0 }
        })

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: libraryDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in contents where !referenced.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func cleanUpFiles(_ names: String?...) {
        cleanUpFiles(names.compactMap { $0 })
    }

    private func cleanUpFiles(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: fileURL(for: name))
        }
    }

    // MARK: - Background tolerance

    /// Asks the system to keep the app running briefly after it is backgrounded
    /// so an import in flight is not chopped in half at the worst moment.
    private func beginBackgroundAssertion() {
        endBackgroundAssertion()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MediaImport") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.runningTask?.cancel()
                self.endBackgroundAssertion()
            }
        }
    }

    private func endBackgroundAssertion() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - Thumbnails & persistence

    private func generateThumbnail(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else { return nil }
        return UIImage(cgImage: result.image)
    }

    private func loadMetadata() {
        guard let data = UserDefaults.standard.data(forKey: metadataKey),
              let decoded = try? JSONDecoder().decode([SavedVideo].self, from: data) else { return }
        videos = decoded
    }

    private func saveMetadata() {
        guard let data = try? JSONEncoder().encode(videos) else { return }
        UserDefaults.standard.set(data, forKey: metadataKey)
    }
}
