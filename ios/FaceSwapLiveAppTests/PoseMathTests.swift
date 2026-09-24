import Foundation
import Testing
@testable import FaceSwapLiveApp

/// Smoothing, resampling, calibration, the idle and the tracked⇄idle blend —
/// all pure value types, so they are checked here exactly as the draw steps them.
struct PoseMathTests {
    private static func pose(_ channel: FaceChannel, _ value: Float, at time: TimeInterval) -> FacePose {
        var pose = FacePose.neutral
        pose.timestamp = time
        pose.hasFace = true
        pose[channel] = value
        return pose
    }

    // MARK: - FacePose

    @Test func shortValueArraysArePaddedNotCrashed() {
        let pose = FacePose(values: [0.5, 0.25], timestamp: 1)
        #expect(pose.values.count == FaceChannel.count)
        #expect(pose[.eyeBlinkLeft] == 0.5)
        #expect(pose[.eyeLookDownLeft] == 0.25)
        #expect(pose[.rightEyeRoll] == 0)
    }

    @Test func mixingIsLinear() {
        let a = Self.pose(.jawOpen, 0, at: 0)
        let b = Self.pose(.jawOpen, 1, at: 1)
        let mid = a.mixed(with: b, amount: 0.25)
        #expect(abs(mid[.jawOpen] - 0.25) < 1e-6)
        #expect(abs(mid.timestamp - 0.25) < 1e-9)
        #expect(a.mixed(with: b, amount: 0) == a)
        #expect(a.mixed(with: b, amount: 1) == b)
    }

    // MARK: - One Euro filter

