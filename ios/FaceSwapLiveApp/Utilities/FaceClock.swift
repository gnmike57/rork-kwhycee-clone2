import QuartzCore

/// Monotonic seconds for pose timestamps. Unaffected by wall-clock changes, so
/// filter deltas and freshness checks never jump.
nonisolated enum FaceClock {
    static func now() -> TimeInterval {
        CACurrentMediaTime()
    }
}
