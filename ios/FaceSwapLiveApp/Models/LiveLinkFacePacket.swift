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
        case unrecognizedLayout
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

    /// Parses a datagram. Layout B (length-prefixed device ID, what Live Link
    /// Face sends today) is tried first. If that fails and the bytes look like
    /// the older fixed 36-character device ID, layout A is tried. Anything
    /// short, from another version, or carrying an impossible length, count or
    /// value is rejected rather than guessed at.
    static func decode(_ data: Data) throws -> LiveLinkFacePacket {
        guard let version = data.first else { throw DecodeError.tooShort }
        guard version == supportedVersion else { throw DecodeError.unsupportedVersion(version) }

        do {
            return try decodeLayoutB(data)
        } catch let layoutBError as DecodeError {
            if let packet = try? decodeLayoutA(data) {
                return packet
            }
            if case .badStringLength = layoutBError, looksLikeLayoutAPrefix(data) {
                throw DecodeError.unrecognizedLayout
            }
            throw layoutBError
        }
    }

    /// Length-prefixed device ID, then subject, frame time, count and values.
    private static func decodeLayoutB(_ data: Data) throws -> LiveLinkFacePacket {
        var reader = ByteReader(bytes: [UInt8](data))
        guard reader.readUInt8() != nil else { throw DecodeError.tooShort }

        let deviceID = try readString(&reader)
        let subjectName = try readString(&reader)
        return try readFrame(deviceID: deviceID, subjectName: subjectName, reader: &reader)
    }

    /// Older published layout: a fixed 36-character device ID, no length prefix.
    private static func decodeLayoutA(_ data: Data) throws -> LiveLinkFacePacket {
        var reader = ByteReader(bytes: [UInt8](data))
        guard reader.readUInt8() != nil else { throw DecodeError.tooShort }
        guard let uuidBytes = reader.readBytes(36), isUUID(uuidBytes) else {
            throw DecodeError.unrecognizedLayout
        }
        let deviceID = String(decoding: uuidBytes, as: UTF8.self)
        let subjectName = try readString(&reader)
        return try readFrame(deviceID: deviceID, subjectName: subjectName, reader: &reader)
    }

    private static func readFrame(
        deviceID: String,
        subjectName: String,
        reader: inout ByteReader
    ) throws -> LiveLinkFacePacket {
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

    /// True when the bytes after the version look like a 36-character device ID.
    private static func looksLikeLayoutAPrefix(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 37 else { return false }
        return isUUID(Array(bytes[1..<37]))
    }

    private static func isUUID(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 36 else { return false }
        let dashIndexes: Set<Int> = [8, 13, 18, 23]
        for index in bytes.indices {
            let byte = bytes[index]
            if dashIndexes.contains(index) {
                if byte != UInt8(ascii: "-") { return false }
            } else if !isHex(byte) {
                return false
            }
        }
        return true
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
            || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "f"))
            || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "F"))
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

    /// False when Stream Head Rotation is off: those three angles arrive as
    /// exact zeros, which is not the same as a face looking straight ahead.
    var includesHeadPose: Bool {
        FaceChannel.headChannels.contains { values[$0.rawValue] != 0 }
    }

    /// Sender frame time in seconds, when the packet carries a usable rate.
    var qualifiedSeconds: TimeInterval? {
        guard frameRateDenominator > 0, frameRateNumerator > 0 else { return nil }
        let fps = Double(frameRateNumerator) / Double(frameRateDenominator)
        guard fps > 0, fps.isFinite else { return nil }
        let seconds = (Double(frameNumber) + Double(subFrame)) / fps
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }

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
