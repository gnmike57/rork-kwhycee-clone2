import ARKit
import Synchronization
import UIKit

/// Receives ARKit's frames on the session's own queue and turns each one into
/// a `FacePose` before anything crosses to the main actor. Nothing from ARKit
/// is retained past the callback.
nonisolated final class ARKitFaceRelay: NSObject, ARSessionDelegate, Sendable {
    nonisolated private struct State: Sendable {
        var orientation: UIInterfaceOrientation = .portrait
        var hadFace = false
        var announcedSearching = false
    }

    private let state = Mutex(State())
    private let sink: AsyncStream<FaceSourceEvent>.Continuation

    init(sink: AsyncStream<FaceSourceEvent>.Continuation) {
        self.sink = sink
        super.init()
    }

    /// Head angles are measured against the screen's up, so the reading stays
    /// right when the phone is held in landscape.
    func setInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        state.withLock { $0.orientation = orientation }
    }

    /// Forgets the last face so the next run announces its search afresh.
    func sessionRestarted() {
        state.withLock {
            $0.hadFace = false
            $0.announcedSearching = false
        }
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let face = frame.anchors.lazy
            .compactMap { $0 as? ARFaceAnchor }
            .first { $0.isTracked }

        guard let face else {
            let announce = state.withLock { s -> Bool in
                let lostOrFirst = s.hadFace || !s.announcedSearching
                s.hadFace = false
                s.announcedSearching = true
                return lostOrFirst
            }
            if announce { sink.yield(.searching) }
            return
        }

        let orientation = state.withLock { s -> UIInterfaceOrientation in
            s.hadFace = true
            return s.orientation
        }

        let pose = Self.pose(from: face, camera: frame.camera, orientation: orientation)
        sink.yield(.pose(pose, sender: nil))
    }

    func sessionWasInterrupted(_ session: ARSession) {
        sink.yield(.interrupted)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        sessionRestarted()
        sink.yield(.resumed)
    }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        if let arError = error as? ARError, arError.code == .cameraUnauthorized {
            sink.yield(.cameraDenied)
        } else {
            sink.yield(.failed(error.localizedDescription))
        }
    }

    // MARK: - Conversion

    /// Reads the 52 coefficients straight across and derives head and eye
    /// angles from the anchor's rotation relative to the upright camera view,
    /// in the convention `FacePose` documents.
    static func pose(from face: ARFaceAnchor, camera: ARCamera, orientation: UIInterfaceOrientation) -> FacePose {
        var values = [Float](repeating: 0, count: FaceChannel.count)
        let shapes = face.blendShapes
        for channel in FaceChannel.allCases where channel.isExpression {
            guard let location = channel.blendShapeLocation, let number = shapes[location] else { continue }
            values[channel.rawValue] = number.floatValue
        }

        let view = camera.viewMatrix(for: orientation)
        let head = HeadAngles(rotation: view * face.transform)
        values[FaceChannel.headYaw.rawValue] = head.yaw
        values[FaceChannel.headPitch.rawValue] = head.pitch
        values[FaceChannel.headRoll.rawValue] = head.roll

        let leftEye = HeadAngles(rotation: face.leftEyeTransform)
        values[FaceChannel.leftEyeYaw.rawValue] = leftEye.yaw
        values[FaceChannel.leftEyePitch.rawValue] = leftEye.pitch
        values[FaceChannel.leftEyeRoll.rawValue] = leftEye.roll

        let rightEye = HeadAngles(rotation: face.rightEyeTransform)
        values[FaceChannel.rightEyeYaw.rawValue] = rightEye.yaw
        values[FaceChannel.rightEyePitch.rawValue] = rightEye.pitch
        values[FaceChannel.rightEyeRoll.rawValue] = rightEye.roll

        return FacePose(values: values, timestamp: FaceClock.now(), hasFace: true).clamped()
    }

    /// Yaw–pitch–roll of a rotation in Apple's face frame (+x subject's left,
    /// +y up, +z toward the viewer): the nose is the +z column, so yaw is its
    /// swing toward +x, pitch its dip toward −y, and roll the tilt of the +x
    /// column toward +y.
    nonisolated struct HeadAngles: Sendable, Equatable {
        var yaw: Float
        var pitch: Float
        var roll: Float

        init(rotation m: simd_float4x4) {
            let nose = m.columns.2
            let side = m.columns.0
            let up = m.columns.1
            yaw = atan2f(nose.x, nose.z)
            pitch = asinf(min(max(-nose.y, -1), 1))
            roll = atan2f(side.y, up.y)
        }
    }
}

