import Foundation

/// One entry in the browser's download history.
///
/// Persisted as-is to metadata storage, so every field must survive a JSON
/// round trip. Files live in the Downloads directory; this struct is the
/// record that lets the list and toast talk about them.
nonisolated struct DownloadItem: Identifiable, Codable, Sendable, Hashable {
    nonisolated enum State: String, Codable, Sendable {
        case downloading
        case completed
        case failed
    }

    let id: UUID
    var fileName: String
    var sourceURL: String
    var state: State
    /// 0...1 when the total size is known, 0 when it is not.
    var progress: Double
    var totalBytes: Int64?
    var receivedBytes: Int64?
    var startedAt: Date
    var finishedAt: Date?
    var errorText: String?

    var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    var symbolName: String {
        switch fileExtension {
        case "pdf": "doc.richtext.fill"
        case "zip", "rar", "7z", "tar", "gz": "doc.zipper"
        case "png", "jpg", "jpeg", "gif", "webp", "heic": "photo.fill"
        case "mp4", "mov", "webm", "m4v", "avi": "video.fill"
        case "mp3", "wav", "m4a", "aac", "ogg": "music.note"
        case "doc", "docx", "txt", "rtf", "md": "doc.text.fill"
        case "xls", "xlsx", "csv", "numbers": "tablecells.fill"
        case "ppt", "pptx", "key": "rectangle.on.rectangle.fill"
        default: "doc.fill"
        }
    }
}
