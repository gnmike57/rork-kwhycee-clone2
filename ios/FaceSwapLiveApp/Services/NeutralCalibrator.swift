import Foundation

/// Averages two seconds of readings into a rest pose. Feed it smoothed but
/// *uncalibrated* readings; the result is what later readings are re-centred on.
nonisolated struct NeutralCalibrator: Sendable, Equatable {
    /// How long the user holds still.
    static let holdDuration: TimeInterval = 2

    /// Fewer readings than this and the hold is not trusted.
    static let minimumSamples = 10

    private(set) var startedAt: TimeInterval?
    private var sums: [Double] = []
    private var sampleCount = 0

    var isRunning: Bool { startedAt != nil }

    /// 0…1 through the hold; 0 when not running.
    func progress(at time: TimeInterval) -> Double {
        guard let startedAt else { return 0 }
        return min(max((time - startedAt) / Self.holdDuration, 0), 1)
    }

    mutating func begin(at time: TimeInterval) {
        startedAt = time
        sums = Array(repeating: 0, count: FaceChannel.count)
        sampleCount = 0
    }

    mutating func cancel() {
        startedAt = nil
        sums = []
        sampleCount = 0
    }

    /// Folds in a reading. Once the hold has elapsed with enough readings the
    /// average is returned and the calibrator stops; otherwise nil.
    mutating func add(_ pose: FacePose, at time: TimeInterval) -> FacePose? {
        guard let startedAt, pose.hasFace else { return nil }
        for index in 0..<FaceChannel.count {
            sums[index] += Double(pose.values[index])
        }
        sampleCount += 1

        guard time - startedAt >= Self.holdDuration, sampleCount >= Self.minimumSamples else { return nil }
        let average = sums.map { Float($0 / Double(sampleCount)) }
        cancel()
        return FacePose(values: average, timestamp: time, hasFace: true)
    }
}
