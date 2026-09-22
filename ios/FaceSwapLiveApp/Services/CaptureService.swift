import AVFoundation
import CoreImage
import Synchronization
import UIKit

/// Whether the camera can be shown right now and, if not, why.
nonisolated enum CaptureAvailability: Sendable, Equatable {
    /// Nothing has asked for the camera yet, or it has been released.
    case idle
    /// Permission is being checked and the session is coming up.
    case starting
    /// Frames are flowing.
    case running
    /// The user has refused camera access; only Settings can change that.
    case permissionDenied
    /// No camera device is present at all.
    case noCamera
    /// The session could not be started for another reason.
    case failed(String)
}

/// How the interface is turned, so the sensor's native landscape frame can be
/// stood upright to match it.
nonisolated enum DisplayRotation: Sendable, Equatable {
    case portrait
    case portraitUpsideDown
    /// Home indicator on the left.
    case landscapeLeft
    /// Home indicator on the right: the sensor's own orientation.
    case landscapeRight

    init(_ interface: UIInterfaceOrientation) {
        switch interface {
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: self = .portrait
        }
    }

    /// The EXIF orientation that turns a native camera frame upright for this
    /// rotation — mirrored for the front camera so the preview behaves like a
    /// mirror. Portrait gives the classic `.right` / `.leftMirrored` pair.
    func imageOrientation(mirrored: Bool) -> CGImagePropertyOrientation {
        switch (self, mirrored) {
        case (.portrait, false): .right
        case (.portrait, true): .leftMirrored
        case (.portraitUpsideDown, false): .left
        case (.portraitUpsideDown, true): .rightMirrored
        case (.landscapeRight, false): .up
        case (.landscapeRight, true): .upMirrored
        case (.landscapeLeft, false): .down
        case (.landscapeLeft, true): .downMirrored
        }
    }
}

/// One analysed camera frame, ready for the screen.
///
/// The preview wraps the camera's own pixel buffer with an orientation
/// applied, so nothing is copied through CPU memory on its way to the GPU.
/// The face has already been found, so nothing AVFoundation owns ever leaves
/// the capture queue.
nonisolated struct FrameOutput: Sendable {
    /// The frame as the user should see it, in display orientation.
    let preview: CIImage
    /// Pixel size of `preview`, which is also the space `analysis` reports in.
    let bufferSize: CGSize
    /// The face found in this frame, or `nil` when none was.
    let analysis: ImageAnalysisResult?
    /// Whether Vision ran on this frame at all. When it did not, the previous
    /// result is still the best guess and the screen keeps it.
    let visionRan: Bool
    /// A finished photo, when a capture was pending for this frame.
    let captured: UIImage?
}