nonisolated extension FaceChannel {
    /// ARKit's key for each expression channel; nil for the angle channels.
    var blendShapeLocation: ARFaceAnchor.BlendShapeLocation? {
        switch self {
        case .eyeBlinkLeft: .eyeBlinkLeft
        case .eyeLookDownLeft: .eyeLookDownLeft
        case .eyeLookInLeft: .eyeLookInLeft
        case .eyeLookOutLeft: .eyeLookOutLeft
        case .eyeLookUpLeft: .eyeLookUpLeft
        case .eyeSquintLeft: .eyeSquintLeft
        case .eyeWideLeft: .eyeWideLeft
        case .eyeBlinkRight: .eyeBlinkRight
        case .eyeLookDownRight: .eyeLookDownRight
        case .eyeLookInRight: .eyeLookInRight
        case .eyeLookOutRight: .eyeLookOutRight
        case .eyeLookUpRight: .eyeLookUpRight
        case .eyeSquintRight: .eyeSquintRight
        case .eyeWideRight: .eyeWideRight
        case .jawForward: .jawForward
        case .jawLeft: .jawLeft
        case .jawRight: .jawRight
        case .jawOpen: .jawOpen
        case .mouthClose: .mouthClose
        case .mouthFunnel: .mouthFunnel
        case .mouthPucker: .mouthPucker
        case .mouthLeft: .mouthLeft
        case .mouthRight: .mouthRight
        case .mouthSmileLeft: .mouthSmileLeft
        case .mouthSmileRight: .mouthSmileRight
        case .mouthFrownLeft: .mouthFrownLeft
        case .mouthFrownRight: .mouthFrownRight
        case .mouthDimpleLeft: .mouthDimpleLeft
        case .mouthDimpleRight: .mouthDimpleRight
        case .mouthStretchLeft: .mouthStretchLeft
        case .mouthStretchRight: .mouthStretchRight
        case .mouthRollLower: .mouthRollLower
        case .mouthRollUpper: .mouthRollUpper
        case .mouthShrugLower: .mouthShrugLower
        case .mouthShrugUpper: .mouthShrugUpper
        case .mouthPressLeft: .mouthPressLeft
        case .mouthPressRight: .mouthPressRight
        case .mouthLowerDownLeft: .mouthLowerDownLeft
        case .mouthLowerDownRight: .mouthLowerDownRight
        case .mouthUpperUpLeft: .mouthUpperUpLeft
        case .mouthUpperUpRight: .mouthUpperUpRight
        case .browDownLeft: .browDownLeft
        case .browDownRight: .browDownRight
        case .browInnerUp: .browInnerUp
        case .browOuterUpLeft: .browOuterUpLeft
        case .browOuterUpRight: .browOuterUpRight
        case .cheekPuff: .cheekPuff
        case .cheekSquintLeft: .cheekSquintLeft
        case .cheekSquintRight: .cheekSquintRight
        case .noseSneerLeft: .noseSneerLeft
        case .noseSneerRight: .noseSneerRight
        case .tongueOut: .tongueOut
        case .headYaw, .headPitch, .headRoll,
             .leftEyeYaw, .leftEyePitch, .leftEyeRoll,
             .rightEyeYaw, .rightEyePitch, .rightEyeRoll:
            nil
        }
    }
}
