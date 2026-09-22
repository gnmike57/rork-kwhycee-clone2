import Foundation

/// Turns readings that arrive whenever they arrive (up to 60/s) into a pose
/// for any instant, by interpolating between the two neighbouring readings.
/// The 30 fps draw asks for a pose a frame behind real time so there is
/// almost always a reading on both sides.
nonisolated struct PoseResampler: Sendable, Equatable {
    /// Readings older than this behind the newest are dropped.
    static let window: TimeInterval = 0.5

    /// Hard cap so a burst can never grow the buffer.
    static let capacity = 32

    private var samples: [FacePose] = []

    /// The newest reading, if any.
    var latest: FacePose? { samples.last }

    var isEmpty: Bool { samples.isEmpty }

    /// Adds a reading. Anything not newer than the last is ignored.
    mutating func add(_ pose: FacePose) {
        if let last = samples.last, pose.timestamp <= last.timestamp { return }
        samples.append(pose)
        let cutoff = pose.timestamp - Self.window
        samples.removeAll { $0.timestamp < cutoff }
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }

    /// The pose at `time`: interpolated between neighbours, held at either
    /// end, nil when nothing has arrived.
    func sample(at time: TimeInterval) -> FacePose? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if time <= first.timestamp { return first }
        if time >= last.timestamp { return last }

        var lower = first
        for upper in samples.dropFirst() {
            if upper.timestamp >= time {
                let span = upper.timestamp - lower.timestamp
                guard span > 0 else { return upper }
                let amount = Float((time - lower.timestamp) / span)
                return lower.mixed(with: upper, amount: amount)
            }
            lower = upper
        }
        return last
    }

    mutating func reset() {
        samples.removeAll()
    }
}
