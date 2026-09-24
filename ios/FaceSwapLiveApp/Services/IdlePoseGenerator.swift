import Foundation

/// The face's resting life: irregular blinks averaging about 5 seconds, a rare
/// double blink, tiny eye flicks, and a breath under 1% on the jaw and nose.
///
/// Head sway stays off unless a later stage says the photo is already tilted.
/// Fully determined by its seed and the times it is asked about.
nonisolated struct IdlePoseGenerator: Sendable, Equatable {
    static let blinkMean: TimeInterval = 5
    static let blinkMinimum: TimeInterval = 1.2
    static let doubleBlinkChance: Double = 0.1
    static let doubleBlinkGap: TimeInterval = 0.18

    /// Lids close, hold, then open — about a quarter of a second in all.
    static let blinkClose: TimeInterval = 0.08
    static let blinkHold: TimeInterval = 0.04
    static let blinkOpen: TimeInterval = 0.16
    static var blinkDuration: TimeInterval { blinkClose + blinkHold + blinkOpen }

    /// Breath stays under 1% and never moves the head.
    static let breathCeiling: Float = 0.009
    static let flickAmplitude: Float = 0.035
    static let swayYaw: Float = 0.008

    /// Time zero for the breath curve.
    let origin: TimeInterval

    /// Straight-on photos stay still in the head. A tilted photo may sway a little.
    var allowsHeadSway = false

    private var random: SplitMix64
    private var currentBlinkStart: TimeInterval?
    private var nextBlinkStart: TimeInterval
    private var nextFlickStart: TimeInterval
    private var flickEnd: TimeInterval = -.greatestFiniteMagnitude
    private var flickYaw: Float = 0
    private var flickPitch: Float = 0

    init(seed: UInt64, startingAt origin: TimeInterval) {
        self.origin = origin
        var random = SplitMix64(seed: seed)
        nextBlinkStart = origin + random.exponential(mean: Self.blinkMean, minimum: 0.8)
        nextFlickStart = origin + random.exponential(mean: 2.4, minimum: 0.5)
        self.random = random
    }

    /// The idle pose at `time`. Times must not go backwards.
    /// Reduce Motion returns a true still.
    mutating func pose(at time: TimeInterval, reducedMotion: Bool = false) -> FacePose {
        if reducedMotion {
            var still = FacePose.neutral
            still.timestamp = time
            return still
        }

        advanceBlinks(to: time)
        advanceFlicks(to: time)

        var pose = FacePose.neutral
        pose.timestamp = time
        pose.hasFace = true

        let blink = blinkAmount(at: time)
        pose[.eyeBlinkLeft] = blink
        pose[.eyeBlinkRight] = blink

        let t = time - origin
        let wave = Float(sin(2 * .pi * 0.16 * t))
        let slow = Float(sin(2 * .pi * 0.07 * t + 1.3))
        let breath = min(max(0, 0.006 * wave + 0.002 * slow), Self.breathCeiling)
        pose[.jawOpen] = breath
        pose[.noseSneerLeft] = breath * 0.5
        pose[.noseSneerRight] = breath * 0.5

        if time < flickEnd {
            pose[.leftEyeYaw] = flickYaw
            pose[.rightEyeYaw] = flickYaw
            pose[.leftEyePitch] = flickPitch
            pose[.rightEyePitch] = flickPitch
        }

        if allowsHeadSway {
            pose[.headYaw] = Self.swayYaw * Float(sin(2 * .pi * 0.05 * t + 0.4))
        }

        return pose
    }

    private mutating func advanceBlinks(to time: TimeInterval) {
        while time >= nextBlinkStart {
            currentBlinkStart = nextBlinkStart
            let isDouble = random.nextDouble(in: 0...1) < Self.doubleBlinkChance
            let gap = isDouble
                ? Self.doubleBlinkGap
                : random.exponential(mean: Self.blinkMean, minimum: Self.blinkMinimum)
            nextBlinkStart += Self.blinkDuration + gap
        }
    }

    private mutating func advanceFlicks(to time: TimeInterval) {
        while time >= nextFlickStart {
            flickYaw = Float(random.nextDouble(in: -1...1)) * Self.flickAmplitude
            flickPitch = Float(random.nextDouble(in: -0.4...0.4)) * Self.flickAmplitude
            flickEnd = nextFlickStart + 0.12
            nextFlickStart = flickEnd + random.exponential(mean: 2.4, minimum: 0.6)
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

        /// Delayed exponential: never shorter than `minimum`, averaging about `mean`.
        mutating func exponential(mean: Double, minimum: Double) -> Double {
            let unit = nextDouble(in: 0.000_001...0.999_999)
            return max(-mean * log(1 - unit), minimum)
        }
    }
}
