import CoreGraphics
import Foundation

/// One frame of the living still: the photo's mesh after the live face has been added.
///
/// Handles never move pixels themselves. This is the mesh the renderer draws.
nonisolated struct StillDrive: Equatable, Sendable {
    var vertices: [CGPoint]
    var leftLid: Float
    var rightLid: Float
    var jawOpen: Float
    var showTeeth: Bool

    static let empty = StillDrive(vertices: [], leftLid: 0, rightLid: 0, jawOpen: 0, showTeeth: false)
}

/// Turns a live reading into a mesh on top of the photo's own rest face.
///
/// The photo's smile stays in the mesh. Only the difference between the live
/// face and the live rest is added, scaled by strength, and kept inside the
/// photo: lids cannot invert, and the jaw cannot pass the soft edge.
nonisolated enum StillRetarget {
    /// The page's draw rate. Heat never changes this.
    static let drawRate: Double = 30

    /// Renderer budget per frame. Detail drops before this clock does.
    static let maxFrameMilliseconds: Double = 8

    /// Hard cap for one slot's working picture.
    static let bytesPerSlot = 6 * 1024 * 1024

    /// Longest side of the working picture.
    static let maxLongSide = 768

    /// The page clock does not follow the phone's heat. Tracking does.
    static let followsHeat = false

    /// `live` minus `rest`, scaled by strength, added to the photo mesh.
    ///
    /// Pass a pose that is already the difference with `rest` left neutral.
    /// Pass both when the caller still has the two baselines.
    static func drive(
        rig: FaceRig,
        live: FacePose,
        rest: FacePose = .neutral,
        strength: Double,
        headPosePresent: Bool
    ) -> StillDrive {
        let restMesh = rig.deformedVertices()
        let amount = min(1, max(0, strength))
        guard amount > 0, !restMesh.isEmpty else {
            return StillDrive(vertices: restMesh, leftLid: 0, rightLid: 0, jawOpen: 0, showTeeth: false)
        }

        let delta = live.calibrated(against: rest)
        var scaled = delta
        for channel in FaceChannel.allCases {
            scaled[channel] = delta[channel] * Float(amount)
        }

        let height = max(0.05, rig.rest.faceHeight)
        let mouthScale = rig.isLowConfidence(.mouthLeft) ? 0.35 : 1.0
        var targets = handleOffsets(pose: scaled, height: height, mouthScale: mouthScale, rig: rig, rest: restMesh)
        clampJaw(&targets, rig: rig, rest: restMesh)

        var moved = propagate(targets, through: restMesh, rig: rig, height: height)
        applyLids(&moved, pose: scaled, rig: rig, rest: restMesh)
        applyIris(&moved, pose: scaled, rig: rig, rest: restMesh, height: height)
        pin(targets, onto: &moved, rest: restMesh)
        preserveShape(&moved, rest: restMesh, rig: rig)
        pin(targets, onto: &moved, rest: restMesh)

        if headPosePresent {
            applyParallax(&moved, pose: scaled, rig: rig, height: height)
        }

        let jaw = min(1, max(0, Double(scaled[.jawOpen]) * (1 - 0.45 * Double(scaled[.mouthClose]))))
        return StillDrive(
            vertices: moved,
            leftLid: lid(scaled, blink: .eyeBlinkLeft, squint: .eyeSquintLeft, wide: .eyeWideLeft),
            rightLid: lid(scaled, blink: .eyeBlinkRight, squint: .eyeSquintRight, wide: .eyeWideRight),
            jawOpen: Float(jaw),
            showTeeth: rig.teethVisible && jaw > 0.04
        )
    }

    /// Straight blend. `amount` 0 returns `start`, 1 returns `end`.
    static func blended(_ start: StillDrive, _ end: StillDrive, amount: Double) -> StillDrive {
        let t = min(1, max(0, amount))
        guard start.vertices.count == end.vertices.count, !start.vertices.isEmpty else {
            return t < 0.5 ? start : end
        }
        let vertices = zip(start.vertices, end.vertices).map { left, right in
            CGPoint(x: left.x + (right.x - left.x) * t, y: left.y + (right.y - left.y) * t)
        }
        return StillDrive(
            vertices: vertices,
            leftLid: mix(start.leftLid, end.leftLid, Float(t)),
            rightLid: mix(start.rightLid, end.rightLid, Float(t)),
            jawOpen: mix(start.jawOpen, end.jawOpen, Float(t)),
            showTeeth: t < 0.5 ? start.showTeeth : end.showTeeth
        )
    }

    /// True when the drive would not move the photo.
    static func isIdentity(_ drive: StillDrive, rest: [CGPoint]) -> Bool {
        guard drive.vertices.count == rest.count else { return false }
        guard drive.leftLid < 0.01, drive.rightLid < 0.01, drive.jawOpen < 0.01 else { return false }
        for (moved, original) in zip(drive.vertices, rest) {
            if hypot(moved.x - original.x, moved.y - original.y) > 0.0008 { return false }
        }
        return true
    }

    /// The chin may not pass this line. It sits just inside the soft edge.
    static func jawLimit(in rig: FaceRig) -> CGFloat {
        let chin = rig.position(of: .chin) ?? rig.vertices.max { $0.y < $1.y } ?? .zero
        var floor = chin.y + CGFloat(rig.rest.faceHeight) * 0.08
        for triangle in rig.triangles where triangle.layer == .edge {
            for index in [triangle.a, triangle.b, triangle.c] where rig.vertices.indices.contains(index) {
                floor = max(floor, rig.vertices[index].y)
            }
        }
        return floor - 0.01
    }

    /// The lower lid line. An upper lid is not allowed past it.
    static func lowerLidY(rig: FaceRig, eye: FaceHandle) -> CGFloat {
        guard let center = rig.position(of: eye) else { return 1 }
        let opening = CGFloat(max(0.01, rig.rest.eyeOpening * rig.rest.faceHeight))
        return center.y + opening * 0.45
    }

    /// Working picture size: longest side capped, and the byte budget held.
    static func workingSize(for pixelSize: CGSize, longSide: Int = maxLongSide) -> CGSize {
        let width = max(1, pixelSize.width)
        let height = max(1, pixelSize.height)
        let cap = max(64, longSide)
        var scale = min(1, Double(cap) / Double(max(width, height)))
        var outWidth = max(1, (width * scale).rounded())
        var outHeight = max(1, (height * scale).rounded())
        while Int(outWidth * outHeight * 4) > bytesPerSlot, scale > 0.05 {
            scale *= 0.75
            outWidth = max(1, (width * scale).rounded())
            outHeight = max(1, (height * scale).rounded())
        }
        return CGSize(width: outWidth, height: outHeight)
    }

    // MARK: - Expression

    private static func handleOffsets(
        pose: FacePose,
        height: Double,
        mouthScale: Double,
        rig: FaceRig,
        rest: [CGPoint]
    ) -> [Int: CGPoint] {
        var offsets: [Int: CGPoint] = [:]
        func put(_ handle: FaceHandle, _ dx: Double, _ dy: Double) {
            guard let index = rig.handleIndex[handle] else { return }
            offsets[index] = CGPoint(x: dx * height, y: dy * height)
        }
        func add(_ handle: FaceHandle, _ dx: Double, _ dy: Double) {
            guard let index = rig.handleIndex[handle] else { return }
            let current = offsets[index] ?? .zero
            offsets[index] = CGPoint(x: current.x + dx * height, y: current.y + dy * height)
        }

        let smileL = value(pose, .mouthSmileLeft) * mouthScale
        let smileR = value(pose, .mouthSmileRight) * mouthScale
        let frownL = value(pose, .mouthFrownLeft) * mouthScale
        let frownR = value(pose, .mouthFrownRight) * mouthScale
        let stretchL = value(pose, .mouthStretchLeft) * mouthScale
        let stretchR = value(pose, .mouthStretchRight) * mouthScale
        let pucker = value(pose, .mouthPucker) * mouthScale
        let funnel = value(pose, .mouthFunnel) * mouthScale
        let jaw = value(pose, .jawOpen) * (1 - 0.45 * value(pose, .mouthClose)) * mouthScale
        let jawSide = (value(pose, .jawLeft) - value(pose, .jawRight)) * 0.04 * mouthScale
        let puff = value(pose, .cheekPuff)

        put(.mouthLeft, 0.045 * smileL + 0.03 * stretchL - 0.035 * pucker, -0.07 * smileL + 0.045 * frownL)
        put(.mouthRight, -0.045 * smileR - 0.03 * stretchR + 0.035 * pucker, -0.07 * smileR + 0.045 * frownR)
        put(.upperLip, 0, -0.02 * (smileL + smileR) / 2 + 0.025 * funnel)
        put(.lowerLip, jawSide * 0.35, jaw * 0.11 + 0.02 * funnel)
        put(.chin, jawSide, jaw * 0.16)
        add(.leftJaw, puff * 0.03 + jawSide * 0.4, jaw * 0.04)
        add(.rightJaw, -puff * 0.03 + jawSide * 0.4, jaw * 0.04)

        put(.leftBrowCenter, 0, value(pose, .browDownLeft) * 0.045 - value(pose, .browInnerUp) * 0.04 - value(pose, .browOuterUpLeft) * 0.01)
        put(.leftBrowTail, 0, value(pose, .browDownLeft) * 0.02 - value(pose, .browOuterUpLeft) * 0.045)
        put(.rightBrowCenter, 0, value(pose, .browDownRight) * 0.045 - value(pose, .browInnerUp) * 0.04 - value(pose, .browOuterUpRight) * 0.01)
        put(.rightBrowTail, 0, value(pose, .browDownRight) * 0.02 - value(pose, .browOuterUpRight) * 0.045)

        _ = rest
        return offsets.filter { $0.value.x != 0 || $0.value.y != 0 }
    }

    private static func propagate(
        _ offsets: [Int: CGPoint],
        through rest: [CGPoint],
        rig: FaceRig,
        height: Double
    ) -> [CGPoint] {
        guard !offsets.isEmpty else { return rest }
        let sigma = max(0.03, height * 0.18)
        let layers = vertexLayers(rig)
        var moved = rest
        for index in moved.indices {
            if isSoftEdge(index, rig: rig) || isGlassesFrame(index, rest: rest, rig: rig) { continue }
            var dx = 0.0
            var dy = 0.0
            var weightSum = 0.0
            var weightMax = 0.0
            for (anchorIndex, offset) in offsets {
                let anchor = rest[anchorIndex]
                let point = rest[index]
                let distanceX = point.x - anchor.x
                let distanceY = point.y - anchor.y
                var weight = exp(-(distanceX * distanceX + distanceY * distanceY) / (2 * sigma * sigma))
                if layers[index] == layers[anchorIndex] { weight *= 1.6 }
                dx += offset.x * weight
                dy += offset.y * weight
                weightSum += weight
                weightMax = max(weightMax, weight)
            }
            guard weightSum > 0, weightMax > 0.02 else { continue }
            moved[index].x += dx / weightSum * weightMax
            moved[index].y += dy / weightSum * weightMax
        }
        return moved
    }

    private static func applyLids(_ moved: inout [CGPoint], pose: FacePose, rig: FaceRig, rest: [CGPoint]) {
        guard !rig.wearsGlasses else { return }
        close(&moved, pose: pose, rig: rig, rest: rest, center: .leftEyeCenter, blink: .eyeBlinkLeft, squint: .eyeSquintLeft)
        close(&moved, pose: pose, rig: rig, rest: rest, center: .rightEyeCenter, blink: .eyeBlinkRight, squint: .eyeSquintRight)
    }

    private static func close(
        _ moved: inout [CGPoint],
        pose: FacePose,
        rig: FaceRig,
        rest: [CGPoint],
        center: FaceHandle,
        blink: FaceChannel,
        squint: FaceChannel
    ) {
        guard let index = rig.handleIndex[center], rest.indices.contains(index) else { return }
        let opening = CGFloat(max(0.01, rig.rest.eyeOpening * rig.rest.faceHeight))
        let amount = min(1, value(pose, blink) + 0.35 * value(pose, squint))
        let drop = opening * 0.9 * amount
        let lower = rest[index].y + opening * 0.45
        let proposed = rest[index].y + drop * 0.55
        moved[index].y = min(moved[index].y + (proposed - rest[index].y), lower - 0.001)
    }

    private static func applyIris(
        _ moved: inout [CGPoint],
        pose: FacePose,
        rig: FaceRig,
        rest: [CGPoint],
        height: Double
    ) {
        slide(&moved, pose: pose, rig: rig, rest: rest, height: height, center: .leftEyeCenter, inner: .leftEyeInner, outer: .leftEyeOuter, yaw: .leftEyeYaw, pitch: .leftEyePitch, lookOut: .eyeLookOutLeft, lookIn: .eyeLookInLeft, lookDown: .eyeLookDownLeft, lookUp: .eyeLookUpLeft)
        slide(&moved, pose: pose, rig: rig, rest: rest, height: height, center: .rightEyeCenter, inner: .rightEyeInner, outer: .rightEyeOuter, yaw: .rightEyeYaw, pitch: .rightEyePitch, lookOut: .eyeLookOutRight, lookIn: .eyeLookInRight, lookDown: .eyeLookDownRight, lookUp: .eyeLookUpRight)
    }

    private static func slide(
        _ moved: inout [CGPoint],
        pose: FacePose,
        rig: FaceRig,
        rest: [CGPoint],
        height: Double,
        center: FaceHandle,
        inner: FaceHandle,
        outer: FaceHandle,
        yaw: FaceChannel,
        pitch: FaceChannel,
        lookOut: FaceChannel,
        lookIn: FaceChannel,
        lookDown: FaceChannel,
        lookUp: FaceChannel
    ) {
        guard let index = rig.handleIndex[center],
              let innerPoint = rig.position(of: inner),
              let outerPoint = rig.position(of: outer),
              rest.indices.contains(index) else { return }
        let eyeWidth = max(0.02, abs(outerPoint.x - innerPoint.x))
        let yawSlide = value(pose, yaw) + value(pose, lookOut) * 0.35 - value(pose, lookIn) * 0.35
        let pitchSlide = value(pose, pitch) + value(pose, lookDown) * 0.25 - value(pose, lookUp) * 0.25
        let limit = eyeWidth * 0.22
        let dx = CGFloat(max(-limit, min(limit, yawSlide * height * 0.12)))
        let dy = CGFloat(max(-limit, min(limit, pitchSlide * height * 0.08)))
        let minX = min(innerPoint.x, outerPoint.x) + eyeWidth * 0.18
        let maxX = max(innerPoint.x, outerPoint.x) - eyeWidth * 0.18
        moved[index].x = min(maxX, max(minX, moved[index].x + dx))
        moved[index].y += dy
    }

    private static func clampJaw(_ offsets: inout [Int: CGPoint], rig: FaceRig, rest: [CGPoint]) {
        guard let index = rig.handleIndex[.chin], rest.indices.contains(index) else { return }
        let limit = jawLimit(in: rig)
        let proposed = rest[index].y + (offsets[index]?.y ?? 0)
        guard proposed > limit else { return }
        let overflow = proposed - limit
        offsets[index] = CGPoint(x: offsets[index]?.x ?? 0, y: (offsets[index]?.y ?? 0) - overflow)
        if let lip = rig.handleIndex[.lowerLip] {
            let current = offsets[lip] ?? .zero
            offsets[lip] = CGPoint(x: current.x, y: min(current.y, (offsets[index]?.y ?? 0) * 0.72))
        }
    }

    private static func pin(_ offsets: [Int: CGPoint], onto moved: inout [CGPoint], rest: [CGPoint]) {
        for (index, offset) in offsets where moved.indices.contains(index) && rest.indices.contains(index) {
            moved[index] = CGPoint(x: rest[index].x + offset.x, y: rest[index].y + offset.y)
        }
    }

    /// One rigid pass so a triangle keeps its shape instead of shearing.
    private static func preserveShape(_ moved: inout [CGPoint], rest: [CGPoint], rig: FaceRig) {
        var pull = Array(repeating: CGPoint.zero, count: moved.count)
        var count = Array(repeating: 0, count: moved.count)
        for triangle in rig.triangles where triangle.layer != .edge {
            let indices = [triangle.a, triangle.b, triangle.c]
            guard indices.allSatisfy({ rest.indices.contains($0) }) else { continue }
            let restCenter = centroid(indices.map { rest[$0] })
            let movedCenter = centroid(indices.map { moved[$0] })
            for index in indices {
                let original = CGPoint(x: rest[index].x - restCenter.x, y: rest[index].y - restCenter.y)
                let current = CGPoint(x: moved[index].x - movedCenter.x, y: moved[index].y - movedCenter.y)
                let blended = CGPoint(
                    x: current.x * 0.4 + original.x * 0.6,
                    y: current.y * 0.4 + original.y * 0.6
                )
                pull[index].x += movedCenter.x + blended.x
                pull[index].y += movedCenter.y + blended.y
                count[index] += 1
            }
        }
        for index in moved.indices where count[index] > 0 && rig.handleIndex.values.contains(index) == false {
            let weight = 0.45
            let average = CGPoint(x: pull[index].x / CGFloat(count[index]), y: pull[index].y / CGFloat(count[index]))
            moved[index].x = moved[index].x * (1 - weight) + average.x * weight
            moved[index].y = moved[index].y * (1 - weight) + average.y * weight
        }
    }

    private static func applyParallax(_ moved: inout [CGPoint], pose: FacePose, rig: FaceRig, height: Double) {
        let gain = FaceRig.headTurnGain(turnRadians: rig.rest.turn)
        let yaw = value(pose, .headYaw) * gain
        let pitch = value(pose, .headPitch) * gain
        let roll = value(pose, .headRoll) * gain * 0.35
        guard abs(yaw) + abs(pitch) + abs(roll) > 0.0001 else { return }
        let center = centroid(FaceHandle.allCases.compactMap { rig.position(of: $0) })
        let layers = vertexLayers(rig)
        let handles = handleDepths(rig)
        for index in moved.indices {
            let depth = handles[index] ?? depth(of: layers[index])
            let dx = moved[index].x - center.x
            let dy = moved[index].y - center.y
            moved[index].x += yaw * depth * height * 0.28 - dy * roll * depth * 0.15
            moved[index].y += pitch * depth * height * 0.18 + dx * roll * depth * 0.15
        }
    }

    // MARK: - Small helpers

    private static func lid(_ pose: FacePose, blink: FaceChannel, squint: FaceChannel, wide: FaceChannel) -> Float {
        let closed = value(pose, blink) + 0.35 * value(pose, squint) - 0.45 * value(pose, wide)
        return Float(min(1, max(0, closed)))
    }

    private static func value(_ pose: FacePose, _ channel: FaceChannel) -> Double {
        Double(pose[channel])
    }

    private static func mix(_ left: Float, _ right: Float, _ amount: Float) -> Float {
        left + (right - left) * amount
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private static func vertexLayers(_ rig: FaceRig) -> [FaceLayer] {
        var layers = Array(repeating: FaceLayer.skin, count: rig.vertices.count)
        for triangle in rig.triangles {
            for index in [triangle.a, triangle.b, triangle.c] where layers.indices.contains(index) {
                if layers[index] == .skin || triangle.layer == .edge {
                    layers[index] = triangle.layer
                }
            }
        }
        return layers
    }

    private static func isSoftEdge(_ index: Int, rig: FaceRig) -> Bool {
        let touching = rig.triangles.filter { $0.a == index || $0.b == index || $0.c == index }
        guard !touching.isEmpty else { return false }
        return touching.allSatisfy { $0.layer == .edge }
    }

    /// The frame around the eye, not the pupil. Glasses do not follow the blink.
    private static func isGlassesFrame(_ index: Int, rest: [CGPoint], rig: FaceRig) -> Bool {
        guard rig.wearsGlasses, rest.indices.contains(index) else { return false }
        if rig.handleIndex[.leftEyeCenter] == index || rig.handleIndex[.rightEyeCenter] == index { return false }
        let point = rest[index]
        for center in [FaceHandle.leftEyeCenter, .rightEyeCenter] {
            guard let eye = rig.position(of: center) else { continue }
            let width = eyeWidth(center, rig: rig)
            let distance = hypot(point.x - eye.x, point.y - eye.y)
            if distance > width * 0.22 && distance < width * 0.9 { return true }
        }
        return false
    }

    private static func eyeWidth(_ center: FaceHandle, rig: FaceRig) -> CGFloat {
        switch center {
        case .leftEyeCenter:
            guard let inner = rig.position(of: .leftEyeInner), let outer = rig.position(of: .leftEyeOuter) else { return 0.06 }
            return max(0.03, abs(outer.x - inner.x))
        default:
            guard let inner = rig.position(of: .rightEyeInner), let outer = rig.position(of: .rightEyeOuter) else { return 0.06 }
            return max(0.03, abs(outer.x - inner.x))
        }
    }

    private static func handleDepths(_ rig: FaceRig) -> [Int: Double] {
        var depths: [Int: Double] = [:]
        func set(_ handle: FaceHandle, _ depth: Double) {
            if let index = rig.handleIndex[handle] { depths[index] = depth }
        }
        set(.noseTip, 1)
        set(.leftEyeCenter, 0.95)
        set(.rightEyeCenter, 0.95)
        set(.leftEyeOuter, 0.8)
        set(.leftEyeInner, 0.8)
        set(.rightEyeOuter, 0.8)
        set(.rightEyeInner, 0.8)
        set(.leftBrowCenter, 0.7)
        set(.leftBrowTail, 0.7)
        set(.rightBrowCenter, 0.7)
        set(.rightBrowTail, 0.7)
        set(.upperLip, 0.45)
        set(.lowerLip, 0.4)
        set(.mouthLeft, 0.4)
        set(.mouthRight, 0.4)
        set(.chin, 0.22)
        set(.leftJaw, 0.22)
        set(.rightJaw, 0.22)
        return depths
    }

    private static func depth(of layer: FaceLayer) -> Double {
        switch layer {
        case .eye, .brow: 0.85
        case .mouth: 0.42
        case .jaw: 0.22
        case .edge: 0.06
        case .skin: 0.55
        }
    }
}
