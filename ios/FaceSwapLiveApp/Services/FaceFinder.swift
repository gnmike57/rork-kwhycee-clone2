import UIKit
import Vision

/// Finds the main face in a still so Frame Check can centre and fit around it.
///
/// Detection runs on a small copy of the still, off the main actor, and the
/// result is reported in the still's displayed orientation with a top-left
/// origin — the same coordinates the page draws in.
nonisolated final class FaceFinder: Sendable {

    /// Long side the still is reduced to before detection. Faces survive this
    /// comfortably and it keeps the work under a frame or two.
    private static let workingLongSide: CGFloat = 1024

    /// Largest face with usable confidence, or `nil` when none is found.
    func findFace(in image: UIImage) async -> FaceBox? {
        await Self.detect(in: image)
    }

    /// Structured rather than detached, so cancelling the caller cancels the
    /// detection and the work leaves the caller's actor on its own.
    @concurrent
    private static func detect(in image: UIImage) async -> FaceBox? {
        guard let cgImage = Self.workingCopy(of: image) else { return nil }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let face = request.results?
            .filter({ $0.confidence >= 0.5 })
            .max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })
        else { return nil }

        // Vision reports a bottom-left origin; the page draws top-left.
        let box = face.boundingBox
        let rect = CGRect(
            x: box.minX,
            y: 1 - box.minY - box.height,
            width: box.width,
            height: box.height
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }
        return FaceBox(rect: rect)
    }

    /// The upright copy detection runs on. Shared with the 76-point pass so
    /// both see the same picture the page draws.
    static func uprightCopy(of image: UIImage) -> CGImage? {
        workingCopy(of: image)
    }

    /// Redraws the still upright at a small size so orientation metadata can
    /// never flip the result.
    private static func workingCopy(of image: UIImage) -> CGImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let longest = max(size.width, size.height)
        let scale = min(1, workingLongSide / longest)
        let target = CGSize(
            width: max(1, (size.width * scale).rounded()),
            height: max(1, (size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let drawn = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return drawn.cgImage
    }
}
