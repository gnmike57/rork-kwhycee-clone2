import CoreGraphics
import Foundation

/// The 18 points that steer the mesh. They never move pixels themselves.
nonisolated enum FaceHandle: String, Codable, CaseIterable, Sendable {
    case leftEyeCenter
    case rightEyeCenter
    case leftEyeOuter
    case leftEyeInner
    case rightEyeInner
    case rightEyeOuter
    case leftBrowCenter
    case leftBrowTail
    case rightBrowCenter
    case rightBrowTail
    case noseTip
    case mouthLeft
    case mouthRight
    case upperLip
    case lowerLip
    case chin
    case leftJaw
    case rightJaw

    var title: String {
        switch self {
        case .leftEyeCenter: "Left eye centre"
        case .rightEyeCenter: "Right eye centre"
        case .leftEyeOuter: "Left eye outer corner"
        case .leftEyeInner: "Left eye inner corner"
        case .rightEyeInner: "Right eye inner corner"
        case .rightEyeOuter: "Right eye outer corner"
        case .leftBrowCenter: "Left brow centre"
        case .leftBrowTail: "Left brow tail"
        case .rightBrowCenter: "Right brow centre"
        case .rightBrowTail: "Right brow tail"
        case .noseTip: "Nose tip"
        case .mouthLeft: "Left mouth corner"
        case .mouthRight: "Right mouth corner"
        case .upperLip: "Upper lip"
        case .lowerLip: "Lower lip"
        case .chin: "Chin"
        case .leftJaw: "Left jaw"
        case .rightJaw: "Right jaw"
        }
    }

    var region: FaceRegion {
        switch self {
        case .leftEyeCenter, .leftEyeOuter, .leftEyeInner: .leftEye
        case .rightEyeCenter, .rightEyeOuter, .rightEyeInner: .rightEye
        case .leftBrowCenter, .leftBrowTail: .leftEyebrow
        case .rightBrowCenter, .rightBrowTail: .rightEyebrow
        case .noseTip: .nose
        case .mouthLeft, .mouthRight, .upperLip, .lowerLip: .outerLips
        case .chin, .leftJaw, .rightJaw: .faceContour
        }
    }

    /// The handle on the other side, when there is one.
    var mirror: FaceHandle? {
        switch self {
        case .leftEyeCenter: .rightEyeCenter
        case .rightEyeCenter: .leftEyeCenter
        case .leftEyeOuter: .rightEyeOuter
        case .rightEyeOuter: .leftEyeOuter
        case .leftEyeInner: .rightEyeInner
        case .rightEyeInner: .leftEyeInner
        case .leftBrowCenter: .rightBrowCenter
        case .rightBrowCenter: .leftBrowCenter
        case .leftBrowTail: .rightBrowTail
        case .rightBrowTail: .leftBrowTail
        case .mouthLeft: .mouthRight
        case .mouthRight: .mouthLeft
        case .leftJaw: .rightJaw
        case .rightJaw: .leftJaw
        case .noseTip, .upperLip, .lowerLip, .chin: nil
        }
    }
}

/// A correction stored as a nudge from the detected position, not a new point.
nonisolated struct FaceNudge: Codable, Sendable, Equatable {
    var dx: Double
    var dy: Double

    static let zero = FaceNudge(dx: 0, dy: 0)
}

nonisolated enum FaceLayer: String, Codable, Sendable {
    case eye
    case mouth
    case brow
    case jaw
    case skin
    case edge
}

nonisolated struct FaceTriangle: Codable, Sendable, Equatable {
    var a: Int
    var b: Int
    var c: Int
    var layer: FaceLayer
}

/// The photo's own rest face, measured at import.
nonisolated struct FaceRest: Codable, Sendable, Equatable {
    var eyeOpening: Double
    var mouthOpening: Double
    var mouthWidth: Double
    var faceHeight: Double
    var tilt: Double
    var turn: Double
}

