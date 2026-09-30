import Foundation

/// How the pill button, the status capsule and the tucked tab should read and
/// colour the tracking state right now.
nonisolated enum FaceTrackingMood: Sendable, Equatable {
    case off
    case waiting
    case searching
    case live
    case lost
    case error

    /// Short wording for VoiceOver on the pill button.
    var spoken: String {
        switch self {
        case .off: "off"
        case .waiting: "waiting"
        case .searching: "searching"
        case .live: "live"
        case .lost: "link lost"
        case .error: "unavailable"
        }
    }
}

/// The status capsule's line, derived from plain values so the wording can be
/// checked for every state without running the tracker.
nonisolated enum FaceTrackingCapsule {
    static func mood(state: FaceTrackingState) -> FaceTrackingMood {
        switch state {
        case .off: .off
        case .standby: .waiting
        case .starting, .searching, .listening: .searching
        case .live, .receiving: .live
        case .lost: .lost
        case .unavailable: .error
        }
    }

    /// nil means the capsule stays hidden.
    static func line(
        state: FaceTrackingState,
        rate: Int,
        address: String?,
        port: UInt16,
        senderName: String?,
        isExpressionOnly: Bool,
        hasSeenFace: Bool
    ) -> String? {
        switch state {
        case .off:
            return nil
        case .standby:
            return "Waiting for a still on the feed"
        case .starting, .searching:
            return "Looking for your face…"
        case .live:
            return "Tracking live · \(rate)/s"
        case .lost:
            return "Link lost — idling"
        case .listening:
            if let address { return "Listening on \(address) : \(port)" }
            return "Listening on :\(port)"
        case .receiving:
            if isExpressionOnly {
                if let senderName { return "Receiving from \(senderName) · expression only" }
                return "Receiving · expression only"
            }
            if !hasSeenFace { return "Receiving · no face" }
            if let senderName { return "Receiving from \(senderName)" }
            return "Receiving"
        case .unavailable(let problem):
            switch problem {
            case .cameraDenied: return "Camera access denied"
            case .notSupported: return "Face tracking isn't supported here"
            case .portInUse(let port): return "Port \(port) is already in use"
            case .failed: return "Tracking failed"
            }
        }
    }
}
