import Foundation

/// What a face source tells the controller. Both sources speak this; the
/// controller never sees ARKit or Network types.
nonisolated enum FaceSourceEvent: Sendable {
    /// A reading. `sender` names the second iPhone for Live Link Face packets
    /// and is nil for this phone's own camera. A pose with `hasFace == false`
    /// only proves the source is alive.
    case pose(FacePose, sender: String?)

    /// This iPhone's camera is running and no face is in view.
    case searching

    /// Something else took the camera; ARKit resumes on its own when it's returned.
    case interrupted

    /// The camera came back after an interruption.
    case resumed

    /// The UDP listener is bound and ready.
    case listening(port: UInt16)

    /// The port could not be bound.
    case portUnavailable(port: UInt16)

    /// The source stopped for good.
    case failed(String)

    /// The camera is not authorised for this app.
    case cameraDenied
}
