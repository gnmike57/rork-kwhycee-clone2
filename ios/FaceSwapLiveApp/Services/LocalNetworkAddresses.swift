import Foundation

/// The IPv4 addresses a second iPhone on the same network can send to —
/// Wi-Fi first, then this phone's Personal Hotspot bridge. Cellular, VPN and
/// loopback interfaces are left out because packets from another phone can
/// never arrive through them.
nonisolated enum LocalNetworkAddresses {
    static func current() -> [LocalAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var found: [LocalAddress] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            cursor = entry.pointee.ifa_next

            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET)
            else { continue }

            let flags = entry.pointee.ifa_flags
            guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_LOOPBACK) == 0 else { continue }

            let interface = String(cString: entry.pointee.ifa_name)
            guard let kind = kind(forInterface: interface) else { continue }
            guard let text = numericHost(address) else { continue }

            found.append(LocalAddress(interface: interface, address: text, kind: kind))
        }

        return found.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            return lhs.interface < rhs.interface
        }
    }

    /// `en0` is Wi-Fi on every iPhone and iPad; `bridge*` is the hotspot
    /// bridge; later `en*` interfaces are USB or Ethernet adapters.
    static func kind(forInterface name: String) -> LocalAddress.Kind? {
        if name == "en0" { return .wifi }
        if name.hasPrefix("bridge") { return .hotspot }
        if name.hasPrefix("en") { return .wired }
        return nil
    }

    private static func numericHost(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        return host.withUnsafeBufferPointer { buffer -> String? in
            guard let base = buffer.baseAddress else { return nil }
            return String(cString: base)
        }
    }
}
