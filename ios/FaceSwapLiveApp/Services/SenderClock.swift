import Foundation

/// Maps a sender's own frame time onto this phone's monotonic clock.
///
/// The first good frame time sets the offset. A jump that cannot be a network
/// delay re-anchors, so a sender restart does not freeze the still in the past.
nonisolated struct SenderClock: Sendable, Equatable {
    private var offset: TimeInterval?

    mutating func localTime(qualified: TimeInterval?, receivedAt: TimeInterval) -> TimeInterval {
        guard let qualified, qualified.isFinite else { return receivedAt }
        if offset == nil {
            offset = receivedAt - qualified
        }
        let mapped = qualified + (offset ?? 0)
        if mapped > receivedAt + 0.5 || mapped < receivedAt - 2 {
            offset = receivedAt - qualified
            return receivedAt
        }
        return mapped
    }

    mutating func reset() {
        offset = nil
    }
}
