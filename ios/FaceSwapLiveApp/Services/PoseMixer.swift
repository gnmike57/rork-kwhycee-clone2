import Foundation

/// Blends the tracked pose with the idle. When readings stop for about half a
/// second the weight eases to idle over 0.6 s; when they return it eases back
/// within a third of a second. Driven by explicit tick times, so it can be
/// stepped in a test exactly as the 30 fps draw steps it.
nonisolated struct PoseMixer: Sendable, Equatable {
    /// A reading older than this no longer counts as fresh.
    static let freshWindow: TimeInterval = 0.5

    /// How long the ease to idle takes.
    static let easeToIdle: TimeInterval = 0.6

    /// How long the ease back to tracked takes.
    static let easeToTracked: TimeInterval = 0.33

    /// 0 is all idle, 1 is all tracked.
    private(set) var trackedWeight: Double = 0

    private var lastTick: TimeInterval?

    var isIdling: Bool { trackedWeight < 0.001 }

    /// Advances the blend to `time`. `lastPoseAt` is when the newest valid
    /// reading arrived, nil when none has.
    @discardableResult
    mutating func advance(to time: TimeInterval, lastPoseAt: TimeInterval?) -> Double {
        let fresh: Bool
        if let lastPoseAt {
            fresh = time - lastPoseAt < Self.freshWindow
        } else {
            fresh = false
        }
        let target: Double = fresh ? 1 : 0

        let previousTick = lastTick
        lastTick = time
        guard let previousTick else { return trackedWeight }
        let dt = max(time - previousTick, 0)
        let rate = target > trackedWeight ? 1 / Self.easeToTracked : 1 / Self.easeToIdle
        let step = dt * rate
        if target > trackedWeight {
            trackedWeight = min(trackedWeight + step, target)
        } else {
            trackedWeight = max(trackedWeight - step, target)
        }
        return trackedWeight
    }

    /// The pose to draw: the idle when nothing is tracked, otherwise the
    /// eased blend.
    func mix(tracked: FacePose?, idle: FacePose) -> FacePose {
        guard let tracked, trackedWeight > 0 else { return idle }
        let eased = Self.smoothstep(trackedWeight)
        var mixed = idle.mixed(with: tracked, amount: Float(eased))
        mixed.timestamp = idle.timestamp
        mixed.hasFace = true
        return mixed
    }

    mutating func reset() {
        trackedWeight = 0
        lastTick = nil
    }

    static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
