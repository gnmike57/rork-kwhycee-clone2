import Foundation

/// One reading of a face: every `FaceChannel` value plus when it was read.
///
/// Expressions run 0…1. Angles are radians in Apple's right-handed face frame,
/// which both sources are mapped into:
/// - `headYaw` is positive when the subject turns toward their **own left**
///   (a viewer looking at them sees the face turn to the viewer's right).
/// - `headPitch` is positive when the nose dips (looking down).
/// - `headRoll` is positive when the subject's left ear rises — counter-clockwise
///   to a viewer facing them.
/// - Eye angles use the same signs, measured relative to the head.
nonisolated struct FacePose: Sendable, Equatable {
    /// One value per `FaceChannel`, in channel order.
    private(set) var values: [Float]

    /// Monotonic seconds from `FaceClock` when the reading was taken.
    var timestamp: TimeInterval

    /// Whether the source actually saw a face. A pose without one carries
    /// rest values and only proves the source is alive.
    var hasFace: Bool

    /// Rest pose: every channel at zero.
    static let neutral = FacePose(
        values: Array(repeating: 0, count: FaceChannel.count),
        timestamp: 0,
        hasFace: false
    )

    /// Pads or trims `values` to the channel count so a short array can never
    /// crash a reader.
    init(values: [Float], timestamp: TimeInterval, hasFace: Bool = true) {
        if values.count == FaceChannel.count {
            self.values = values
        } else {
            var fixed = Array(values.prefix(FaceChannel.count))
            fixed.append(contentsOf: Array(repeating: 0, count: FaceChannel.count - fixed.count))
            self.values = fixed
        }
        self.timestamp = timestamp
        self.hasFace = hasFace
    }

    subscript(_ channel: FaceChannel) -> Float {
        get { values[channel.rawValue] }
        set { values[channel.rawValue] = newValue }
    }

    /// True when at least one channel is away from rest.
    var isMoving: Bool { values.contains { $0 != 0 } }

    /// Straight-line blend; `amount` 0 returns `self`, 1 returns `other`.
    /// The timestamp and face flag follow the same blend.
    func mixed(with other: FacePose, amount: Float) -> FacePose {
        let t = min(max(amount, 0), 1)
        var mixed = [Float](repeating: 0, count: FaceChannel.count)
        for index in 0..<FaceChannel.count {
            mixed[index] = values[index] + (other.values[index] - values[index]) * t
        }
        let time = timestamp + (other.timestamp - timestamp) * TimeInterval(t)
        return FacePose(values: mixed, timestamp: time, hasFace: t < 0.5 ? hasFace : other.hasFace)
    }

    /// Re-centres the reading on a rest pose. Expressions rescale so the rest
    /// reads 0 and a full coefficient still reads 1; angles shift so the rest
    /// heading becomes straight ahead.
    func calibrated(against rest: FacePose) -> FacePose {
        var out = values
        for channel in FaceChannel.allCases {
            let index = channel.rawValue
            let base = rest.values[index]
            if channel.isExpression {
                let span = max(1 - base, 0.05)
                out[index] = min(max((values[index] - base) / span, 0), 1)
            } else {
                out[index] = values[index] - base
            }
        }
        return FacePose(values: out, timestamp: timestamp, hasFace: hasFace)
    }

    /// Expressions held to 0…1 and angles to ±π, with non-finite values zeroed.
    func clamped() -> FacePose {
        var out = values
        for channel in FaceChannel.allCases {
            let index = channel.rawValue
            let value = values[index]
            guard value.isFinite else {
                out[index] = 0
                continue
            }
            out[index] = channel.isExpression
                ? min(max(value, 0), 1)
                : min(max(value, -.pi), .pi)
        }
        return FacePose(values: out, timestamp: timestamp, hasFace: hasFace)
    }

    /// A head or eye angle in degrees, handy for meters.
    func degrees(_ channel: FaceChannel) -> Double {
        Double(self[channel]) * 180 / .pi
    }
}
