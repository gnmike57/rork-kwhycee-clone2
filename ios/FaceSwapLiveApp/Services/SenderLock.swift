import Foundation

/// Remembers the first Live Link Face sender and ignores every other phone on
/// the same network. An empty name does not lock and does not count as a
/// different sender.
nonisolated struct SenderLock: Sendable, Equatable {
    private(set) var lockedName: String?

    /// True when the packet may drive the still.
    mutating func accept(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if let lockedName, lockedName != trimmed { return false }
        if lockedName == nil { lockedName = trimmed }
        return true
    }

    mutating func release() {
        lockedName = nil
    }
}
