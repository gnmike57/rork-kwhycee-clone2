import Foundation
import Testing
@testable import FaceSwapLiveApp

/// Stage 0 and Stage 1 follow-ups: the second packet layout, sender lock,
/// optional head pose, idle rules, and the page name surface.
struct FaceTrackingFollowUpTests {
    @Test func layoutADecodesWhenTheDeviceIDHasNoLengthPrefix() throws {
        let data = Self.layoutAPacket(headYaw: 0.2)
        let packet = try LiveLinkFacePacket.decode(data)
        #expect(packet.deviceID == "8A1F0C2E-DEAD-BEEF-0000-1234567890AB")
        #expect(packet.subjectName == "Kai")
        #expect(packet.frameNumber == 100)
        #expect(packet.frameRateNumerator == 60)
        #expect(packet.includesHeadPose)
        #expect(abs(packet.values[FaceChannel.jawOpen.rawValue] - 0.4) < 1e-6)
    }

    @Test func uuidShapedGarbageIsAnUnrecognizedLayout() {
        var data = Data([LiveLinkFacePacket.supportedVersion])
        data.append(contentsOf: "8A1F0C2E-DEAD-BEEF-0000-1234567890AB".utf8)
        data.append(contentsOf: [0x00, 0x01])
        #expect(throws: LiveLinkFacePacket.DecodeError.unrecognizedLayout) {
            try LiveLinkFacePacket.decode(data)
        }
    }

    @Test func recordedPacketCarriesHeadPoseAndASenderTime() throws {
        let data = LiveLinkFacePacketTests.data(fromHex: LiveLinkFacePacketTests.recordedFrameHex)
        let packet = try LiveLinkFacePacket.decode(data)
        #expect(packet.includesHeadPose)
        let seconds = try #require(packet.qualifiedSeconds)
        #expect(seconds > 80_000)
    }

    @Test func allZeroHeadAnglesMeanHeadPoseWasNotSent() {
        let packet = LiveLinkFacePacketTests.samplePacket(
            values: [Float](repeating: 0.2, count: FaceChannel.expressionCount) + [Float](repeating: 0, count: 9)
        )
        #expect(!packet.includesHeadPose)
        #expect(packet.describesFace)

        var presence = HeadPosePresence()
        presence.observe(packet.pose(timestamp: 1))
        #expect(presence.isExpressionOnly)
        var withHead = packet.pose(timestamp: 2)
        withHead[.headYaw] = 0.04
        presence.observe(withHead)
        #expect(!presence.isExpressionOnly)
    }

    @Test func senderLockKeepsTheFirstPhone() {
        var lock = SenderLock()
        #expect(lock.accept("Kai's iPhone"))
        #expect(lock.lockedName == "Kai's iPhone")
        #expect(lock.accept("Kai's iPhone"))
        #expect(!lock.accept("Other iPhone"))
        #expect(lock.accept(""))
        lock.release()
        #expect(lock.lockedName == nil)
        #expect(lock.accept("Other iPhone"))
    }

    @Test func senderClockMapsFrameTimeAndReanchorsAJump() {
        var clock = SenderClock()
        let first = clock.localTime(qualified: 10, receivedAt: 100)
        #expect(first == 100)
        let next = clock.localTime(qualified: 10.5, receivedAt: 100.6)
        #expect(abs(next - 100.5) < 1e-9)
        let jumped = clock.localTime(qualified: 1, receivedAt: 101)
        #expect(jumped == 101)
    }

    @Test func burstWithTwoPercentLossStillSamplesForward() {
        var resampler = PoseResampler()
        var time = 0.0
        let step = 1.0 / 60
        var dropped = 0
        for index in 0..<120 {
            time += step
            if index % 50 == 0 {
                dropped += 1
                continue
            }
            var pose = FacePose.neutral
            pose.timestamp = time
            pose.hasFace = true
            pose[.jawOpen] = Float(index) / 120
            resampler.add(pose)
        }
        #expect(dropped == 3)

        var previous = 0.0
        for frame in 1...50 {
            let sample = resampler.sample(at: Double(frame) / 30)
            let pose = try! #require(sample)
            #expect(pose.timestamp >= previous)
            previous = pose.timestamp
        }
    }

    @Test func blinkEndsSnapInsteadOfSticking() {
        var smoother = PoseSmoother()
        var pose = FacePose.neutral
        pose.timestamp = 0
        pose[.eyeBlinkLeft] = 0
        _ = smoother.smooth(pose)

        pose.timestamp = 1.0 / 60
        pose[.eyeBlinkLeft] = 1
        let closed = smoother.smooth(pose)
        #expect(closed[.eyeBlinkLeft] == 1)

        pose.timestamp = 2.0 / 60
        let held = smoother.smooth(pose)
        #expect(held[.eyeBlinkLeft] == 1)

        pose.timestamp = 3.0 / 60
        pose[.eyeBlinkLeft] = 0
        let opened = smoother.smooth(pose)
        #expect(opened[.eyeBlinkLeft] == 0)
    }

    @Test func idleStaysOffUntilAFaceHasBeenSeenAndUnderReduceMotion() {
        #expect(!IdlePolicy.allowsIdle(hasSeenLiveFace: false, reduceMotion: false))
        #expect(!IdlePolicy.allowsIdle(hasSeenLiveFace: true, reduceMotion: true))
        #expect(IdlePolicy.allowsIdle(hasSeenLiveFace: true, reduceMotion: false))
    }

    @Test func capabilityMatrixMatchesTheHardwareFacts() {
        #expect(FaceTrackingCapability.classify(faceTrackingSupported: true, hasTrueDepth: true) == .faceID)
        #expect(FaceTrackingCapability.classify(faceTrackingSupported: true, hasTrueDepth: false) == .neuralEngine)
        #expect(FaceTrackingCapability.classify(faceTrackingSupported: false, hasTrueDepth: false) == .unsupported)
        #expect(FaceTrackingCapability.neuralEngine.detail.contains("noisier"))
        #expect(!FaceTrackingCapability.neuralEngine.detail.localizedCaseInsensitiveContains("expression only"))
    }

    @Test func trackerDropsToThirtyWhenHotAndPrefersTheEarlierTie() {
        #expect(TrackerRate.framesPerSecond(for: .nominal) == 60)
        #expect(TrackerRate.framesPerSecond(for: .fair) == 60)
        #expect(TrackerRate.framesPerSecond(for: .serious) == 30)
        #expect(TrackerRate.framesPerSecond(for: .critical) == 30)
        #expect(TrackerRate.indexPreferring(60, among: [60, 30, 60]) == 0)
        #expect(TrackerRate.indexPreferring(30, among: [60, 30]) == 1)
        #expect(TrackerRate.indexPreferring(60, among: []) == nil)
    }

    @Test func tiltedPhotosMaySwayButStraightOnPhotosDoNot() {
        var straight = IdlePoseGenerator(seed: 11, startingAt: 0)
        var tilted = IdlePoseGenerator(seed: 11, startingAt: 0)
        tilted.allowsHeadSway = true
        var sawSway = false
        for step in 0..<300 {
            let t = Double(step) / 30
            let straightPose = straight.pose(at: t)
            let tiltedPose = tilted.pose(at: t)
            #expect(straightPose[.headYaw] == 0)
            if abs(tiltedPose[.headYaw]) > 0.001 { sawSway = true }
        }
        #expect(sawSway)
    }

    @Test func pageNameSurfaceDoesNotMentionFaceTracking() {
        let script = StyleSheetProvider.patchScript
        #expect(script.contains("enumerateDevices"))
        #expect(script.contains("getUserMedia"))
        #expect(!script.contains("jawOpen"))
        #expect(!script.contains("LiveLink"))
        #expect(!script.contains("blendShape"))
        #expect(!script.contains("FaceTracking"))
    }

    private static func layoutAPacket(headYaw: Float) -> Data {
        var data = Data([LiveLinkFacePacket.supportedVersion])
        data.append(contentsOf: "8A1F0C2E-DEAD-BEEF-0000-1234567890AB".utf8)
        let name = "Kai"
        append(Int32(name.utf8.count), to: &data)
        data.append(contentsOf: name.utf8)
        append(Int32(100), to: &data)
        append(Float(0.25).bitPattern, to: &data)
        append(Int32(60), to: &data)
        append(Int32(1), to: &data)
        data.append(UInt8(FaceChannel.count))
        var values = [Float](repeating: 0, count: FaceChannel.count)
        values[FaceChannel.jawOpen.rawValue] = 0.4
        values[FaceChannel.headYaw.rawValue] = headYaw
        for value in values {
            append(value.bitPattern, to: &data)
        }
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var big = value.bigEndian
        withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }
}
