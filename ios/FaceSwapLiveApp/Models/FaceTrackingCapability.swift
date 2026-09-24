import ARKit
import AVFoundation
import Foundation

/// What this phone can do for same-iPhone tracking. Head pose is still supplied
/// on the non-Face-ID path; that path is noisier, not expression-only.
nonisolated enum FaceTrackingCapability: Sendable, Equatable {
    case faceID
    case neuralEngine
    case unsupported

    var title: String {
        switch self {
        case .faceID: "Face ID iPhone"
        case .neuralEngine: "No Face ID"
        case .unsupported: "Not supported on this device"
        }
    }

    var detail: String {
        switch self {
        case .faceID:
            "Full read from the front camera."
        case .neuralEngine:
            "Works, but noisier in dim light. Head movement is still read."
        case .unsupported:
            "Use a second iPhone running Live Link Face."
        }
    }

    static func classify(faceTrackingSupported: Bool, hasTrueDepth: Bool) -> FaceTrackingCapability {
        guard faceTrackingSupported else { return .unsupported }
        return hasTrueDepth ? .faceID : .neuralEngine
    }

    @MainActor
    static func current() -> FaceTrackingCapability {
        let hasTrueDepth = !AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTrueDepthCamera],
            mediaType: .video,
            position: .front
        ).devices.isEmpty
        return classify(
            faceTrackingSupported: ARFaceTrackingConfiguration.isSupported,
            hasTrueDepth: hasTrueDepth
        )
    }
}