    @Test func filterPassesTheFirstSampleAndConvergesOnAConstant() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0)
        #expect(filter.filter(0.7, at: 0) == 0.7)
        var last = 0.0
        for step in 1...120 {
            last = filter.filter(0.3, at: Double(step) / 60)
        }
        #expect(abs(last - 0.3) < 0.01)
    }

    @Test func filterIsDeterministic() {
        var a = PoseSmoother.filter(for: .jawOpen)
        var b = PoseSmoother.filter(for: .jawOpen)
        for step in 0..<200 {
            let t = Double(step) / 60
            let value = 0.5 + 0.4 * sin(t * 3) + (step % 3 == 0 ? 0.02 : -0.02)
            #expect(a.filter(value, at: t) == b.filter(value, at: t))
        }
    }

    @Test func filterIgnoresRepeatedAndBackwardsTimestamps() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0)
        _ = filter.filter(0.2, at: 1)
        let held = filter.filter(0.9, at: 1)
        #expect(held == 0.2)
        #expect(filter.filter(0.9, at: 0.5) == 0.2)
        #expect(filter.filter(0.9, at: 1.1) > 0.2)
    }

    @Test func blinksStaySnappyWhileJitterDies() {
        // A blink: the lid goes from open to shut in 80 ms at 60 readings/s.
        var blink = PoseSmoother.filter(for: .eyeBlinkLeft)
        var output = 0.0
        for step in 0...12 {
            let t = Double(step) / 60
            let target = min(Double(step) / 5, 1)
            output = blink.filter(target, at: t)
        }
        #expect(output > 0.85, "a blink should reach nearly shut within its own duration, got \(output)")

        // Jitter: ±0.03 wobble around 0.5 on a slow channel should be flattened.
        var jitter = PoseSmoother.filter(for: .mouthSmileLeft)
        var outputs: [Double] = []
        for step in 0..<240 {
            let t = Double(step) / 60
            let value = 0.5 + (step % 2 == 0 ? 0.03 : -0.03)
            outputs.append(jitter.filter(value, at: t))
        }
        let settled = outputs.suffix(60)
        let spread = (settled.max() ?? 0) - (settled.min() ?? 0)
        #expect(spread < 0.01, "jitter of 0.06 peak-to-peak should shrink below 0.01, got \(spread)")
    }

    @Test func smootherResetsCleanly() {
        var smoother = PoseSmoother()
        _ = smoother.smooth(Self.pose(.jawOpen, 1, at: 0))
        _ = smoother.smooth(Self.pose(.jawOpen, 1, at: 0.016))
        smoother.reset()
        let fresh = smoother.smooth(Self.pose(.jawOpen, 0.2, at: 5))
        #expect(fresh[.jawOpen] == 0.2)
    }

    // MARK: - Resampler

    @Test func resamplerInterpolatesBetweenNeighboursAndHoldsAtTheEnds() {
        // Readings 100 ms apart, well inside the half-second the resampler keeps.
        var resampler = PoseResampler()
        #expect(resampler.sample(at: 0) == nil)
        resampler.add(Self.pose(.jawOpen, 0, at: 1.0))
        resampler.add(Self.pose(.jawOpen, 1, at: 1.1))
        resampler.add(Self.pose(.jawOpen, 0, at: 1.2))

        #expect(resampler.sample(at: 0.5)?[.jawOpen] == 0)
        #expect(abs((resampler.sample(at: 1.05)?[.jawOpen] ?? -1) - 0.5) < 1e-5)
        #expect(abs((resampler.sample(at: 1.125)?[.jawOpen] ?? -1) - 0.75) < 1e-5)
        #expect(resampler.sample(at: 9)?[.jawOpen] == 0)
        #expect(resampler.latest?.timestamp == 1.2)
    }

    @Test func resamplerDropsStaleAndOutOfOrderReadings() {
        var resampler = PoseResampler()
        resampler.add(Self.pose(.jawOpen, 0.1, at: 1))
        resampler.add(Self.pose(.jawOpen, 0.9, at: 0.5))
        #expect(resampler.latest?[.jawOpen] == 0.1)

        resampler.add(Self.pose(.jawOpen, 0.5, at: 3))
        #expect(resampler.sample(at: 0)?[.jawOpen] == 0.5, "readings older than the window are gone")
    }

    // MARK: - Calibration

    @Test func calibrationAveragesTheHoldAndBecomesTheRestPose() {
        var calibrator = NeutralCalibrator()
        calibrator.begin(at: 0)
        #expect(calibrator.isRunning)

        var baseline: FacePose?
        for step in 0...130 {
            let t = Double(step) / 60
            var pose = Self.pose(.mouthSmileLeft, step % 2 == 0 ? 0.3 : 0.5, at: t)
            pose[.headYaw] = 0.1
            if let result = calibrator.add(pose, at: t) {
                baseline = result
                break
            }
            #expect(calibrator.progress(at: t) <= 1)
        }

        let rest = try! #require(baseline)
        #expect(abs(rest[.mouthSmileLeft] - 0.4) < 0.01)
        #expect(abs(rest[.headYaw] - 0.1) < 1e-5)
        #expect(!calibrator.isRunning)

        // The rest pose itself reads as fully neutral.
        let calibratedRest = rest.calibrated(against: rest)
        for channel in FaceChannel.allCases {
            #expect(abs(calibratedRest[channel]) < 1e-5, "\(channel) should be 0 at rest")
        }

        // A full coefficient still reaches 1 and a head turn reads relative to rest.
        var expressive = rest
        expressive[.mouthSmileLeft] = 1
        expressive[.headYaw] = 0.3
        let calibrated = expressive.calibrated(against: rest)
        #expect(abs(calibrated[.mouthSmileLeft] - 1) < 1e-5)
        #expect(abs(calibrated[.headYaw] - 0.2) < 1e-5)
    }

    @Test func calibrationNeedsTheFullHoldAndEnoughReadings() {
        var calibrator = NeutralCalibrator()
        calibrator.begin(at: 0)
        #expect(calibrator.add(Self.pose(.jawOpen, 0.2, at: 0.5), at: 0.5) == nil)
        #expect(calibrator.add(Self.pose(.jawOpen, 0.2, at: 2.5), at: 2.5) == nil, "two readings are not a hold")
        calibrator.cancel()
        #expect(!calibrator.isRunning)
        #expect(calibrator.progress(at: 3) == 0)
    }

    // MARK: - Idle

    @Test func idleIsDeterministicForASeed() {
        var a = IdlePoseGenerator(seed: 42, startingAt: 100)
        var b = IdlePoseGenerator(seed: 42, startingAt: 100)
        for step in 0..<900 {
            let t = 100 + Double(step) / 30
            #expect(a.pose(at: t) == b.pose(at: t))
        }

        var c = IdlePoseGenerator(seed: 43, startingAt: 100)
        var differs = false
        for step in 0..<900 {
            let t = 100 + Double(step) / 30
            if a.pose(at: t) != c.pose(at: t) { differs = true }
        }
        #expect(differs, "a different seed should blink at different times")
    }

    @Test func idleBlinksIrregularlyAndStaysInRange() {
        var idle = IdlePoseGenerator(seed: 7, startingAt: 0)
        var onsets: [TimeInterval] = []
        var wasClosed = false
        for step in 0..<(300 * 30) {
            let t = Double(step) / 30
            let pose = idle.pose(at: t)
            for channel in FaceChannel.allCases where channel.isExpression {
                #expect(pose[channel] >= 0 && pose[channel] <= 1)
            }
            #expect(pose[.eyeBlinkLeft] == pose[.eyeBlinkRight])
            #expect(pose[.headPitch] == 0)
            #expect(pose[.headYaw] == 0)
            #expect(pose[.headRoll] == 0)
            #expect(pose[.jawOpen] <= IdlePoseGenerator.breathCeiling)
            #expect(pose[.noseSneerLeft] <= IdlePoseGenerator.breathCeiling)

            let closed = pose[.eyeBlinkLeft] > 0.5
            if closed, !wasClosed { onsets.append(t) }
            wasClosed = closed
        }

        #expect(onsets.count >= 30, "five minutes should hold at least 30 blinks, got \(onsets.count)")
        let gaps = zip(onsets, onsets.dropFirst()).map { $1 - $0 }
        guard let shortest = gaps.min(), let longest = gaps.max(), !gaps.isEmpty else {
            Issue.record("expected blink gaps")
            return
        }
        let average = gaps.reduce(0, +) / Double(gaps.count)
        #expect(average > 2.5 && average < 8, "blinks should average about 5 s, got \(average)")
        #expect(gaps.contains { $0 < 1 }, "a rare double blink should land inside five minutes")
        #expect(longest - shortest > 1, "blinks should not be a fixed interval")
        _ = shortest
    }

    @Test func reduceMotionIdleIsATrueStill() {
        var idle = IdlePoseGenerator(seed: 3, startingAt: 0)
        let pose = idle.pose(at: 12, reducedMotion: true)
        #expect(pose.values.allSatisfy { $0 == 0 })
        #expect(!pose.hasFace)
    }

    // MARK: - Mixer

    @Test func mixerEasesToIdleAfterHalfASecondAndBackWithinAThird() {
        var mixer = PoseMixer()
        let frame = 1.0 / 30

        // Fresh readings: weight climbs to 1 within a third of a second.
        var t = 0.0
        mixer.advance(to: t, lastPoseAt: t)
        while t < 0.34 {
            t += frame
            mixer.advance(to: t, lastPoseAt: t)
        }
        #expect(mixer.trackedWeight == 1)
        #expect(!mixer.isIdling)

        // Readings stop at t: the weight holds for the fresh window, then eases out over 0.6 s.
        let lastPose = t
        var heldAtHalfSecond = 0.0
        var reachedIdleAt: TimeInterval?
        while t < lastPose + 2 {
            t += frame
            mixer.advance(to: t, lastPoseAt: lastPose)
            if abs(t - (lastPose + 0.45)) < frame / 2 { heldAtHalfSecond = mixer.trackedWeight }
            if mixer.isIdling, reachedIdleAt == nil { reachedIdleAt = t }
        }
        #expect(heldAtHalfSecond == 1, "still fully tracked just before the half-second window closes")
        let idleAfter = try! #require(reachedIdleAt) - lastPose
        #expect(idleAfter > 0.5 + 0.6 - 0.1 && idleAfter < 0.5 + 0.6 + 0.1, "idle reached \(idleAfter)s after the last reading")

        // Tracking returns: back to fully tracked within a third of a second.
        let returned = t
        var backAt: TimeInterval?
        while t < returned + 1 {
            t += frame
            mixer.advance(to: t, lastPoseAt: t)
            if mixer.trackedWeight == 1, backAt == nil { backAt = t }
        }
        let backAfter = try! #require(backAt) - returned
        #expect(backAfter <= 0.34 + frame, "back to tracked \(backAfter)s after tracking returned")
    }

    @Test func mixerOutputIsIdleWithoutATrackedPoseAndBlendsWithOne() {
        var mixer = PoseMixer()
        var idle = FacePose.neutral
        idle[.eyeBlinkLeft] = 1
        idle.timestamp = 5
        #expect(mixer.mix(tracked: nil, idle: idle) == idle)

        mixer.advance(to: 0, lastPoseAt: 0)
        mixer.advance(to: 1, lastPoseAt: 1)
        #expect(mixer.trackedWeight == 1)
        var tracked = FacePose.neutral
        tracked[.jawOpen] = 0.8
        let out = mixer.mix(tracked: tracked, idle: idle)
        #expect(abs(out[.jawOpen] - 0.8) < 1e-6)
        #expect(abs(out[.eyeBlinkLeft]) < 1e-6)
        #expect(out.timestamp == 5)
    }
}
