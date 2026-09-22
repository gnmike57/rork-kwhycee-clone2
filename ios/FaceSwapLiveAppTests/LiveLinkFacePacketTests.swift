import Foundation
import Testing
@testable import FaceSwapLiveApp

/// The wire format against a real recording and against synthetic packets.
struct LiveLinkFacePacketTests {
    /// One frame recorded from Live Link Face by the LLV capture tool (its
    /// example `dao.gesichter`): 320 bytes, 32-byte device ID, 18-byte name.
    static let recordedFrameHex = """
    060000002044454144433044452d313333372d313333372d313333372d4341464542414245000000124c4c5620\
    44656661756c7420446576696365005206f73df9b4000000003c000000013d393a75c33e283bb33dd569910000\
    0000000000003d35ded23ce66f02393ad9dc3e285e3b3ba6f00c00000000000000003d35d5f53ce371413da55b\
    e6000000003d0c87953d9e5e523dacdfda3d3ed5c53d89557c000000003cea2dab00000000000000003d363c56\
    3cacb8443db7619e3dcab1f93de035263e0643083e095af03d5a25423db33d953dd7ba3c3d3d04fa3d33fc093d\
    ee09053e033ea93c9f4e953ca1a96000000000000000003da4e7df3d5712983d5631f43cea54373ce50f023cda\
    319f3d29331e3d2b6fb73815c4ec3d7518553c977237bde8ea5bbb4bc8083dcdb343b923e1313d8241bb3dcd77\
    593b5155cc
    """

    static func data(fromHex hex: String) -> Data {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        return Data(bytes)
    }

    static func samplePacket(values: [Float]? = nil) -> LiveLinkFacePacket {
        var channelValues = [Float](repeating: 0, count: FaceChannel.count)
        channelValues[FaceChannel.jawOpen.rawValue] = 0.42
        channelValues[FaceChannel.eyeBlinkLeft.rawValue] = 0.9
        channelValues[FaceChannel.headYaw.rawValue] = 0.2
        channelValues[FaceChannel.headPitch.rawValue] = -0.1
        channelValues[FaceChannel.headRoll.rawValue] = 0.05
        return LiveLinkFacePacket(
            deviceID: "8A1F0C2E-DEAD-BEEF-0000-1234567890AB",
            subjectName: "Kai’s iPhone",
            frameNumber: 1234,
            subFrame: 0.25,
            frameRateNumerator: 60,
            frameRateDenominator: 1,
            values: values ?? channelValues
        )
    }

    @Test func channelLayoutMatchesLiveLinkFace() {
        #expect(FaceChannel.allCases.count == 61)
        #expect(FaceChannel.tongueOut.rawValue == 51)
        #expect(FaceChannel.headYaw.rawValue == 52)
        #expect(FaceChannel.rightEyeRoll.rawValue == 60)
        #expect(FaceChannel.eyeBlinkLeft.liveLinkName == "EyeBlinkLeft")
        #expect(FaceChannel.mouthUpperUpRight.liveLinkName == "MouthUpperUpRight")
    }

    @Test func decodesARecordedFrame() throws {
        let data = Self.data(fromHex: Self.recordedFrameHex)
        #expect(data.count == 320)

        let packet = try LiveLinkFacePacket.decode(data)
        #expect(packet.deviceID == "DEADC0DE-1337-1337-1337-CAFEBABE")
        #expect(packet.subjectName == "LLV Default Device")
        #expect(packet.frameNumber == 5_375_735)
        #expect(abs(packet.subFrame - 0.121_925_354) < 1e-6)
        #expect(packet.frameRateNumerator == 60)
        #expect(packet.frameRateDenominator == 1)
        #expect(packet.values.count == 61)

        #expect(abs(packet.values[FaceChannel.eyeLookDownLeft.rawValue] - 0.164_290) < 1e-5)
        #expect(abs(packet.values[FaceChannel.mouthRollLower.rawValue] - 0.134_136) < 1e-5)
        #expect(abs(packet.values[FaceChannel.headYaw.rawValue] - 0.059_838) < 1e-5)
        #expect(abs(packet.values[FaceChannel.headPitch.rawValue] - 0.018_487) < 1e-5)
        #expect(abs(packet.values[FaceChannel.headRoll.rawValue] - (-0.113_728)) < 1e-5)
        #expect(abs(packet.values[FaceChannel.rightEyeYaw.rawValue] - 0.063_602) < 1e-5)
        #expect(packet.describesFace)

        // Head angles are radians: a quarter turn of roll would read ~1.57, never 90.
        for channel in FaceChannel.headChannels {
            #expect(abs(packet.values[channel.rawValue]) < Float.pi)
        }
    }

    @Test func recordedFrameRoundTripsThroughTheEncoder() throws {
        let data = Self.data(fromHex: Self.recordedFrameHex)
        let packet = try LiveLinkFacePacket.decode(data)
        #expect(packet.encoded() == data)
    }

