import CoreGraphics
import Foundation

/// One named region of Apple's 76-point face map.
nonisolated enum FaceRegion: String, Codable, CaseIterable, Sendable {
    case faceContour
    case leftEye
    case rightEye
    case leftEyebrow
    case rightEyebrow
    case nose
    case noseCrest
    case medianLine
    case outerLips
    case innerLips
    case leftPupil
    case rightPupil
}

/// Points for one region, in the upright photo, origin at the top left.
nonisolated struct FaceSample: Codable, Sendable, Equatable {
    var points: [CGPoint]
    /// 0…1. Missing precision estimates fall back to the face's own confidence.
    var confidence: Float
}

/// One face found in a still. Coordinates are normalized, top-left origin.
nonisolated struct MappedFace: Codable, Sendable, Equatable, Identifiable {
    var id: Int
    var bounds: CGRect
    var roll: Double
    var yaw: Double
    var pitch: Double
    var confidence: Float
    var regions: [FaceRegion: FaceSample]

    var area: CGFloat { max(0, bounds.width) * max(0, bounds.height) }

    func sample(_ region: FaceRegion) -> FaceSample? {
        guard let sample = regions[region], !sample.points.isEmpty else { return nil }
        return sample
    }
}

/// The button text when a still has no usable face map.
nonisolated enum FaceMapNote {
    static let noFace = "No face found in this photo"
    static let couldntMap = "Couldn't map this face"
}

/// With several faces, the largest upright one wins.
nonisolated enum FacePicker {
    /// About 40°. A 20° tilt still counts as upright; a sideways face does not.
    static let uprightRollLimit = 40 * Double.pi / 180

    static func largestUpright(among faces: [MappedFace]) -> MappedFace? {
        let upright = faces.filter { abs($0.roll) <= uprightRollLimit }
        let pool = upright.isEmpty ? faces : upright
        return pool.max { $0.area < $1.area }
    }
}
