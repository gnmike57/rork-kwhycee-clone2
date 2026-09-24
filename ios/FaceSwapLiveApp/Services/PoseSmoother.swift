import Foundation

/// One 1€ filter per channel, tuned so the eyelids stay snappy while the
/// slower channels lose their jitter.
///
/// Feed it every reading in order; reset it whenever the face is lost so the
/// next reading starts clean instead of dragging in from stale history.
nonisolated struct PoseSmoother: Sendable {
    private var filters: [OneEuroFilter]

    init() {
        filters = FaceChannel.allCases.map { Self.filter(for: $0) }
    }

    /// The smoothed reading; timestamp and face flag pass through.
    mutating func smooth(_ pose: FacePose) -> FacePose {
        var values = [Float](repeating: 0, count: FaceChannel.count)
        for index in 0..<FaceChannel.count {
            let raw = Double(pose.values[index])
            let channel = FaceChannel(rawValue: index)
            if let channel, FaceChannel.blinkChannels.contains(channel), raw >= 0.85 || raw <= 0.12 {
                values[index] = Float(filters[index].snap(to: raw, at: pose.timestamp))
            } else {
                values[index] = Float(filters[index].filter(raw, at: pose.timestamp))
            }
        }
        return FacePose(values: values, timestamp: pose.timestamp, hasFace: pose.hasFace)
    }

    mutating func reset() {
        for index in filters.indices {
            filters[index].reset()
        }
    }

    /// Tuning per channel. Expressions live in 0…1 so a blink moves at roughly
    /// ten units a second and swings its cutoff wide open; angles are radians,
    /// where a brisk head turn is about one unit a second.
    static func filter(for channel: FaceChannel) -> OneEuroFilter {
        if FaceChannel.blinkChannels.contains(channel) {
            return OneEuroFilter(minCutoff: 3.0, beta: 1.5)
        }
        if channel.isExpression {
            return OneEuroFilter(minCutoff: 1.2, beta: 0.8)
        }
        if FaceChannel.headChannels.contains(channel) {
            return OneEuroFilter(minCutoff: 0.8, beta: 0.4)
        }
        return OneEuroFilter(minCutoff: 1.5, beta: 0.6)
    }
}
