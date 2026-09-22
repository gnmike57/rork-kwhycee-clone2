import Foundation

/// The face's resting life: a blink every 3–7 seconds, a slow breath and a
/// barely-there head sway. Fully determined by its seed and the times it is
/// asked about, so two generators with the same seed draw the same thing.
nonisolated struct IdlePoseGenerator: Sendable, Equatable {
    static let blinkInterval: ClosedRange<TimeInterval> = 3...7

    /// Lids close, hold, then open — about a quarter of a second in all.
    static let blinkClose: TimeInterval = 0.08
    static let blinkHold: TimeInterval = 0.04
    static let blinkOpen: TimeInterval = 0.16
    static var blinkDuration: TimeInterval { blinkClose + blinkHold + blinkOpen }

    /// Breath and sway amplitudes, in radians.
    static let breathPitch: Float = 0.012
    static let swayYaw: Float = 0.015
    static let swayRoll: Float = 0.006
    static let eyeDrift: Float = 0.03

    /// Time zero for the breath and sway curves.
    let origin: TimeInterval

    private var random: SplitMix64
    private var currentBlinkStart: TimeInterval?
    private var nextBlinkStart: TimeInterval

    init(seed: UInt64, startingAt origin: TimeInterval) {
        self.origin = origin
        var random = SplitMix64(seed: seed)
        // The first blink arrives sooner than a full interval so a freshly
        // idle face does not stare for seven seconds.
        nextBlinkStart = origin + random.nextDouble(in: 1...3)
        self.random = random
    }

    /// The idle pose at `time`. Times must not go backwards.
    mutating func pose(at time: TimeInterval) -> FacePose {
        advanceBlinks(to: time)

        var pose = FacePose.neutral
        pose.timestamp = time
        pose.hasFace = true

        let blink = blinkAmount(at: time)
        pose[.eyeBlinkLeft] = blink
        pose[.eyeBlinkRight] = blink

        let t = time - origin
        pose[.headPitch] = Self.breathPitch * Float(sin(2 * .pi * 0.22 * t))
        pose[.headYaw] = Self.swayYaw * Float(sin(2 * .pi * 0.09 * t + 1.1))
        pose[.headRoll] = Self.swayRoll * Float(sin(2 * .pi * 0.13 * t + 2.3))

        let drift = Self.eyeDrift * Float(sin(2 * .pi * 0.07 * t + 0.6))
        pose[.leftEyeYaw] = drift
        pose[.rightEyeYaw] = drift

        return pose
    }

    private mutating func advanceBlinks(to time: TimeInterval) {
        while time >= nextBlinkStart {
            currentBlinkStart = nextBlinkStart
            nextBlinkStart += random.nextDouble(in: Self.blinkInterval)
        }
    }

    /// 0 with the eyes open, 1 fully closed, following an eased close and open.
    private func blinkAmount(at time: TimeInterval) -> Float {
        guard let start = currentBlinkStart else { return 0 }
        let elapsed = time - start
        guard elapsed >= 0, elapsed < Self.blinkDuration else { return 0 }
        if elapsed < Self.blinkClose {
            return Self.easeInOut(Float(elapsed / Self.blinkClose))
        }
        if elapsed < Self.blinkClose + Self.blinkHold {
            return 1
        }
        let opening = (elapsed - Self.blinkClose - Self.blinkHold) / Self.blinkOpen
        return 1 - Self.easeInOut(Float(opening))
    }

    private static func easeInOut(_ x: Float) -> Float {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Small, fast, seedable generator so the idle is reproducible.
    nonisolated struct SplitMix64: Sendable, Equatable {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// Uniform in `range`.
        mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
            let unit = Double(next() >> 11) / Double(1 << 53)
            return range.lowerBound + (range.upperBound - range.lowerBound) * unit
        }
    }
}
