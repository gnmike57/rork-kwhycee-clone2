import Foundation

/// One line in the pipeline tail: a page-side failure, a watchdog repair or a
/// quiet reload, timestamped and tagged with the site it happened on.
nonisolated struct PipelineEvent: Identifiable, Sendable, Equatable {
    nonisolated enum Kind: String, Sendable {
        case error
        case repair
        case info
    }

    let id: UUID
    let date: Date
    let site: String
    let kind: Kind
    let message: String

    init(site: String, kind: Kind, message: String) {
        id = UUID()
        date = Date()
        self.site = site
        self.kind = kind
        self.message = message
    }
}

/// One heartbeat's answer about the injected pipeline.
///
/// Every field is a plain comparison the page makes against references it
/// captured when it installed its own hooks. The answer travels over the
/// state accessor behind its token; nothing here is readable by the page and
/// nothing is observable from outside the app.
nonisolated struct PipelineHealth: Sendable, Equatable {
    var feedActive: Bool
    var getUserMediaHooked: Bool
    var enumerateDevicesHooked: Bool
    var clickHooked: Bool
    var liveFeed: Bool
    var frozen: Bool
    var loopIdleMs: Int
    var hardened: Bool

    /// True when a hook the page should still be holding has gone missing.
    ///
    /// The feed-loop age is deliberately left out of this decision: a
    /// backgrounded page stops scheduling frames and a paused clip ends its
    /// draw loop by design, so a stale tick is normal and must never read as
    /// a failure. It is reported for the Diagnostics tail only.
    var hasDroppedHook: Bool {
        guard feedActive else { return false }
        return !getUserMediaHooked || !enumerateDevicesHooked || !clickHooked
    }
}

/// What the indicator dot shows.
nonisolated enum PipelineIndicator: Sendable {
    case flowing
    case silent
    case lost
    case off

    nonisolated var label: String {
        switch self {
        case .flowing: "Feed flowing"
        case .silent: "Waiting for the page"
        case .lost: "Hooks lost"
        case .off: "No media"
        }
    }
}

/// Live tail of injection-pipeline events, shown in Diagnostics.
///
/// Entries are in memory only (latest first, capped), so nothing about a
/// site's pipeline history survives a relaunch.
@Observable
@MainActor
final class PipelineLogStore {
    private(set) var events: [PipelineEvent] = []

    private let cap = 200

    func add(kind: PipelineEvent.Kind, site: String, _ message: String) {
        events.insert(PipelineEvent(site: site, kind: kind, message: message), at: 0)
        if events.count > cap {
            events.removeLast(events.count - cap)
        }
    }

    func addError(site: String, _ message: String) { add(kind: .error, site: site, message) }
    func addRepair(site: String, _ message: String) { add(kind: .repair, site: site, message) }
    func addInfo(site: String, _ message: String) { add(kind: .info, site: site, message) }

    func clear() { events.removeAll() }
}
