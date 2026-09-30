import Foundation

/// A snapshot of how Live Link Face packets are arriving.
///
/// Loss is estimated from arrival gaps against the typical interval, since the
/// packets carry no sequence numbers. This is a signal for the sheet, not a
/// measurement the page ever sees.
nonisolated struct PacketHealth: Equatable, Sendable {
    /// Packets accepted in the last few seconds.
    var packetCount: Int = 0
    /// Accepted packets per second over the recent window.
    var ratePerSecond: Double = 0
    /// 0…1 estimated share of sent packets that never arrived.
    var lostFraction: Double = 0
    /// Mean wander of arrival gaps around their typical gap, in seconds.
    var jitterSeconds: Double = 0
    /// Seconds since the last packet; infinity when none has arrived yet.
    var secondsSinceLastPacket: Double = .infinity

    static let empty = PacketHealth()
}

/// Turns arrival times into a `PacketHealth`, with no clock or socket of its
/// own: the caller passes each arrival, so tests can feed synthetic gaps.
nonisolated struct PacketHealthTracker {
    /// How far back arrivals are remembered.
    private static let window: TimeInterval = 4
    /// How many recent gaps feed the median and jitter.
    private static let maxGaps = 120
    /// A long stall must not count as hundreds of losses in one step.
    private static let maxMissedPerGap = 30
    /// Smallest span the rate divides by, so the first second reads sanely.
    private static let minimumRateSpan: TimeInterval = 1

    private var arrivals: [TimeInterval] = []
    private var gaps: [TimeInterval] = []
    private var missedByArrival: [Int] = []

    /// Records one accepted packet at the given time.
    mutating func record(at now: TimeInterval) {
        if let last = arrivals.last {
            guard now > last else { return }
            let gap = now - last
            gaps.append(gap)
            if gaps.count > Self.maxGaps { gaps.removeFirst(gaps.count - Self.maxGaps) }
            var missed = 0
            if let typical = Self.median(gaps), typical > 0 {
                let estimate = (gap / typical).rounded() - 1
                if estimate > 0 { missed = min(Int(estimate), Self.maxMissedPerGap) }
            }
            missedByArrival.append(missed)
        }
        arrivals.append(now)
        arrivals.removeAll { $0 < now - Self.window }
        missedByArrival.removeFirst(max(0, missedByArrival.count - arrivals.count))
    }

    /// Forgets everything, as a source restart should.
    mutating func reset() {
        arrivals.removeAll()
        gaps.removeAll()
        missedByArrival.removeAll()
    }

    /// The health as of `now`, which keeps the last-seen age moving between
    /// packets.
    func snapshot(at now: TimeInterval) -> PacketHealth {
        guard let first = arrivals.first else { return .empty }
        let missedTotal = missedByArrival.reduce(0, +)
        let accepted = arrivals.count
        let span = max(Self.minimumRateSpan, min(Self.window, now - first))
        let jitter: Double
        if let typical = Self.median(gaps), !gaps.isEmpty {
            let wander = gaps.reduce(0.0) { $0 + abs($1 - typical) }
            jitter = wander / Double(gaps.count)
        } else {
            jitter = 0
        }
        let sent = accepted + missedTotal
        return PacketHealth(
            packetCount: accepted,
            ratePerSecond: Double(accepted) / span,
            lostFraction: sent > 0 ? Double(missedTotal) / Double(sent) : 0,
            jitterSeconds: jitter,
            secondsSinceLastPacket: max(0, now - arrivals.last!)
        )
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
