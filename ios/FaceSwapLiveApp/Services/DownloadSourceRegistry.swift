import Foundation

/// Maps a `WKDownload` object identity to the URL it came from.
///
/// `WKDownloadDelegate` is main-actor bound, so the download is registered and
/// looked up on the main actor by construction — no lock is needed.
final class DownloadSourceRegistry {
    private var sources: [ObjectIdentifier: URL] = [:]

    func setSource(_ id: ObjectIdentifier, url: URL?) {
        sources[id] = url
    }

    func source(_ id: ObjectIdentifier) -> URL? {
        sources[id]
    }
}
