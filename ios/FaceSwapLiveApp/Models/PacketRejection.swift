import Foundation

/// Why a Live Link Face datagram was dropped. Shown in Diagnostics so a silent
/// listener can be told apart from a sender that is on the wrong mode.
nonisolated enum PacketRejection: String, Sendable, Equatable, CaseIterable {
    case tooShort
    case unsupportedVersion
    case badLength
    case badChannelCount
    case nonFinite
    case unrecognizedLayout
    case wrongSender

    init(_ error: LiveLinkFacePacket.DecodeError) {
        switch error {
        case .tooShort: self = .tooShort
        case .unsupportedVersion: self = .unsupportedVersion
        case .badStringLength: self = .badLength
        case .badChannelCount: self = .badChannelCount
        case .nonFiniteValue: self = .nonFinite
        case .unrecognizedLayout: self = .unrecognizedLayout
        }
    }

    var label: String {
        switch self {
        case .tooShort: "too short"
        case .unsupportedVersion: "version"
        case .badLength: "size"
        case .badChannelCount: "channel count"
        case .nonFinite: "bad value"
        case .unrecognizedLayout: "layout"
        case .wrongSender: "other sender"
        }
    }
}

/// Running totals for the Diagnostics meter. Reset when the listener restarts.
nonisolated struct PacketRejectionCounts: Equatable, Sendable {
    private var counts: [PacketRejection: Int] = [:]

    var total: Int { counts.values.reduce(0, +) }

    subscript(_ reason: PacketRejection) -> Int {
        counts[reason, default: 0]
    }

    mutating func record(_ reason: PacketRejection) {
        counts[reason, default: 0] += 1
    }

    mutating func reset() {
        counts.removeAll()
    }

    /// Compact wording, empty when nothing has been dropped.
    var summary: String {
        guard total > 0 else { return "None" }
        return PacketRejection.allCases.compactMap { reason in
            let count = self[reason]
            return count > 0 ? "\(reason.label) \(count)" : nil
        }.joined(separator: " · ")
    }
}
