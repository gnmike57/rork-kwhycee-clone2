import Foundation

nonisolated struct SavedVideo: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var name: String
    var originalFileName: String
    var importedAt: Date
    var frontCameraFileName: String?
    var backCameraFileName: String?
    var originalWidth: Int
    var originalHeight: Int
    var originalDuration: Double
    var frontSpec: String?
    var backSpec: String?
    var thumbnailFileName: String?
    var fileSizeBytes: Int64

    /// Which camera this clip stands in for. A clip is only ever needed by one
    /// of them: a person is a front-camera capture, a document a back-camera
    /// one. `nil` on records saved before this existed, so their stored
    /// behaviour is unchanged.
    var subject: MediaSubject?

    /// Plain-language reason the subject was chosen, shown next to the clip.
    var subjectReason: String?

    /// Why the last preparation attempt failed, if it did.
    var preparationError: String?

    /// Set while a preparation is in flight. A record still carrying this on
    /// launch was interrupted, and is repaired rather than trusted.
    var isPreparing: Bool?

    init(
        id: UUID = UUID(),
        name: String,
        originalFileName: String,
        importedAt: Date = Date(),
        frontCameraFileName: String? = nil,
        backCameraFileName: String? = nil,
        originalWidth: Int = 0,
        originalHeight: Int = 0,
        originalDuration: Double = 0,
        frontSpec: String? = nil,
        backSpec: String? = nil,
        thumbnailFileName: String? = nil,
        fileSizeBytes: Int64 = 0,
        subject: MediaSubject? = nil,
        subjectReason: String? = nil,
        preparationError: String? = nil,
        isPreparing: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.originalFileName = originalFileName
        self.importedAt = importedAt
        self.frontCameraFileName = frontCameraFileName
        self.backCameraFileName = backCameraFileName
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.originalDuration = originalDuration
        self.frontSpec = frontSpec
        self.backSpec = backSpec
        self.thumbnailFileName = thumbnailFileName
        self.fileSizeBytes = fileSizeBytes
        self.subject = subject
        self.subjectReason = subjectReason
        self.preparationError = preparationError
        self.isPreparing = isPreparing
    }

    /// The prepared version's file name, whichever camera it was made for.
    var preparedFileName: String? {
        switch subject {
        case .person: return frontCameraFileName
        case .document: return backCameraFileName
        case nil: return backCameraFileName ?? frontCameraFileName
        }
    }

    var preparedSpec: String? {
        switch subject {
        case .person: return frontSpec
        case .document: return backSpec
        case nil: return backSpec ?? frontSpec
        }
    }

    var isPreparingNow: Bool { isPreparing ?? false }

    var isReady: Bool { preparedFileName != nil && !isPreparingNow }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated static func == (lhs: SavedVideo, rhs: SavedVideo) -> Bool {
        lhs.id == rhs.id
    }
}
