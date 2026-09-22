import Foundation

/// Runs `operation` and gives up on it after `timeout`.
///
/// Returns `nil` when time runs out first. The abandoned work is cancelled,
/// so an operation that waits on a stream or a sleep stops promptly.
nonisolated func withTimeout<T: Sendable>(
    _ timeout: Duration,
    _ operation: @escaping @Sendable () async -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