    @Test func syntheticPacketRoundTrips() throws {
        let packet = Self.samplePacket()
        let decoded = try LiveLinkFacePacket.decode(packet.encoded())
        #expect(decoded == packet)
        #expect(decoded.subjectName == "Kai’s iPhone")
    }

    @Test func trailingBytesAreTolerated() throws {
        var data = Self.samplePacket().encoded()
        data.append(contentsOf: [0xAA, 0xBB, 0xCC])
        let decoded = try LiveLinkFacePacket.decode(data)
        #expect(decoded == Self.samplePacket())
    }

    @Test func rejectsTruncatedPackets() {
        let data = Self.samplePacket().encoded()
        for length in [0, 1, 4, 40, 100, data.count - 1] {
            #expect(throws: LiveLinkFacePacket.DecodeError.tooShort) {
                try LiveLinkFacePacket.decode(data.prefix(length))
            }
        }
    }

    @Test func rejectsOtherVersions() {
        var data = Self.samplePacket().encoded()
        data[data.startIndex] = 5
        #expect(throws: LiveLinkFacePacket.DecodeError.unsupportedVersion(5)) {
            try LiveLinkFacePacket.decode(data)
        }
    }

    @Test func rejectsWrongChannelCount() {
        var data = Self.samplePacket().encoded()
        // The count byte sits right after the two strings and the 16-byte frame time.
        let deviceBytes = Self.samplePacket().deviceID.utf8.count
        let nameBytes = Self.samplePacket().subjectName.utf8.count
        let countOffset = 1 + 4 + deviceBytes + 4 + nameBytes + 16
        data[data.startIndex + countOffset] = 52
        #expect(throws: LiveLinkFacePacket.DecodeError.badChannelCount(52)) {
            try LiveLinkFacePacket.decode(data)
        }
    }

    @Test func rejectsImpossibleStringLengths() {
        var data = Data([LiveLinkFacePacket.supportedVersion])
        data.append(contentsOf: [0x7F, 0xFF, 0xFF, 0xFF])
        data.append(contentsOf: [UInt8](repeating: 0, count: 400))
        #expect(throws: LiveLinkFacePacket.DecodeError.badStringLength(Int32.max)) {
            try LiveLinkFacePacket.decode(data)
        }

        var negative = Data([LiveLinkFacePacket.supportedVersion])
        negative.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFE])
        negative.append(contentsOf: [UInt8](repeating: 0, count: 400))
        #expect(throws: LiveLinkFacePacket.DecodeError.badStringLength(-2)) {
            try LiveLinkFacePacket.decode(negative)
        }
    }

    @Test func rejectsNonFiniteValues() {
        var values = [Float](repeating: 0, count: FaceChannel.count)
        values[FaceChannel.jawOpen.rawValue] = .nan
        let data = Self.samplePacket(values: values).encoded()
        #expect(throws: LiveLinkFacePacket.DecodeError.nonFiniteValue) {
            try LiveLinkFacePacket.decode(data)
        }
    }

    @Test func garbageIsRejectedNotCrashed() {
        var random = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let length = Int.random(in: 0..<400, using: &random)
            let bytes = (0..<length).map { _ in UInt8.random(in: 0...255, using: &random) }
            _ = try? LiveLinkFacePacket.decode(Data(bytes))
        }
    }

    @Test func allZeroPacketMeansNoFace() {
        let packet = Self.samplePacket(values: [Float](repeating: 0, count: FaceChannel.count))
        #expect(!packet.describesFace)
        let pose = packet.pose(timestamp: 10)
        #expect(!pose.hasFace)
        #expect(pose.timestamp == 10)
    }

    @Test func poseAppliesTheHeadSignTableAndClamps() {
        var values = [Float](repeating: 0, count: FaceChannel.count)
        values[FaceChannel.headYaw.rawValue] = 0.2
        values[FaceChannel.headPitch.rawValue] = 0.1
        values[FaceChannel.headRoll.rawValue] = 0.05
        values[FaceChannel.leftEyeYaw.rawValue] = 0.3
        values[FaceChannel.jawOpen.rawValue] = 1.4
        values[FaceChannel.browInnerUp.rawValue] = -0.2

        let pose = Self.samplePacket(values: values).pose(timestamp: 1)
        #expect(pose.hasFace)
        #expect(abs(pose[.headYaw] - (-0.2)) < 1e-6)
        #expect(abs(pose[.headPitch] - (-0.1)) < 1e-6)
        #expect(abs(pose[.headRoll] - 0.05) < 1e-6)
        #expect(abs(pose[.leftEyeYaw] - (-0.3)) < 1e-6)
        #expect(pose[.jawOpen] == 1)
        #expect(pose[.browInnerUp] == 0)
    }
}