/// The mesh a still is taught. Versioned so a maths change can rebuild it
/// without throwing away the nudges.
nonisolated struct FaceRig: Codable, Sendable, Equatable {
    static let currentVersion = 1
    static let lowConfidence: Float = 0.45

    var version: Int
    var source: MappedFace
    var nudges: [FaceHandle: FaceNudge]
    var wearsGlasses: Bool
    var teethVisible: Bool
    var rest: FaceRest
    var handleIndex: [FaceHandle: Int]
    var vertices: [CGPoint]
    var triangles: [FaceTriangle]

    func detectedPosition(of handle: FaceHandle) -> CGPoint? {
        guard let index = handleIndex[handle], vertices.indices.contains(index) else { return nil }
        return vertices[index]
    }

    func position(of handle: FaceHandle) -> CGPoint? {
        guard let detected = detectedPosition(of: handle) else { return nil }
        let nudge = nudges[handle] ?? .zero
        return CGPoint(x: detected.x + nudge.dx, y: detected.y + nudge.dy)
    }

    func isLowConfidence(_ handle: FaceHandle) -> Bool {
        (source.sample(handle.region)?.confidence ?? 0) < Self.lowConfidence
    }

    /// Live head-turn gain. Full until about 15°, then reduced so a photo
    /// that is already turned does not tear.
    static func headTurnGain(turnRadians: Double) -> Double {
        let degrees = abs(turnRadians) * 180 / .pi
        guard degrees > 15 else { return 1 }
        let t = min(1, (degrees - 15) / 30)
        return 1 - 0.55 * t
    }

    /// Vertices after nudges, with a falloff so a handle moves its neighbours
    /// and leaves the far side of the face alone.
    func deformedVertices() -> [CGPoint] {
        guard !vertices.isEmpty else { return [] }
        let height = max(0.05, rest.faceHeight)
        let sigma = max(0.035, height * 0.22)
        var moved = vertices
        for (handle, nudge) in nudges where nudge.dx != 0 || nudge.dy != 0 {
            guard let anchorIndex = handleIndex[handle], vertices.indices.contains(anchorIndex) else { continue }
            let anchor = vertices[anchorIndex]
            for index in moved.indices {
                let point = vertices[index]
                let dx = point.x - anchor.x
                let dy = point.y - anchor.y
                let weight = exp(-(dx * dx + dy * dy) / (2 * sigma * sigma))
                moved[index].x += nudge.dx * weight
                moved[index].y += nudge.dy * weight
            }
        }
        return moved
    }

    /// Rebuilds the mesh from the stored face and keeps every nudge.
    func rebuilt(version: Int) -> FaceRig {
        var next = FaceRigBuilder.build(
            from: source,
            wearsGlasses: wearsGlasses,
            teethVisible: teethVisible
        ) ?? self
        next.nudges = nudges
        next.version = version
        return next
    }

    /// Mirrors nudges across the face midline. Centre handles lose their sideways nudge.
    func snappedToSymmetry() -> FaceRig {
        var next = self
        var mirrored: [FaceHandle: FaceNudge] = [:]
        for handle in FaceHandle.allCases {
            let nudge = nudges[handle] ?? .zero
            if let pair = handle.mirror {
                let other = nudges[pair] ?? .zero
                mirrored[handle] = FaceNudge(dx: -(other.dx + nudge.dx) / 2, dy: (other.dy + nudge.dy) / 2)
            } else {
                mirrored[handle] = FaceNudge(dx: 0, dy: nudge.dy)
            }
        }
        next.nudges = mirrored
        return next
    }
}

