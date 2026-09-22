import Foundation

/// The 61 values a face reading carries, in the order Live Link Face packs
/// them: Apple's 52 expression coefficients, then head and eye rotation.
///
/// Both sources fill the same channels, so everything downstream reads one
/// layout whether the face came from this phone's camera or a second iPhone.
nonisolated enum FaceChannel: Int, CaseIterable, Sendable, Codable {
    case eyeBlinkLeft = 0
    case eyeLookDownLeft
    case eyeLookInLeft
    case eyeLookOutLeft
    case eyeLookUpLeft
    case eyeSquintLeft
    case eyeWideLeft
    case eyeBlinkRight
    case eyeLookDownRight
    case eyeLookInRight
    case eyeLookOutRight
    case eyeLookUpRight
    case eyeSquintRight
    case eyeWideRight
    case jawForward
    case jawLeft
    case jawRight
    case jawOpen
    case mouthClose
    case mouthFunnel
    case mouthPucker
    case mouthLeft
    case mouthRight
    case mouthSmileLeft
    case mouthSmileRight
    case mouthFrownLeft
    case mouthFrownRight
    case mouthDimpleLeft
    case mouthDimpleRight
    case mouthStretchLeft
    case mouthStretchRight
    case mouthRollLower
    case mouthRollUpper
    case mouthShrugLower
    case mouthShrugUpper
    case mouthPressLeft
    case mouthPressRight
    case mouthLowerDownLeft
    case mouthLowerDownRight
    case mouthUpperUpLeft
    case mouthUpperUpRight
    case browDownLeft
    case browDownRight
    case browInnerUp
    case browOuterUpLeft
    case browOuterUpRight
    case cheekPuff
    case cheekSquintLeft
    case cheekSquintRight
    case noseSneerLeft
    case noseSneerRight
    case tongueOut
    case headYaw
    case headPitch
    case headRoll
    case leftEyeYaw
    case leftEyePitch
    case leftEyeRoll
    case rightEyeYaw
    case rightEyePitch
    case rightEyeRoll

    /// Every channel, expressions and angles together.
    static let count = 61

    /// The leading run of 0…1 expression coefficients.
    static let expressionCount = 52

    /// The two eyelid channels, which get a snappier filter than the rest.
    static let blinkChannels: Set<FaceChannel> = [.eyeBlinkLeft, .eyeBlinkRight]

    /// Head rotation, in radians.
    static let headChannels: [FaceChannel] = [.headYaw, .headPitch, .headRoll]

    /// Eye rotation relative to the head, in radians.
    static let eyeChannels: [FaceChannel] = [
        .leftEyeYaw, .leftEyePitch, .leftEyeRoll,
        .rightEyeYaw, .rightEyePitch, .rightEyeRoll,
    ]

    /// True for the 52 coefficients, false for the nine rotation angles.
    var isExpression: Bool { rawValue < Self.expressionCount }

    /// True for head and eye rotation.
    var isAngle: Bool { !isExpression }

    /// The name Live Link Face and Apple use for this channel, e.g. `EyeBlinkLeft`.
    var liveLinkName: String {
        let name = String(describing: self)
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
