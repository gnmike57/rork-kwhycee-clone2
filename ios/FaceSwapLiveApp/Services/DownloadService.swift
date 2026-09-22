import Foundation
import WebKit

/// Runs and records browser downloads, saving files to the app's Downloads
/// directory.
///
/// The directory is exposed to the Files app through the file-sharing Info
/// keys, so everything downloaded here is also browsable at
/// On My iPhone → Kwhycee → Downloads.
@Observable
@MainActor
final class DownloadService {
    private(set) var downloads: [DownloadItem] = []

    /// The download the toast is currently talking about, if any.
    var activeToastID: UUID?

    private let metadataKey = "browser_downloads_v1"
    private let directoryName = "Downloads"

    private var activeDownloadByID: [UUID: WKDownload] = [:]
    private var idByDownload: [ObjectIdentifier: UUID] = [:]
    private var progressObservers: [UUID: NSKeyValueObservation] = [:]
    private var toastDismissTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    init() {
        loadMetadata()
        pruneMissingFiles()
    }

    // MARK: - Storage

    var downloadsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(directoryName)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func fileURL(for fileName: String) -> URL {
        downloadsDirectory.appendingPathComponent(fileName)
    }

    var hasActiveDownload: Bool {
        downloads.contains { $0.state == .downloading }
    }

    var activeToastItem: DownloadItem? {
        guard let activeToastID else { return nil }
        return item(id: activeToastID)
    }

    func item(id: UUID) -> DownloadItem? {
        downloads.first { $0.id == id }
    }

    // MARK: - WKDownload flow

    /// Chooses the on-disk destination for a new download and starts tracking
    /// it. Called from `download(_:decideDestinationUsing:completionHandler:)`.
    @discardableResult
    func makeDestination(
        download: WKDownload,
        response: URLResponse,
        suggestedFilename: String,
        sourceURL: URL?
    ) -> URL {
        let fileName = uniqueFileName(for: suggestedFilename)
        let item = DownloadItem(
            id: UUID(),
            fileName: fileName,
            sourceURL: sourceURL?.absoluteString ?? response.url?.absoluteString ?? "",
            state: .downloading,
            progress: 0,
            totalBytes: response.expectedContentLength > 0 ? response.expectedContentLength : nil,
            receivedBytes: 0,
            startedAt: Date(),
            finishedAt: nil,
            errorText: nil
        )
        downloads.insert(item, at: 0)
        activeDownloadByID[item.id] = download
        idByDownload[ObjectIdentifier(download)] = item.id
        startObservingProgress(item.id, download: download)
        persist()
        showToast(for: item.id)
        return fileURL(for: fileName)
    }

    func handleFinish(_ download: WKDownload) {
        guard let id = idByDownload.removeValue(forKey: ObjectIdentifier(download)) else { return }
        activeDownloadByID.removeValue(forKey: id)
        progressObservers.removeValue(forKey: id)?.invalidate()

        guard var item = item(id: id) else { return }
        let url = fileURL(for: item.fileName)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value

        item.state = .completed
        item.progress = 1
        item.receivedBytes = fileSize
        item.totalBytes = item.totalBytes ?? fileSize
        item.finishedAt = Date()
        replace(item)
        persist()
        scheduleToastDismissal()
    }

    func handleFailure(_ download: WKDownload, error: Error, resumeData: Data?) {
        guard let id = idByDownload.removeValue(forKey: ObjectIdentifier(download)) else { return }
        activeDownloadByID.removeValue(forKey: id)
        progressObservers.removeValue(forKey: id)?.invalidate()

        guard var item = item(id: id) else { return }
        // A failed download never leaves a half-written file behind.
        try? FileManager.default.removeItem(at: fileURL(for: item.fileName))
        item.state = .failed
        item.errorText = error.localizedDescription
        item.finishedAt = Date()
        replace(item)
        persist()
        scheduleToastDismissal()
    }

    private func startObservingProgress(_ itemID: UUID, download: WKDownload) {
        progressObservers[itemID] = download.progress.observe(
            \.fractionCompleted,
            options: [.initial]
        ) { [weak self] progress, _ in
            let completed = progress.completedUnitCount
            let total = progress.totalUnitCount
            Task { @MainActor [weak self] in
                self?.updateProgress(itemID: itemID, completed: completed, total: total)
            }
        }
    }

    private func updateProgress(itemID: UUID, completed: Int64, total: Int64) {
        guard var item = item(id: itemID), item.state == .downloading else { return }
        if total > 0 {
            let fraction = min(max(Double(completed) / Double(total), 0), 1)
            guard abs(fraction - item.progress) >= 0.005 || fraction == 1 else { return }
            item.progress = fraction
            item.totalBytes = total
            item.receivedBytes = completed
        } else {
            // Total unknown: keep the bar indeterminate but still track bytes.
            item.progress = 0
            item.totalBytes = nil
            item.receivedBytes = completed
        }
        replace(item)
    }

