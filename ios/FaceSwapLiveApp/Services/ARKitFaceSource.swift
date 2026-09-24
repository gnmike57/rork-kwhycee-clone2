import ARKit
import AVFoundation
import UIKit

/// This iPhone's own face tracking through the front camera, delivered as a
/// stream of poses at the camera's rate (60/s on current phones).
///
/// Owns the `ARSession`; frames are converted on ARKit's queue by
/// `ARKitFaceRelay`, so nothing heavier than a `FacePose` reaches the main actor.
@MainActor
final class ARKitFaceSource {
    /// False on the simulator and on the few iPads without a TrueDepth or
    /// A12-class front camera pipeline.
    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    let events: AsyncStream<FaceSourceEvent>

    private let session = ARSession()
    private let relay: ARKitFaceRelay
    private let sink: AsyncStream<FaceSourceEvent>.Continuation
    private let queue = DispatchQueue(label: "com.app.facetracking.arkit", qos: .userInteractive)
    private(set) var isRunning = false
    private var appliedRate = 0

    init() {
        let (stream, continuation) = AsyncStream<FaceSourceEvent>.makeStream(bufferingPolicy: .bufferingNewest(8))
        events = stream
        sink = continuation
        relay = ARKitFaceRelay(sink: continuation)
        session.delegate = relay
        session.delegateQueue = queue
    }

    /// Asks for the camera when undecided, then runs face tracking. Denied or
    /// unsupported cases are reported through `events` rather than thrown.
    func start() async {
        guard Self.isSupported else {
            sink.yield(.failed(FaceTrackingState.Problem.notSupported.description))
            return
        }
        guard await Self.ensureCameraPermission() else {
            sink.yield(.cameraDenied)
            return
        }
        guard !Task.isCancelled else { return }

        appliedRate = TrackerRate.framesPerSecond(for: ProcessInfo.processInfo.thermalState)
        relay.sessionRestarted()
        session.run(makeConfiguration(rate: appliedRate), options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    /// Releases the camera immediately, before anything else may open it.
    func stop() {
        guard isRunning else { return }
        session.pause()
        isRunning = false
        appliedRate = 0
    }

    /// Steps the tracker between 60 and 30 without resetting the face.
    func setPreferredFrameRate(_ fps: Int) {
        guard isRunning, fps != appliedRate else { return }
        appliedRate = fps
        session.run(makeConfiguration(rate: fps))
    }

    private func makeConfiguration(rate: Int) -> ARFaceTrackingConfiguration {
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = false
        configuration.maximumNumberOfTrackedFaces = 1
        if let format = Self.videoFormat(preferring: rate) {
            configuration.videoFormat = format
        }
        return configuration
    }

    private static func videoFormat(preferring fps: Int) -> ARConfiguration.VideoFormat? {
        let formats = ARFaceTrackingConfiguration.supportedVideoFormats
        guard let index = TrackerRate.indexPreferring(fps, among: formats.map(\.framesPerSecond)) else {
            return nil
        }
        return formats[index]
    }

    func setInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        relay.setInterfaceOrientation(orientation)
    }

    private static func ensureCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

extension FaceTrackingState.Problem {
    /// Wording for the failure channel when a source cannot even start.
    var description: String {
        FaceTrackingState.unavailable(self).label
    }
}
