import Foundation

/// An IPv4 address this phone has on a network a second iPhone could share.
nonisolated struct LocalAddress: Sendable, Hashable, Identifiable {
    nonisolated enum Kind: Sendable, Hashable, Comparable {
        case wifi
        case hotspot
        case wired
    }

    /// BSD interface name, e.g. `en0` or `bridge100`.
    var interface: String
    var address: String
    var kind: Kind

    nonisolated var id: String { interface + "|" + address }

    /// Plain wording for the sheet.
    var label: String {
        switch kind {
        case .wifi: "Wi-Fi"
        case .hotspot: "Personal Hotspot"
        case .wired: "Wired"
        }
    }
}