    // MARK: - User actions

    func cancel(itemID: UUID) {
        guard let item = item(id: itemID) else { return }
        let download = activeDownloadByID.removeValue(forKey: itemID)
        progressObservers.removeValue(forKey: itemID)?.invalidate()
        if let key = idByDownload.first(where: { $0.value == itemID })?.key {
            idByDownload.removeValue(forKey: key)
        }

        let fileName = item.fileName
        if let download {
            download.cancel { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removePartialFile(fileName: fileName)
                }
            }
        } else {
            removePartialFile(fileName: fileName)
        }

        if activeToastID == itemID {
            dismissToast()
        }
        downloads.removeAll { $0.id == itemID }
        persist()
    }

    func delete(itemID: UUID) {
        guard let item = item(id: itemID) else { return }
        if item.state == .downloading {
            cancel(itemID: itemID)
            return
        }
        try? FileManager.default.removeItem(at: fileURL(for: item.fileName))
        if activeToastID == itemID {
            dismissToast()
        }
        downloads.removeAll { $0.id == itemID }
        persist()
    }

    /// Failed downloads are retried from their original URL with a plain
    /// URLSession fetch into the same file name.
    func retry(itemID: UUID) {
        guard var item = item(id: itemID), item.state == .failed else { return }
        guard let source = URL(string: item.sourceURL) else {
            item.errorText = "The original link is no longer valid."
            replace(item)
            persist()
            return
        }

        item.state = .downloading
        item.progress = 0
        item.receivedBytes = 0
        item.errorText = nil
        item.finishedAt = nil
        replace(item)
        showToast(for: itemID)

        let fileName = item.fileName
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            do {
                let (tempURL, response) = try await URLSession.shared.download(from: source)
                guard let self, !Task.isCancelled else { return }
                let destination = self.fileURL(for: fileName)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: tempURL, to: destination)
                self.completeRetry(itemID: itemID, destination: destination, response: response)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.failRetry(itemID: itemID, error: error)
            }
        }
    }

    private func completeRetry(itemID: UUID, destination: URL, response: URLResponse) {
        guard var item = item(id: itemID) else { return }
        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value
        item.state = .completed
        item.progress = 1
        item.receivedBytes = fileSize
        item.totalBytes = fileSize
        item.finishedAt = Date()
        replace(item)
        persist()
        scheduleToastDismissal()
        _ = response
    }

    private func failRetry(itemID: UUID, error: Error) {
        guard var item = item(id: itemID) else { return }
        try? FileManager.default.removeItem(at: fileURL(for: item.fileName))
        item.state = .failed
        item.errorText = error.localizedDescription
        item.finishedAt = Date()
        replace(item)
        persist()
        scheduleToastDismissal()
    }

    func dismissToast() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        activeToastID = nil
    }

    // MARK: - Helpers

    private func replace(_ item: DownloadItem) {
        guard let index = downloads.firstIndex(where: { $0.id == item.id }) else { return }
        downloads[index] = item
    }

    private func removePartialFile(fileName: String) {
        try? FileManager.default.removeItem(at: fileURL(for: fileName))
    }

    private func uniqueFileName(for suggestedName: String) -> String {
        var raw = (suggestedName as NSString).lastPathComponent
        raw = raw.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        if raw.isEmpty || raw == "." { raw = "Download" }

        let ext = (raw as NSString).pathExtension
        let stem = (raw as NSString).deletingPathExtension.isEmpty ? "Download" : (raw as NSString).deletingPathExtension
        var candidate = ext.isEmpty ? stem : "\(stem).\(ext)"
        var counter = 2
        while FileManager.default.fileExists(atPath: fileURL(for: candidate).path) {
            candidate = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    private func showToast(for id: UUID) {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        activeToastID = id
    }

    private func scheduleToastDismissal() {
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.activeToastID = nil
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(downloads) else { return }
        UserDefaults.standard.set(data, forKey: metadataKey)
    }

    private func loadMetadata() {
        guard let data = UserDefaults.standard.data(forKey: metadataKey),
              let items = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return }
        downloads = items.sorted { $0.startedAt > $1.startedAt }
    }

    /// Completed entries whose file disappeared (manual deletion in Files,
    /// a reinstall restoring metadata) are removed rather than shown dead.
    private func pruneMissingFiles() {
        let before = downloads.count
        downloads.removeAll { item in
            guard item.state == .completed else { return false }
            return !FileManager.default.fileExists(atPath: fileURL(for: item.fileName).path)
        }
        if downloads.count != before {
            persist()
        }
    }
}
