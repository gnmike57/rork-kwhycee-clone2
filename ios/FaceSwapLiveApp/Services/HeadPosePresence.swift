import Foundation

/// Whether a Live Link Face sender is actually streaming head angles.
///
/// Stream Head Rotation off sends exact zeros. A face looking straight ahead
/// on this phone's own camera is not that case — this latch is only fed in
/// link mode, and it stays on once any head angle has been non-zero.
nonisolated struct HeadPosePresence: Sendable, Equatable {
    private(set) var hasSeenHeadPose = false

    mutating func observe(_ pose: FacePose) {
        guard !hasSeenHeadPose else { return }
        if FaceChannel.headChannels.contains(where: { pose[$0] != 0 }) {
            hasSeenHeadPose = true
        }
    }

    mutating func reset() {
        hasSeenHeadPose = false
    }

    var isExpressionOnly: Bool { !hasSeenHeadPose }
}
