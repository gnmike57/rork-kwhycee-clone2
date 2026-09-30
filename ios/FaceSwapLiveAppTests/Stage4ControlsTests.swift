import Testing
import UIKit
@testable import FaceSwapLiveApp

/// Stage 4's automated checks: capsule wording and colour, packet health from
/// synthetic arrivals, the haptics switch, one-time flags, per-photo memory
/// and the photo controls' hidden state.
struct Stage4ControlsTests {
    // MARK: - Capsule wording

    private func line(
        _ state: FaceTrackingState,
        rate: Int = 60,
        address: String? = "192.168.1.23",
        port: UInt16 = 11111,
        sender: String? = nil,
        expressionOnly: Bool = false,
        hasFace: Bool = true
    ) -> String? {
        FaceTrackingCapsule.line(
            state: state,
            rate: rate,
            address: address,
            port: port,
            senderName: sender,
            isExpressionOnly: expressionOnly,
            hasSeenFace: hasFace
        )
    }

    @Test func capsuleHiddenWhenTrackingOff() {
        #expect(line(.off) == nil)
    }

    @Test func capsuleWordingForEveryState() {
        #expect(line(.standby) == "Waiting for a still on the feed")
        #expect(line(.starting) == "Looking for your face…")
        #expect(line(.searching) == "Looking for your face…")
        #expect(line(.live) == "Tracking live · 60/s")
        #expect(line(.live, rate: 30) == "Tracking live · 30/s")
        #expect(line(.lost) == "Link lost — idling")
        #expect(line(.listening) == "Listening on 192.168.1.23 : 11111")
        #expect(line(.listening, address: nil) == "Listening on :11111")
    }

