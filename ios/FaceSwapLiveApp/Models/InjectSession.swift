import Foundation

/// One line in the sequence recap. Honest asked-vs-sent only.
nonisolated struct RecapEvent: Identifiable, Sendable, Equatable {
    var id: UUID
    var time: Date
    var kind: MediaRequestKind
    var host: String
    var askedFacing: String
    var sentFacing: String
    var askedSize: String
    var sentSize: String
    var askedFrameRate: String
    var sentFrameRate: String
    var wantsAudio: Bool
    var cropPercent: Int?
    var note: String

    init(
        id: UUID = UUID(),
        time: Date = Date(),
        kind: MediaRequestKind,
        host: String,
        askedFacing: String,
        sentFacing: String,
        askedSize: String,
        sentSize: String,
        askedFrameRate: String,
        sentFrameRate: String,
        wantsAudio: Bool,
        cropPercent: Int?,
        note: String
    ) {
        self.id = id
        self.time = time
        self.kind = kind
        self.host = host
        self.askedFacing = askedFacing
        self.sentFacing = sentFacing
        self.askedSize = askedSize
        self.sentSize = sentSize
        self.askedFrameRate = askedFrameRate
        self.sentFrameRate = sentFrameRate
        self.wantsAudio = wantsAudio
        self.cropPercent = cropPercent
        self.note = note
    }
}

/// Snapshot shown after injection turns off.
nonisolated struct SequenceRecap: Sendable, Equatable, Identifiable {
    var id: UUID
    var host: String
    var startedAt: Date
    var endedAt: Date
    var events: [RecapEvent]
    var heldFeedAfterSeconds: Double?
    var endedBecause: String

    init(
        id: UUID = UUID(),
        host: String,
        startedAt: Date,
        endedAt: Date,
        events: [RecapEvent],
        heldFeedAfterSeconds: Double?,
        endedBecause: String
    ) {
        self.id = id
        self.host = host
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.events = events
        self.heldFeedAfterSeconds = heldFeedAfterSeconds
        self.endedBecause = endedBecause
    }
}

/// What the page is told about the live feed — HUD source of truth.
nonisolated struct ObservedFeedSnapshot: Sendable, Equatable {
    var width: Int
    var height: Int
    var frameRate: Int
    var format: String
    var cameraLabel: String
    var facing: String
    var isActive: Bool
    var pageHoldsFeed: Bool
}

/// In-progress pass on this page visit.
struct InjectSessionState: Equatable {
    var host: String = ""
    var startedAt: Date?
    var usedFront: Bool = false
    var usedBack: Bool = false
    var servedFront: Set<Int> = []
    var servedBack: Set<Int> = []
    var events: [RecapEvent] = []
    var lastActiveAt: Date?
    var lastInactiveAt: Date?
    var recapShown: Bool = false

    var hasStarted: Bool { startedAt != nil }

    mutating func reset() {
        self = InjectSessionState()
    }
}
