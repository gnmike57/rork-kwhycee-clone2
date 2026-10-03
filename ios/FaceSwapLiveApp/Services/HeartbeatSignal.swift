import Foundation

/// The skin's natural colour rhythm: a wandering heart rate plus the slow
/// brightness of breathing. Nothing here touches the page — the value rides
/// the rendered frame as a subtle, red-biased tint.
nonisolated struct HeartbeatSignal {
    private var phase: Double = 0
    private var lastT: TimeInterval?

    /// One sample of the combined pulse, roughly 0…1.25: a sharp systole
    /// shaped heartbeat plus a much slower breathing sway.
    mutating func sample(at t: TimeInterval) -> Float {
        if let lastT {
            let dt = min(0.2, max(0, t - lastT))
            phase += dt * 2 * Double.pi * beatsPerMinute(t) / 60
        }
        lastT = t
        let beat = 0.5 + 0.5 * sin(phase)
        let systole = pow(beat, 3)
        let breath = 0.3 * sin(t * 2 * Double.pi * 0.22)
        return Float(systole * 0.9 + breath * 0.3)
    }

    /// Drifts between about 66 and 78 bpm, like a resting person.
    private func beatsPerMinute(_ t: TimeInterval) -> Double {
        72 + 5 * sin(t * 0.00021) + 3 * sin(t * 0.00047 + 2.0)
    }
}
