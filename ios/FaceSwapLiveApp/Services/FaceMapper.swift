import CoreGraphics
import Foundation
import UIKit
import Vision

/// The 76-point pass. Runs on the same upright copy the face finder uses.
nonisolated struct FaceMapResult: Sendable {
    var faces: [MappedFace]
    var primary: MappedFace?
    var rig: FaceRig?
    var fingerprint: PhotoFingerprint?
    var note: String?
}

nonisolated enum FaceMapper {
    @concurrent
    static func map(_ image: UIImage) async -> FaceMapResult {
        guard let cgImage = FaceFinder.uprightCopy(of: image) else {
            return FaceMapResult(faces: [], note: FaceMapNote.noFace)
        }
        let faces = detect(in: cgImage)
        guard let primary = FacePicker.largestUpright(among: faces) else {
            return FaceMapResult(faces: faces, note: FaceMapNote.noFace)
        }
        let pixels = PhotoFingerprint.rgbaPixels(of: UIImage(cgImage: cgImage))
        let grey = pixels.map { FaceFlags.luma(of: $0.bytes, width: $0.width, height: $0.height) } ?? []
        let glasses = wearsGlasses(face: primary, grey: grey, width: cgImage.width, height: cgImage.height)
        let teeth = showsTeeth(face: primary, grey: grey, width: cgImage.width, height: cgImage.height)
        guard let rig = FaceRigBuilder.build(from: primary, wearsGlasses: glasses, teethVisible: teeth) else {
            return FaceMapResult(faces: faces, primary: primary, note: FaceMapNote.couldntMap)
        }
        return FaceMapResult(
            faces: faces,
            primary: primary,
            rig: rig,
            fingerprint: PhotoFingerprint.make(from: image),
            note: nil
        )
    }

    private static func detect(in image: CGImage) -> [MappedFace] {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        if VNDetectFaceLandmarksRequest.revision(VNDetectFaceLandmarksRequestRevision3, supportsConstellation: .constellation76Points) {
            request.constellation = .constellation76Points
        }
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let size = CGSize(width: image.width, height: image.height)
        return (request.results ?? []).enumerated().compactMap { index, face in
            mapped(face, index: index, imageSize: size)
        }
    }

    private static func mapped(_ face: VNFaceObservation, index: Int, imageSize: CGSize) -> MappedFace? {
        guard let landmarks = face.landmarks else { return nil }
        var regions: [FaceRegion: FaceSample] = [:]
        func store(_ region: FaceRegion, _ sample: VNFaceLandmarkRegion2D?) {
            guard let sample, sample.pointCount > 0 else { return }
            let points = imagePoints(sample, box: face.boundingBox)
            guard !points.isEmpty else { return }
            regions[region] = FaceSample(points: points, confidence: confidence(of: sample, fallback: face.confidence))
        }
        store(.faceContour, landmarks.faceContour)
        store(.leftEye, landmarks.leftEye)
        store(.rightEye, landmarks.rightEye)
        store(.leftEyebrow, landmarks.leftEyebrow)
        store(.rightEyebrow, landmarks.rightEyebrow)
        store(.nose, landmarks.nose)
        store(.noseCrest, landmarks.noseCrest)
        store(.medianLine, landmarks.medianLine)
        store(.outerLips, landmarks.outerLips)
        store(.innerLips, landmarks.innerLips)
        store(.leftPupil, landmarks.leftPupil)
        store(.rightPupil, landmarks.rightPupil)
        guard !regions.isEmpty else { return nil }
        let box = face.boundingBox
        return MappedFace(
            id: index,
            bounds: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height),
            roll: face.roll?.doubleValue ?? 0,
            yaw: face.yaw?.doubleValue ?? 0,
            pitch: face.pitch?.doubleValue ?? 0,
            confidence: face.confidence,
            regions: regions
        )
    }

    /// Landmark points are in the face box, origin at its lower left.
    private static func imagePoints(_ region: VNFaceLandmarkRegion2D, box: CGRect) -> [CGPoint] {
        let pointer = region.normalizedPoints
        return (0..<region.pointCount).map { index in
            let point = pointer[index]
            let x = box.minX + CGFloat(point.x) * box.width
            let yFromBottom = box.minY + CGFloat(point.y) * box.height
            return CGPoint(x: x, y: 1 - yFromBottom)
        }
    }

    private static func confidence(of region: VNFaceLandmarkRegion2D, fallback: Float) -> Float {
        guard let estimates = region.precisionEstimatesPerPoint, !estimates.isEmpty else { return fallback }
        let total = estimates.reduce(Float(0), +)
        return total / Float(estimates.count)
    }

    private static func wearsGlasses(face: MappedFace, grey: [UInt8], width: Int, height: Int) -> Bool {
        let eyes = (face.sample(.leftEye)?.points ?? []) + (face.sample(.rightEye)?.points ?? [])
        guard let eyeBox = bounds(of: eyes) else { return false }
        let padY = max(0.012, eyeBox.height * 1.1)
        let padX = max(0.01, eyeBox.width * 0.04)
        let band = eyeBox.insetBy(dx: -padX, dy: -padY)
        return FaceFlags.wearsGlasses(luma: grey, width: width, height: height, eyeBand: band)
    }

    private static func showsTeeth(face: MappedFace, grey: [UInt8], width: Int, height: Int) -> Bool {
        let inner = face.sample(.innerLips)?.points ?? []
        let outer = face.sample(.outerLips)?.points ?? []
        let mouth = bounds(of: inner.isEmpty ? outer : inner)
        guard let mouth else { return false }
        let opening = (inner.map(\.y).max() ?? 0) - (inner.map(\.y).min() ?? 0)
        return FaceFlags.teethVisible(
            luma: grey,
            width: width,
            height: height,
            mouth: mouth,
            opening: opening,
            faceHeight: max(0.05, face.bounds.height)
        )
    }

    private static func bounds(of points: [CGPoint]) -> CGRect? {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max(),
              maxX > minX, maxY > minY
        else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
