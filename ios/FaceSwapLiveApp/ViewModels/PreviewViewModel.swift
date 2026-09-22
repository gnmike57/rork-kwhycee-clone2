import SwiftUI
import AVFoundation
import CoreImage

@Observable
@MainActor
final class PreviewViewModel {
    /// The latest camera frame, already upright and mirrored as the user expects.
    var previewFrame: CIImage?
    /// What the camera area should show right now.
    var availability: CaptureAvailability = .idle
    var overlayImage: UIImage?
    var selectedSourceImage: UIImage?
    var detectedRect: CGRect = .zero
    var roll: CGFloat = 0
    var sourceAspectRatio: CGFloat = 1.0
    var isActive: Bool = false
    var isProcessingSource: Bool = false
    var showImageSelection: Bool = false
    var showGallery: Bool = false
    var showNoResultAlert: Bool = false
    var showCaptureFlash: Bool = false
    var capturedImages: [CapturedImage] = []
    var viewSize: CGSize = .zero
    var showDebugOverlay: Bool = false
    var debugLandmarkScreenPoints: [CGPoint] = []

    /// Pixel size of the frames being shown; the space `detectedRect` is mapped from.
    private var bufferSize: CGSize = .zero

    private let processor: ImageProcessor
    private let pipeline: FramePipeline
    private let frames: AsyncStream<FrameOutput>
    private let captureService: CaptureService
    private var frameTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var sourceTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?

    init() {
        let processor = ImageProcessor()
        // Only the newest frame is ever waiting: a slow main thread drops
        // frames rather than falling behind the camera.
        let (stream, continuation) = AsyncStream<FrameOutput>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let pipeline = FramePipeline(processor: processor, sink: continuation)
        self.processor = processor
        self.pipeline = pipeline
        self.frames = stream
        self.captureService = CaptureService(pipeline: pipeline)
    }

    var isCameraRunning: Bool { availability == .running }

    func startCapture() {
        if frameTask == nil {
            frameTask = Task { [weak self, frames] in
                for await frame in frames {
                    guard let self else { return }
                    self.apply(frame)
                }
            }
        }
        availability = .starting
        runSession { service in await service.start() }
    }

    func stopCapture() {
        // Cancel whatever is in flight, then stop strictly after it, so a
        // start that was half-way through cannot leave the camera running.
        sessionTask?.cancel()
        let previous = sessionTask
        sessionTask = Task { [captureService] in
            _ = await previous?.value
            await captureService.stop()
        }
        availability = .idle
        previewFrame = nil
    }

    func switchPosition() {
        runSession { service in await service.switchPosition() }
    }

    /// The interface turned; the next frames are stood upright to match.
    func setRotation(_ rotation: DisplayRotation) {
        pipeline.setRotation(rotation)
    }

    /// Session changes queue behind one another so a fast double tap on the
    /// flip button cannot interleave two reconfigurations.
    private func runSession(_ operation: @escaping @Sendable (CaptureService) async -> CaptureAvailability) {
        let previous = sessionTask
        sessionTask = Task { [weak self, captureService] in
            _ = await previous?.value
            let result = await operation(captureService)
            guard !Task.isCancelled else { return }
            self?.availability = result
        }
    }

    private func apply(_ frame: FrameOutput) {
        previewFrame = frame.preview
        bufferSize = frame.bufferSize

        if frame.visionRan {
            if let result = frame.analysis {
                detectedRect = convertToScreen(
                    result.boundingBox,
                    bufferWidth: result.bufferWidth,
                    bufferHeight: result.bufferHeight
                )
                roll = result.roll
                debugLandmarkScreenPoints = result.landmarkPoints.map { point in
                    convertPointToScreen(point, bufferWidth: result.bufferWidth, bufferHeight: result.bufferHeight)
                }
            } else {
                detectedRect = .zero
                roll = 0
                debugLandmarkScreenPoints = []
            }
        }

        if let captured = frame.captured {
            capturedImages.insert(CapturedImage(image: captured), at: 0)
        }
    }

    func selectSourceImage(_ image: UIImage) {
        selectedSourceImage = image
        isProcessingSource = true
        let processor = self.processor

        sourceTask?.cancel()
        sourceTask = Task { [weak self] in
            let result = await Self.processSource(image, with: processor)
            guard let self, !Task.isCancelled else { return }
            self.isProcessingSource = false
            if let result {
                self.overlayImage = result.overlay
                self.sourceAspectRatio = result.aspectRatio
                self.isActive = true
            } else {
                self.showNoResultAlert = true
                self.isActive = false
            }
            self.showImageSelection = false
        }
    }

    /// Face detection and the halo mask are heavy; they leave the main actor.
    @concurrent
    nonisolated private static func processSource(_ image: UIImage, with processor: ImageProcessor) async -> ImageProcessingResult? {
        processor.processSourceImage(image)
    }

    func clearSelection() {
        overlayImage = nil
        selectedSourceImage = nil
        isActive = false
        detectedRect = .zero
    }

    func capture() {
        guard let overlay = overlayImage, isCameraRunning else { return }
        pipeline.requestCapture(CaptureContext(
            overlayImage: overlay,
            overlayRect: detectedRect,
            viewSize: viewSize,
            bufferSize: bufferSize,
            sourceAspectRatio: sourceAspectRatio
        ))

        showCaptureFlash = true
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.showCaptureFlash = false
        }
    }

    /// One shared mapping from pixel-buffer coordinates to screen points, so
    /// the rect and landmark paths can never drift apart.
    private struct BufferTransform {
        let bufferWidth: CGFloat
        let bufferHeight: CGFloat
        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        func toScreen(x: CGFloat, y: CGFloat) -> CGPoint {
            CGPoint(
                x: x * bufferWidth * scale - offsetX,
                y: y * bufferHeight * scale - offsetY
            )
        }
    }

    private func bufferTransform(bufferWidth: Int, bufferHeight: Int) -> BufferTransform? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }

        let bw = CGFloat(bufferWidth)
        let bh = CGFloat(bufferHeight)
        guard bw > 0, bh > 0 else { return nil }

        let videoAspect = bw / bh
        let viewAspect = viewSize.width / viewSize.height

        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        if videoAspect > viewAspect {
            scale = viewSize.height / bh
            offsetX = (bw * scale - viewSize.width) / 2
            offsetY = 0
        } else {
            scale = viewSize.width / bw
            offsetX = 0
            offsetY = (bh * scale - viewSize.height) / 2
        }

        return BufferTransform(
            bufferWidth: bw,
            bufferHeight: bh,
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY
        )
    }

    private func convertToScreen(_ visionRect: CGRect, bufferWidth: Int, bufferHeight: Int) -> CGRect {
        guard let transform = bufferTransform(bufferWidth: bufferWidth, bufferHeight: bufferHeight) else {
            return .zero
        }

        let topLeft = transform.toScreen(
            x: visionRect.origin.x,
            y: 1 - visionRect.origin.y - visionRect.height
        )
        let size = CGSize(
            width: visionRect.width * transform.bufferWidth * transform.scale,
            height: visionRect.height * transform.bufferHeight * transform.scale
        )
        return CGRect(origin: topLeft, size: size)
    }

    private func convertPointToScreen(_ point: CGPoint, bufferWidth: Int, bufferHeight: Int) -> CGPoint {
        guard let transform = bufferTransform(bufferWidth: bufferWidth, bufferHeight: bufferHeight) else {
            return .zero
        }
        return transform.toScreen(x: point.x, y: 1 - point.y)
    }
}
