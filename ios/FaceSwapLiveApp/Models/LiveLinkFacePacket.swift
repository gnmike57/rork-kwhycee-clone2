import Foundation

/// One Live Link Face UDP packet, as Epic's app streams it (format version 6).
///
/// Layout, all multi-byte fields big-endian:
/// - `UInt8` version (always 6)
/// - `Int32` device-ID byte count, then that many UTF-8 bytes
/// - `Int32` subject-name byte count, then that many UTF-8 bytes
/// - `Int32` frame number, `Float32` sub-frame, `Int32` rate numerator, `Int32` rate denominator
/// - `UInt8` channel count (61), then 61 × `Float32` in `FaceChannel` order
///
/// Verified against a frame recorded from the real app: 320 bytes for a
/// 32-byte device ID and an 18-byte subject name.
nonisolated struct LiveLinkFacePacket: Sendable, Equatable {
    static let supportedVersion: UInt8 = 6
    static let channelCount = FaceChannel.count
    static let defaultPort: UInt16 = 11111

    /// Longest name or ID the decoder will accept; real senders stay well under.
    static let maximumStringBytes = 1024

    var deviceID: String
    var subjectName: String
    var frameNumber: Int32
    var subFrame: Float
    var frameRateNumerator: Int32
    var frameRateDenominator: Int32
    /// 61 raw values, exactly as sent.
    var values: [Float]

    nonisolated enum DecodeError: Error, Equatable, Sendable {
        case tooShort
        case unsupportedVersion(UInt8)
        case badStringLength(Int32)
        case badChannelCount(UInt8)
        case nonFiniteValue
    }

    init(
        deviceID: String,
        subjectName: String,
        frameNumber: Int32,
        subFrame: Float,
        frameRateNumerator: Int32,
        frameRateDenominator: Int32,
        values: [Float]
    ) {
        self.deviceID = deviceID
        self.subjectName = subjectName
        self.frameNumber = frameNumber
        self.subFrame = subFrame
        self.frameRateNumerator = frameRateNumerator
        self.frameRateDenominator = frameRateDenominator
        self.values = FacePose(values: values, timestamp: 0).values
    }

    // MARK: - Decoding

    /// Parses a datagram. Anything short, from another version, or carrying an
    /// impossible length, count or value is rejected rather than guessed at.
    static func decode(_ data: Data) throws -> LiveLinkFacePacket {
        var reader = ByteReader(bytes: [UInt8](data))

        guard let version = reader.readUInt8() else { throw DecodeError.tooShort }
        guard version == supportedVersion else { throw DecodeError.unsupportedVersion(version) }

        let deviceID = try readString(&reader)
        let subjectName = try readString(&reader)

        guard let frameNumber = reader.readInt32(),
              let subFrame = reader.readFloat(),
              let numerator = reader.readInt32(),
              let denominator = reader.readInt32(),
              let count = reader.readUInt8()
        else { throw DecodeError.tooShort }

        guard Int(count) == channelCount else { throw DecodeError.badChannelCount(count) }

        var values: [Float] = []
        values.reserveCapacity(channelCount)
        for _ in 0..<channelCount {
            guard let value = reader.readFloat() else { throw DecodeError.tooShort }
            guard value.isFinite else { throw DecodeError.nonFiniteValue }
            values.append(value)
        }

        return LiveLinkFacePacket(
            deviceID: deviceID,
            subjectName: subjectName,
            frameNumber: frameNumber,
            subFrame: subFrame,
            frameRateNumerator: numerator,
            frameRateDenominator: denominator,
            values: values
        )
    }

    private static func readString(_ reader: inout ByteReader) throws -> String {
        guard let length = reader.readInt32() else { throw DecodeError.tooShort }
        guard length >= 0, Int(length) <= maximumStringBytes else { throw DecodeError.badStringLength(length) }
        guard let bytes = reader.readBytes(Int(length)) else { throw DecodeError.tooShort }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Encoding

    /// The packet's wire form; `decode` of the result returns an equal packet.
    func encoded() -> Data {
        var out = Data()
        out.append(Self.supportedVersion)
        Self.appendString(deviceID, to: &out)
        Self.appendString(subjectName, to: &out)
        Self.append(frameNumber, to: &out)
        Self.append(subFrame.bitPattern, to: &out)
        Self.append(frameRateNumerator, to: &out)
        Self.append(frameRateDenominator, to: &out)
        out.append(UInt8(Self.channelCount))
        for value in values {
            Self.append(value.bitPattern, to: &out)
        }
        return out
    }

    private static func appendString(_ string: String, to data: inout Data) {
        let bytes = Array(string.utf8.prefix(maximumStringBytes))
        append(Int32(bytes.count), to: &data)
        data.append(contentsOf: bytes)
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var big = value.bigEndian
        withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }

    // MARK: - Pose

    /// True unless every channel is exactly zero, which is what the sender
    /// streams while no face is in front of it.
    var describesFace: Bool { values.contains { $0 != 0 } }

    /// The packet as a pose in the app's convention.
    ///
    /// Live Link Face reports head and eye rotation in Unreal's rotator sense:
    /// yaw positive toward the subject's right, pitch positive nose-up, roll
    /// positive with the subject's right ear dropping. `FacePose` uses Apple's
    /// right-handed face frame, so yaw and pitch flip and roll carries over.
    /// The Stage 6 on-phone pass confirms this table against a real sender —
    /// if a puppet mirrors, this is the one place to flip.
    func pose(timestamp: TimeInterval) -> FacePose {
        var pose = FacePose(values: values, timestamp: timestamp, hasFace: describesFace)
        for channel in FaceChannel.headChannels + FaceChannel.eyeChannels {
            pose[channel] *= Self.angleSign(for: channel)
        }
        return pose.clamped()
    }

    static func angleSign(for channel: FaceChannel) -> Float {
        switch channel {
        case .headYaw, .headPitch, .leftEyeYaw, .leftEyePitch, .rightEyeYaw, .rightEyePitch: -1
        default: 1
        }
    }
}

/// Sequential big-endian reader over a byte array; every read is bounds-checked.
nonisolated private struct ByteReader {
    let bytes: [UInt8]
    private(set) var offset = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var remaining: Int { bytes.count - offset }

    mutating func readUInt8() -> UInt8? {
        guard remaining >= 1 else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readInt32() -> Int32? {
        guard let raw = readUInt32() else { return nil }
        return Int32(bitPattern: raw)
    }

    mutating func readFloat() -> Float? {
        guard let raw = readUInt32() else { return nil }
        return Float(bitPattern: raw)
    }

    mutating func readBytes(_ count: Int) -> [UInt8]? {
        guard count >= 0, remaining >= count else { return nil }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    private mutating func readUInt32() -> UInt32? {
        guard remaining >= 4 else { return nil }
        defer { offset += 4 }
        return UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }
}
