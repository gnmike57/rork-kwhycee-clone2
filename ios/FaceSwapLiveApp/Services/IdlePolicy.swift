import Foundation

/// Idle life only starts after a real face has been seen, and Reduce Motion
/// means a true still.
nonisolated enum IdlePolicy {
    static func allowsIdle(hasSeenLiveFace: Bool, reduceMotion: Bool) -> Bool {
        hasSeenLiveFace && !reduceMotion
    }
}
