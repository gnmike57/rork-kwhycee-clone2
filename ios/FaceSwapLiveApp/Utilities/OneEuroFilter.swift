import Foundation

/// The 1€ filter (Casiez, Roussel & Vogel): a low-pass whose cutoff rises with
/// speed. Slow drift and jitter are damped hard; fast moves such as a blink go
/// through almost untouched.
///
/// Pure value type driven by explicit timestamps, so the same inputs always
/// produce the same outputs.
nonisolated struct OneEuroFilter: Sendable, Equatable {
    /// Cutoff at rest, in Hz. Lower means smoother but laggier.
    var minCutoff: Double

    /// How much speed opens the cutoff. Higher means less lag on fast moves.
    var beta: Double

    /// Cutoff for the speed estimate itself, in Hz.
    var derivativeCutoff: Double

    private var lastValue: Double?
    private var lastDerivative: Double = 0
    private var lastTime: TimeInterval?

    init(minCutoff: Double, beta: Double, derivativeCutoff: Double = 1) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    /// The most recent output, or nil before the first sample.
    var value: Double? { lastValue }

    /// Feeds one sample. Out-of-order or repeated timestamps return the last
    /// output without changing state.
    mutating func filter(_ value: Double, at time: TimeInterval) -> Double {
        guard let previous = lastValue, let previousTime = lastTime else {
            lastValue = value
            lastTime = time
            lastDerivative = 0
            return value
        }
        let dt = time - previousTime
        guard dt > 0 else { return previous }

        let rawDerivative = (value - previous) / dt
        let derivativeAlpha = Self.alpha(cutoff: derivativeCutoff, dt: dt)
        let derivative = lastDerivative + derivativeAlpha * (rawDerivative - lastDerivative)

        let cutoff = minCutoff + beta * abs(derivative)
        let alpha = Self.alpha(cutoff: cutoff, dt: dt)
        let filtered = previous + alpha * (value - previous)

        lastValue = filtered
        lastDerivative = derivative
        lastTime = time
        return filtered
    }

    /// Forgets history; the next sample passes straight through.
    mutating func reset() {
        lastValue = nil
        lastDerivative = 0
        lastTime = nil
    }

    /// Smoothing factor for an exponential filter with `cutoff` Hz over `dt` seconds.
    static func alpha(cutoff: Double, dt: TimeInterval) -> Double {
        let tau = 1 / (2 * Double.pi * max(cutoff, 0.001))
        return 1 / (1 + tau / dt)
    }
}
