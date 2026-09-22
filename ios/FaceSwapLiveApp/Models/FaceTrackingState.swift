import Foundation

/// Where face tracking stands right now. Drives the capsule wording, the pill
/// button's colour and the haptic ticks.
nonisolated enum FaceTrackingState: Sendable, Equatable {
    /// The user has tracking switched off.
    case off

    /// Switched on, but nothing to animate: no still on an active feed, the
    /// Preview tab is up, or the app is in the background.
    case standby

    /// The source is spinning up.
    case starting

    /// This iPhone's camera is running but no face has been found.
    case searching

    /// Poses are arriving from this iPhone's camera.
    case live

    /// A face or a link was there and has gone quiet; the still is idling.
    case lost

    /// Waiting for the first Live Link Face packet.
    case listening

    /// Live Link Face packets are arriving from the second iPhone.
    case receiving

    /// Tracking cannot run until something outside the app changes.
    case unavailable(Problem)

    nonisolated enum Problem: Sendable, Equatable {
        case cameraDenied
        case notSupported
        case portInUse(UInt16)
        case failed(String)
    }

    /// A source is up and readings could arrive.
    var isSourceActive: Bool {
        switch self {
        case .starting, .searching, .live, .lost, .listening, .receiving: true
        case .off, .standby, .unavailable: false
        }
    }

    /// Readings are flowing right now.
    var isTracking: Bool {
        switch self {
        case .live, .receiving: true
        default: false
        }
    }

    /// Short wording for meters and the status capsule.
    var label: String {
        switch self {
        case .off: "Off"
        case .standby: "Waiting for a still on an active feed"
        case .starting: "Starting…"
        case .searching: "Looking for your face…"
        case .live: "Tracking live"
        case .lost: "Lost — idling"
        case .listening: "Listening…"
        case .receiving: "Receiving"
        case .unavailable(.cameraDenied): "Camera access denied"
        case .unavailable(.notSupported): "Face tracking isn't supported on this device"
        case .unavailable(.portInUse(let port)): "Port \(port) is already in use"
        case .unavailable(.failed(let reason)): reason
        }
    }
}
