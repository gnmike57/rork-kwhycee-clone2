import AVFoundation
import CoreGraphics
import Vision

/// Decides which camera a clip belongs to by looking at a handful of frames.
///
/// The rule is deliberately blunt because the real world is: a human face means
/// front camera, everything else means back camera. Faces are checked first on
/// purpose — a person holding their ID up to the lens is still a front-camera
/// capture.
nonisolated final class MediaSubjectClassifier: Sendable {
    /// Frames sampled across the clip. Enough to survive a blink, a pan or a
    /// dark opening frame without paying for a full decode.
    private let sampleCount: Int = 6

    /// A face smaller than this share of the frame is treated as background
    /// noise (a photo on a wall behind a document, for example).
    private let minimumFaceArea: CGFloat = 0.012

    /// Runs off the caller's actor: decoding and the Vision requests are real
    /// work that has no place on the main thread.
    @concurrent
    func classify(url: URL) async -> MediaSubjectDecision {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let frames = await sampleFrames(from: asset)

        guard !frames.isEmpty else {
            return MediaSubjectDecision(
                subject: .person,
                reason: "Could not read frames — assumed a person, the more common case."
            )
        }

        var faceFrames = 0
        var humanFrames = 0
        var documentFrames = 0

        for frame in frames {
            let handler = VNImageRequestHandler(cgImage: frame, options: [:])

            let faceRequest = VNDetectFaceRectanglesRequest()
            let humanRequest = VNDetectHumanRectanglesRequest()
            humanRequest.upperBodyOnly = false
            let documentRequest = VNDetectDocumentSegmentationRequest()

            try? handler.perform([faceRequest, humanRequest, documentRequest])

            let faces = (faceRequest.results ?? []).filter { observation in
                let box = observation.boundingBox
                return box.width * box.height >= minimumFaceArea
            }
            if !faces.isEmpty { faceFrames += 1 }

            let humans = (humanRequest.results ?? []).filter { $0.confidence >= 0.5 }
            if !humans.isEmpty { humanFrames += 1 }

            let documents = (documentRequest.results ?? []).filter { $0.confidence >= 0.6 }
            if !documents.isEmpty { documentFrames += 1 }
        }

        if faceFrames > 0 {
            return MediaSubjectDecision(
                subject: .person,
                reason: "Face found in \(faceFrames) of \(frames.count) sampled frames."
            )
        }

        if humanFrames >= max(1, frames.count / 3) {
            return MediaSubjectDecision(
                subject: .person,
                reason: "Person detected in \(humanFrames) of \(frames.count) sampled frames."
            )
        }

        if documentFrames > 0 {
            return MediaSubjectDecision(
                subject: .document,
                reason: "No face; document edges found in \(documentFrames) of \(frames.count) frames."
            )
        }

        return MediaSubjectDecision(
            subject: .document,
            reason: "No face or person in \(frames.count) sampled frames."
        )
    }

    private func sampleFrames(from asset: AVURLAsset) async -> [CGImage] {
        let duration = (try? await asset.load(.duration)) ?? .zero
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        // Snapping to nearby keyframes keeps this to a fraction of a second even
        // on long clips; exact timing is irrelevant for "is there a face".
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var images: [CGImage] = []
        for index in 0..<sampleCount {
            if Task.isCancelled { break }
            // Skip the very start and very end, where clips often hold a black
            // or blurred frame.
            let fraction = (Double(index) + 0.5) / Double(sampleCount)
            let time = CMTime(seconds: seconds * fraction, preferredTimescale: 600)
            if let result = try? await generator.image(at: time) {
                images.append(result.image)
            }
        }
        return images
    }
}