/// Builds a rig from a mapped face. Pure, so tests can feed it a synthetic set.
nonisolated enum FaceRigBuilder {
    /// Outward reach of the soft edge, as a fraction of face width.
    /// Temples stay tighter than the chin so ears and hair are not pulled.
    static func edgeReach(temple: Bool) -> CGFloat {
        temple ? 0.035 : 0.09
    }

    static func build(from face: MappedFace, wearsGlasses: Bool, teethVisible: Bool) -> FaceRig? {
        guard let contour = face.sample(.faceContour), contour.points.count >= 5,
              face.sample(.leftEye) != nil,
              face.sample(.rightEye) != nil,
              face.sample(.outerLips) != nil
        else { return nil }

        let center = centroid(contour.points)
        var vertices: [CGPoint] = []
        var handleIndex: [FaceHandle: Int] = [:]

        func add(_ point: CGPoint) -> Int {
            vertices.append(point)
            return vertices.count - 1
        }

        func addHandle(_ handle: FaceHandle, _ point: CGPoint) {
            handleIndex[handle] = add(point)
        }

        if let eyes = eyeHandles(in: face) {
            for (handle, point) in eyes { addHandle(handle, point) }
        } else {
            return nil
        }
        for (handle, point) in browHandles(in: face) { addHandle(handle, point) }
        guard let mouth = mouthHandles(in: face) else { return nil }
        for (handle, point) in mouth { addHandle(handle, point) }
        guard let jaw = jawHandles(in: face) else { return nil }
        for (handle, point) in jaw { addHandle(handle, point) }
        if let nose = noseTip(in: face) {
            addHandle(.noseTip, nose)
        } else if let upper = handleIndex[.upperLip], let left = handleIndex[.leftEyeCenter], let right = handleIndex[.rightEyeCenter] {
            let eyeMid = CGPoint(x: (vertices[left].x + vertices[right].x) / 2, y: (vertices[left].y + vertices[right].y) / 2)
            addHandle(.noseTip, CGPoint(x: eyeMid.x, y: (eyeMid.y + vertices[upper].y) / 2))
        } else {
            return nil
        }
        if handleIndex[.leftBrowCenter] == nil, let eye = handleIndex[.leftEyeCenter] {
            addHandle(.leftBrowCenter, CGPoint(x: vertices[eye].x, y: vertices[eye].y - face.bounds.height * 0.08))
            addHandle(.leftBrowTail, CGPoint(x: vertices[eye].x + face.bounds.width * 0.08, y: vertices[eye].y - face.bounds.height * 0.06))
        }
        if handleIndex[.rightBrowCenter] == nil, let eye = handleIndex[.rightEyeCenter] {
            addHandle(.rightBrowCenter, CGPoint(x: vertices[eye].x, y: vertices[eye].y - face.bounds.height * 0.08))
            addHandle(.rightBrowTail, CGPoint(x: vertices[eye].x - face.bounds.width * 0.08, y: vertices[eye].y - face.bounds.height * 0.06))
        }
        guard handleIndex.count == FaceHandle.allCases.count else { return nil }

        for region in [FaceRegion.nose, .noseCrest, .medianLine, .innerLips, .leftPupil, .rightPupil] {
            for point in face.sample(region)?.points ?? [] { _ = add(point) }
        }

        let forehead = foreheadArc(in: face)
        let neck = neckFade(in: face, chin: jaw[.chin] ?? center)
        var ring: [CGPoint] = []
        let faceWidth = max(0.05, face.bounds.width)
        for point in contour.points + forehead {
            let temple = point.y < center.y - face.bounds.height * 0.12
            ring.append(offsetOutward(point, from: center, reach: faceWidth * edgeReach(temple: temple)))
        }
        ring.append(contentsOf: neck)

        let ringStart = vertices.count
        for point in ring { _ = add(point) }
        let centerIndex = add(center)
        let ringCount = centerIndex - ringStart
        guard ringCount >= 3 else { return nil }

        var triangles = fan(centerIndex: centerIndex, ringStart: ringStart, ringCount: ringCount, vertices: vertices)
        insertInterior(into: &triangles, vertices: vertices, ringStart: ringStart)
        tag(&triangles, vertices: vertices, ringStart: ringStart, ringCount: ringCount, face: face)
        appendRegionTriangles(&triangles, handleIndex: handleIndex)

        let rest = measurements(of: face, jaw: jaw)
        return FaceRig(
            version: FaceRig.currentVersion,
            source: face,
            nudges: [:],
            wearsGlasses: wearsGlasses,
            teethVisible: teethVisible,
            rest: rest,
            handleIndex: handleIndex,
            vertices: vertices,
            triangles: triangles
        )
    }

    private static func eyeHandles(in face: MappedFace) -> [FaceHandle: CGPoint]? {
        guard let left = face.sample(.leftEye), let right = face.sample(.rightEye) else { return nil }
        return [
            .leftEyeCenter: face.sample(.leftPupil)?.points.first ?? centroid(left.points),
            .rightEyeCenter: face.sample(.rightPupil)?.points.first ?? centroid(right.points),
            .leftEyeOuter: extreme(left.points, largestX: true),
            .leftEyeInner: extreme(left.points, largestX: false),
            .rightEyeInner: extreme(right.points, largestX: true),
            .rightEyeOuter: extreme(right.points, largestX: false)
        ]
    }

    private static func browHandles(in face: MappedFace) -> [FaceHandle: CGPoint] {
        var handles: [FaceHandle: CGPoint] = [:]
        if let left = face.sample(.leftEyebrow) {
            handles[.leftBrowCenter] = left.points[left.points.count / 2]
            handles[.leftBrowTail] = extreme(left.points, largestX: true)
        }
        if let right = face.sample(.rightEyebrow) {
            handles[.rightBrowCenter] = right.points[right.points.count / 2]
            handles[.rightBrowTail] = extreme(right.points, largestX: false)
        }
        return handles
    }

    private static func noseTip(in face: MappedFace) -> CGPoint? {
        let points = (face.sample(.nose)?.points ?? []) + (face.sample(.noseCrest)?.points ?? [])
        return points.max { $0.y < $1.y }
    }

    private static func mouthHandles(in face: MappedFace) -> [FaceHandle: CGPoint]? {
        guard let lips = face.sample(.outerLips) else { return nil }
        return [
            .mouthLeft: extreme(lips.points, largestX: true),
            .mouthRight: extreme(lips.points, largestX: false),
            .upperLip: lips.points.min { $0.y < $1.y } ?? centroid(lips.points),
            .lowerLip: lips.points.max { $0.y < $1.y } ?? centroid(lips.points)
        ]
    }

    private static func jawHandles(in face: MappedFace) -> [FaceHandle: CGPoint]? {
        guard let contour = face.sample(.faceContour) else { return nil }
        return [
            .chin: contour.points.max { $0.y < $1.y } ?? centroid(contour.points),
            .leftJaw: extreme(contour.points, largestX: true),
            .rightJaw: extreme(contour.points, largestX: false)
        ]
    }

    private static func foreheadArc(in face: MappedFace) -> [CGPoint] {
        let brows = (face.sample(.leftEyebrow)?.points ?? []) + (face.sample(.rightEyebrow)?.points ?? [])
        let top = brows.min { $0.y < $1.y }?.y ?? (face.bounds.minY + face.bounds.height * 0.25)
        let left = brows.max { $0.x < $1.x }?.x ?? face.bounds.maxX
        let right = brows.min { $0.x < $1.x }?.x ?? face.bounds.minX
        let lift = max(0.04, face.bounds.height * 0.16)
        return (0..<7).map { step in
            let t = CGFloat(step) / 6
            let x = right + (left - right) * t
            let arch = sin(t * .pi)
            return CGPoint(x: x, y: top - lift * (0.55 + 0.45 * arch))
        }
    }

    private static func neckFade(in face: MappedFace, chin: CGPoint) -> [CGPoint] {
        let drop = max(0.03, face.bounds.height * 0.12)
        let half = max(0.04, face.bounds.width * 0.28)
        return (0..<5).map { step in
            let t = CGFloat(step) / 4
            return CGPoint(x: chin.x - half + half * 2 * t, y: chin.y + drop * (0.6 + 0.4 * abs(t - 0.5)))
        }
    }

    private static func measurements(of face: MappedFace, jaw: [FaceHandle: CGPoint]) -> FaceRest {
        let eyeOpening = averageSpan(face.sample(.leftEye)?.points, face.sample(.rightEye)?.points)
        let mouth = face.sample(.innerLips)?.points ?? face.sample(.outerLips)?.points ?? []
        let mouthOpening = verticalSpan(mouth)
        let mouthWidth = horizontalSpan(mouth)
        let faceHeight = max(0.05, face.bounds.height)
        let turn = abs(face.yaw) > 0.08 ? face.yaw : estimatedTurn(of: face)
        return FaceRest(
            eyeOpening: eyeOpening / faceHeight,
            mouthOpening: mouthOpening / faceHeight,
            mouthWidth: mouthWidth / max(0.05, face.bounds.width),
            faceHeight: faceHeight,
            tilt: face.roll,
            turn: turn
        )
    }

    private static func estimatedTurn(of face: MappedFace) -> Double {
        guard let left = face.sample(.leftEye), let right = face.sample(.rightEye) else { return face.yaw }
        let mid = (centroid(left.points).x + centroid(right.points).x) / 2
        let nose = noseTip(in: face)?.x ?? mid
        let width = max(0.05, face.bounds.width)
        return Double((nose - mid) / width) * 0.9
    }

    private static func fan(centerIndex: Int, ringStart: Int, ringCount: Int, vertices: [CGPoint]) -> [FaceTriangle] {
        guard ringCount >= 3 else { return [] }
        let center = vertices[centerIndex]
        let order = (0..<ringCount).sorted { lhs, rhs in
            angle(vertices[ringStart + lhs], from: center) < angle(vertices[ringStart + rhs], from: center)
        }
        var triangles: [FaceTriangle] = []
        for index in order.indices {
            let a = ringStart + order[index]
            let b = ringStart + order[(index + 1) % order.count]
            triangles.append(FaceTriangle(a: centerIndex, b: a, c: b, layer: .skin))
        }
        return triangles
    }

    private static func insertInterior(into triangles: inout [FaceTriangle], vertices: [CGPoint], ringStart: Int) {
        for index in 0..<ringStart {
            guard let hit = triangles.firstIndex(where: { contains($0, point: vertices[index], vertices: vertices) }) else { continue }
            let triangle = triangles.remove(at: hit)
            triangles.append(FaceTriangle(a: index, b: triangle.b, c: triangle.c, layer: .skin))
            triangles.append(FaceTriangle(a: triangle.a, b: index, c: triangle.c, layer: .skin))
            triangles.append(FaceTriangle(a: triangle.a, b: triangle.b, c: index, layer: .skin))
        }
    }

    /// Guarantees the eye, mouth, brow and jaw layers even when a split misses.
    private static func appendRegionTriangles(
        _ triangles: inout [FaceTriangle],
        handleIndex: [FaceHandle: Int]
    ) {
        func add(_ handles: [FaceHandle], _ layer: FaceLayer) {
            let indices = handles.compactMap { handleIndex[$0] }
            guard indices.count >= 3 else { return }
            triangles.append(FaceTriangle(a: indices[0], b: indices[1], c: indices[2], layer: layer))
        }
        add([.leftEyeOuter, .leftEyeCenter, .leftEyeInner], .eye)
        add([.rightEyeOuter, .rightEyeCenter, .rightEyeInner], .eye)
        add([.leftBrowTail, .leftBrowCenter, .rightBrowCenter], .brow)
        add([.mouthLeft, .upperLip, .mouthRight], .mouth)
        add([.mouthLeft, .lowerLip, .mouthRight], .mouth)
        add([.leftJaw, .chin, .rightJaw], .jaw)
    }

    private static func tag(
        _ triangles: inout [FaceTriangle],
        vertices: [CGPoint],
        ringStart: Int,
        ringCount: Int,
        face: MappedFace
    ) {
        let ringEnd = ringStart + ringCount
        for index in triangles.indices {
            let triangle = triangles[index]
            let onRing = [triangle.a, triangle.b, triangle.c].filter { $0 >= ringStart && $0 < ringEnd }.count
            if onRing >= 2 {
                triangles[index].layer = .edge
                continue
            }
            let mid = centroid([vertices[triangle.a], vertices[triangle.b], vertices[triangle.c]])
            triangles[index].layer = layer(nearest: mid, face: face)
        }
    }

    private static func layer(nearest point: CGPoint, face: MappedFace) -> FaceLayer {
        let eyes = (face.sample(.leftEye)?.points ?? []) + (face.sample(.rightEye)?.points ?? [])
        let brows = (face.sample(.leftEyebrow)?.points ?? []) + (face.sample(.rightEyebrow)?.points ?? [])
        let mouth = face.sample(.outerLips)?.points ?? []
        let jaw = face.sample(.faceContour)?.points ?? []
        let pairs: [(FaceLayer, [CGPoint])] = [(.eye, eyes), (.brow, brows), (.mouth, mouth), (.jaw, jaw)]
        var best = FaceLayer.skin
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (layer, points) in pairs {
            guard let nearest = points.map({ hypot($0.x - point.x, $0.y - point.y) }).min() else { continue }
            if nearest < bestDistance {
                bestDistance = nearest
                best = layer
            }
        }
        return best
    }

    private static func contains(_ triangle: FaceTriangle, point: CGPoint, vertices: [CGPoint]) -> Bool {
        let a = vertices[triangle.a]
        let b = vertices[triangle.b]
        let c = vertices[triangle.c]
        let area = cross(a, b, c)
        guard abs(area) > 1e-8 else { return false }
        let u = cross(point, b, c) / area
        let v = cross(a, point, c) / area
        let w = cross(a, b, point) / area
        return u >= -0.001 && v >= -0.001 && w >= -0.001
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private static func angle(_ point: CGPoint, from center: CGPoint) -> CGFloat {
        atan2(point.y - center.y, point.x - center.x)
    }

    private static func offsetOutward(_ point: CGPoint, from center: CGPoint, reach: CGFloat) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let length = max(0.0001, hypot(dx, dy))
        return CGPoint(x: point.x + dx / length * reach, y: point.y + dy / length * reach)
    }

    static func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private static func extreme(_ points: [CGPoint], largestX: Bool) -> CGPoint {
        points.max { largestX ? $0.x < $1.x : $0.x > $1.x } ?? centroid(points)
    }

    private static func verticalSpan(_ points: [CGPoint]) -> CGFloat {
        guard let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return 0 }
        return maxY - minY
    }

    private static func horizontalSpan(_ points: [CGPoint]) -> CGFloat {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max() else { return 0 }
        return maxX - minX
    }

    private static func averageSpan(_ left: [CGPoint]?, _ right: [CGPoint]?) -> CGFloat {
        let spans = [left, right].compactMap { $0 }.map(verticalSpan)
        guard !spans.isEmpty else { return 0 }
        return spans.reduce(0, +) / CGFloat(spans.count)
    }
}