    @Test func receivingWordingCoversEveryShape() {
        #expect(line(.receiving, sender: "Kai's iPhone") == "Receiving from Kai's iPhone")
        #expect(line(.receiving) == "Receiving")
        #expect(line(.receiving, hasFace: false) == "Receiving · no face")
        #expect(
            line(.receiving, sender: "Kai's iPhone", expressionOnly: true)
                == "Receiving from Kai's iPhone · expression only"
        )
        #expect(line(.receiving, expressionOnly: true) == "Receiving · expression only")
    }

    @Test func unavailableWordingNamesTheProblem() {
        #expect(line(.unavailable(.cameraDenied)) == "Camera access denied")
        #expect(line(.unavailable(.portInUse(11111))) == "Port 11111 is already in use")
        #expect(line(.unavailable(.notSupported)) == "Face tracking isn't supported here")
        #expect(line(.unavailable(.failed("x"))) == "Tracking failed")
    }

    @Test func moodForEveryState() {
        #expect(FaceTrackingCapsule.mood(state: .off) == .off)
        #expect(FaceTrackingCapsule.mood(state: .standby) == .waiting)
        #expect(FaceTrackingCapsule.mood(state: .starting) == .searching)
        #expect(FaceTrackingCapsule.mood(state: .searching) == .searching)
        #expect(FaceTrackingCapsule.mood(state: .listening) == .searching)
        #expect(FaceTrackingCapsule.mood(state: .live) == .live)
        #expect(FaceTrackingCapsule.mood(state: .receiving) == .live)
        #expect(FaceTrackingCapsule.mood(state: .lost) == .lost)
        #expect(FaceTrackingCapsule.mood(state: .unavailable(.cameraDenied)) == .error)
    }

    // MARK: - Packet health

    @Test func emptyTrackerReadsEmpty() {
        #expect(PacketHealthTracker().snapshot(at: 100) == .empty)
    }

    @Test func steadyStreamReadsFullRateAndNoLoss() {
        var tracker = PacketHealthTracker()
        for i in 0..<180 { tracker.record(at: Double(i) / 60) }
        let health = tracker.snapshot(at: 3.0)
        #expect(abs(health.ratePerSecond - 60) < 1)
        #expect(health.lostFraction < 0.01)
        #expect(health.packetCount == 180)
        #expect(health.jitterSeconds < 0.002)
    }

    @Test func droppedPacketsShowUpAsLoss() {
        var tracker = PacketHealthTracker()
        for i in 0..<180 where i % 5 != 0 { tracker.record(at: Double(i) / 60) }
        let health = tracker.snapshot(at: 3.0)
        #expect(health.packetCount == 144)
        #expect(abs(health.lostFraction - 0.2) < 0.02)
    }

    @Test func lastSeenAgeGrowsBetweenPackets() {
        var tracker = PacketHealthTracker()
        tracker.record(at: 10)
        #expect(tracker.snapshot(at: 10.5).secondsSinceLastPacket == 0.5)
        #expect(tracker.snapshot(at: 12).secondsSinceLastPacket == 2)
    }

    @Test func resetForgetsEverything() {
        var tracker = PacketHealthTracker()
        tracker.record(at: 1)
        tracker.reset()
        #expect(tracker.snapshot(at: 2) == .empty)
    }

    // MARK: - Haptics switch

    @Test func hapticGateRespectsTheSwitchAndReduceMotion() {
        #expect(FaceTrackingController.shouldBuzz(enabled: true, reduceMotion: false))
        #expect(!FaceTrackingController.shouldBuzz(enabled: false, reduceMotion: false))
        #expect(!FaceTrackingController.shouldBuzz(enabled: true, reduceMotion: true))
    }

    // MARK: - One-time notes

    @MainActor
    @Test func oneTimeFlagsSurviveARelaunch() {
        let name = "stage4.flags.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }

        let first = FaceTrackingController(defaults: suite)
        #expect(!first.hasSeenPillTip)
        #expect(!first.hasSeenGreenDotNote)

        first.markPillTipSeen()
        first.markGreenDotNoteSeen()

        let second = FaceTrackingController(defaults: suite)
        #expect(second.hasSeenPillTip)
        #expect(second.hasSeenGreenDotNote)
    }

    // MARK: - Per-photo memory

    private static func frontFace() -> MappedFace {
        let leftEye = [CGPoint(x: 0.58, y: 0.38), CGPoint(x: 0.66, y: 0.38), CGPoint(x: 0.62, y: 0.36), CGPoint(x: 0.62, y: 0.40)]
        let rightEye = [CGPoint(x: 0.34, y: 0.38), CGPoint(x: 0.42, y: 0.38), CGPoint(x: 0.38, y: 0.36), CGPoint(x: 0.38, y: 0.40)]
        let regions: [FaceRegion: FaceSample] = [
            .leftEye: FaceSample(points: leftEye, confidence: 0.9),
            .rightEye: FaceSample(points: rightEye, confidence: 0.9),
            .leftPupil: FaceSample(points: [CGPoint(x: 0.62, y: 0.38)], confidence: 0.9),
            .rightPupil: FaceSample(points: [CGPoint(x: 0.38, y: 0.38)], confidence: 0.9),
            .leftEyebrow: FaceSample(points: [CGPoint(x: 0.56, y: 0.30), CGPoint(x: 0.62, y: 0.29), CGPoint(x: 0.68, y: 0.31)], confidence: 0.8),
            .rightEyebrow: FaceSample(points: [CGPoint(x: 0.32, y: 0.31), CGPoint(x: 0.38, y: 0.29), CGPoint(x: 0.44, y: 0.30)], confidence: 0.8),
            .nose: FaceSample(points: [CGPoint(x: 0.50, y: 0.48), CGPoint(x: 0.50, y: 0.56)], confidence: 0.8),
            .outerLips: FaceSample(points: [CGPoint(x: 0.42, y: 0.66), CGPoint(x: 0.50, y: 0.64), CGPoint(x: 0.58, y: 0.66), CGPoint(x: 0.50, y: 0.70)], confidence: 0.2),
            .innerLips: FaceSample(points: [CGPoint(x: 0.46, y: 0.66), CGPoint(x: 0.54, y: 0.66), CGPoint(x: 0.50, y: 0.68)], confidence: 0.8),
            .faceContour: FaceSample(points: [
                CGPoint(x: 0.28, y: 0.42), CGPoint(x: 0.30, y: 0.62), CGPoint(x: 0.40, y: 0.78),
                CGPoint(x: 0.50, y: 0.84), CGPoint(x: 0.60, y: 0.78), CGPoint(x: 0.70, y: 0.62),
                CGPoint(x: 0.72, y: 0.42),
            ], confidence: 0.9),
        ]
        return MappedFace(
            id: 0,
            bounds: CGRect(x: 0.26, y: 0.22, width: 0.48, height: 0.56),
            roll: 0,
            yaw: 0,
            pitch: 0,
            confidence: 0.95,
            regions: regions
        )
    }

    private static func rig() -> FaceRig? {
        FaceRigBuilder.build(from: frontFace(), wearsGlasses: false, teethVisible: false)
    }

    private static func flatImage(_ color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { _ in
            color.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 8, height: 8)).fill()
        }
    }

    @Test func calibrationRoundTripsThroughPhotoStorage() {
        var pose = FacePose(values: .init(repeating: 0, count: FaceChannel.count), timestamp: 0, hasFace: true)
        pose[.jawOpen] = 0.4
        pose[.headYaw] = 0.2

        let restored = FacePose.decodeCalibration(pose.encodeCalibration())
        #expect(restored?[.jawOpen] == 0.4)
        #expect(restored?[.headYaw] == 0.2)

        // A stale or short record must never read as rest.
        #expect(FacePose.decodeCalibration([0, 1, 2]) == nil)
        #expect(FacePose.decodeCalibration(nil) == nil)
    }

    @MainActor
    @Test func strengthWritesReachMemoryAndSurviveSwitchingPhotos() throws {
        let viewModel = BrowserViewModel()
        let photoA = Self.flatImage(.red)
        let photoB = Self.flatImage(.blue)
        viewModel.frameCache.setMap(try #require(Self.rig()), note: nil, faces: [], for: photoA)
        viewModel.frameCache.setMap(try #require(Self.rig()), note: nil, faces: [], for: photoB)

        #expect(viewModel.livingStrength(for: photoA) == PhotoMemory.defaultStrength)

        viewModel.setLivingStrength(0.4, for: photoA)
        #expect(viewModel.livingStrength(for: photoA) == 0.4)
        #expect(viewModel.photoMemory.changeCount == 1)

        // Switching photos keeps each photo's own value.
        viewModel.setLivingStrength(0.25, for: photoB)
        #expect(viewModel.livingStrength(for: photoB) == 0.25)
        #expect(viewModel.livingStrength(for: photoA) == 0.4)

        viewModel.setLivingStrength(0.9, for: photoA)
        #expect(viewModel.livingStrength(for: photoA) == 0.9)
    }

    @MainActor
    @Test func strengthWriteIgnoresUnmappedPhotos() {
        let viewModel = BrowserViewModel()
        let photo = Self.flatImage(.green)
        viewModel.setLivingStrength(0.1, for: photo)
        // No rig and no memory: nothing is invented, the default stands.
        #expect(viewModel.livingStrength(for: photo) == PhotoMemory.defaultStrength)
        #expect(viewModel.photoMemory.changeCount == 0)
    }

    // MARK: - Photo controls' hidden state

    @MainActor
    @Test func photoControlsHideWithoutFaceMap() throws {
        let viewModel = BrowserViewModel()
        #expect(viewModel.activeLivingStill == nil)
        #expect(viewModel.activeStillHasFace == false)

        let photo = Self.flatImage(.red)
        viewModel.frontImage = photo
        viewModel.frontSourceType = .image
        viewModel.livingFeed = LivingFeedSignal(facing: .front, slot: 0)

        #expect(viewModel.activeLivingStill != nil)
        // The photo is active but unmapped: the controls stay hidden.
        #expect(viewModel.activeStillHasFace == false)

        viewModel.frameCache.setMap(try #require(Self.rig()), note: nil, faces: [], for: photo)
        #expect(viewModel.activeStillHasFace == true)
    }
}