/// Receives frames on the capture queue and turns each into a `FrameOutput`.
///
/// This is the only object that touches sample buffers. Its few pieces of
/// shared state sit behind a `Mutex`, so the compiler can prove the pipeline
/// is safe to hand to AVFoundation and to the main actor at the same time.
nonisolated final class FramePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
    private struct State: Sendable {
        var mirrored = false
        /// External cameras deliver upright frames already; only the built-in
        /// sensors need turning to match the interface.
        var followsInterface = true
        var rotation: DisplayRotation = .portrait
        var pendingCapture: CaptureContext?
        var skipNextVision = false

        var orientation: CGImagePropertyOrientation {
            guard followsInterface else { return mirrored ? .upMirrored : .up }
            return rotation.imageOrientation(mirrored: mirrored)
        }
    }

    /// Vision that takes longer than this on a frame yields the next one to
    /// the preview alone, so the picture stays fluid on slower phones.
    private static let visionBudget: Duration = .milliseconds(24)

    private let processor: ImageProcessor
    private let state = Mutex(State())
    private let sink: AsyncStream<FrameOutput>.Continuation

    init(processor: ImageProcessor, sink: AsyncStream<FrameOutput>.Continuation) {
        self.processor = processor
        self.sink = sink
        super.init()
    }

    /// Describes the camera now feeding the pipeline.
    func setSource(mirrored: Bool, followsInterface: Bool) {
        state.withLock {
            $0.mirrored = mirrored
            $0.followsInterface = followsInterface
        }
    }

    /// Follows the interface so the picture stays upright when the phone turns.
    func setRotation(_ rotation: DisplayRotation) {
        state.withLock { $0.rotation = rotation }
    }

    /// The next frame is composited with this context and delivered as `captured`.
    func requestCapture(_ context: CaptureContext) {
        state.withLock { $0.pendingCapture = context }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let (orientation, pending, runVision) = state.withLock { s -> (CGImagePropertyOrientation, CaptureContext?, Bool) in
            let run = !s.skipNextVision
            s.skipNextVision = false
            let context = s.pendingCapture
            s.pendingCapture = nil
            return (s.orientation, context, run)
        }

        // Orientation is metadata on the image, not a render: the pixels stay
        // in the camera's buffer and the GPU applies the turn when it draws.
        let preview = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let extent = preview.extent
        guard extent.width > 0, extent.height > 0 else { return }

        var analysis: ImageAnalysisResult?
        if runVision {
            let started = ContinuousClock.now
            analysis = processor.detectFeatures(in: pixelBuffer, orientation: orientation)
            if ContinuousClock.now - started > Self.visionBudget {
                state.withLock { $0.skipNextVision = true }
            }
        }

        let captured = pending.flatMap {
            processor.compositeCapture(pixelBuffer: pixelBuffer, orientation: orientation, context: $0)
        }

        sink.yield(FrameOutput(
            preview: preview,
            bufferSize: CGSize(width: extent.width, height: extent.height),
            analysis: analysis,
            visionRan: runVision,
            captured: captured
        ))
    }
}

/// Owns the camera session.
///
/// Every AVFoundation call runs on one serial queue — this actor's executor —
/// so `startRunning()` never blocks the main thread and the session itself is
/// never shared with anything. Frames leave through the `FramePipeline`.
actor CaptureService {
    private let sessionQueue = DispatchSerialQueue(label: "com.app.capture.session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "com.app.capture.frames", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let pipeline: FramePipeline
    private var position: AVCaptureDevice.Position = .back
    private var hasOutput = false

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        sessionQueue.asUnownedSerialExecutor()
    }

    init(pipeline: FramePipeline) {
        self.pipeline = pipeline
    }

    /// Asks for permission when it has not been decided, then brings the
    /// session up. The result says exactly what the screen should show.
    func start() async -> CaptureAvailability {
        guard await Self.ensurePermission() else { return .permissionDenied }
        // The screen may have gone away while the permission sheet was up;
        // a camera nobody is watching should not be started.
        guard !Task.isCancelled else { return .idle }
        return bringUp()
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    /// Flips between the front and back cameras.
    func switchPosition() -> CaptureAvailability {
        position = (position == .front) ? .back : .front
        return bringUp()
    }

    private static func ensurePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    private func bringUp() -> CaptureAvailability {
        if let problem = configureSession() {
            return problem
        }
        if !session.isRunning {
            session.startRunning()
        }
        return session.isRunning ? .running : .failed("The camera could not be started.")
    }

    /// The camera for `position`, falling back to any external camera (the
    /// cloud simulator injects the webcam as one) and then to whatever
    /// built-in camera exists, so switching never strands the user.
    private func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let devices = discovery.devices
        if let wanted = devices.first(where: { $0.deviceType == .builtInWideAngleCamera && $0.position == position }) {
            return wanted
        }
        if let external = devices.first(where: { $0.deviceType == .external }) {
            return external
        }
        return devices.first
    }

    /// Rebuilds the session's input for the current position. Returns the
    /// problem when there is one, `nil` when a camera is wired up.
    private func configureSession() -> CaptureAvailability? {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for input in session.inputs {
            session.removeInput(input)
        }

        if !hasOutput {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(pipeline, queue: frameQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
                hasOutput = true
            }
        }

        session.sessionPreset = .high

        guard let device = device(for: position) else { return .noCamera }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            return .failed("\(device.localizedName) could not be opened.")
        }
        session.addInput(input)

        pipeline.setSource(
            mirrored: device.position == .front,
            followsInterface: device.deviceType != .external
        )
        return nil
    }
}
