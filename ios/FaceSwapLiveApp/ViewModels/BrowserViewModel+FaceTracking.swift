import Foundation

extension BrowserViewModel {
    /// A still is being drawn into a feed the page is actively pulling — the
    /// only time face tracking has anything to animate. A video in the slot,
    /// the real camera, or a page with no open feed all read false.
    ///
    /// Reads the page's status pings, which only flow while the pill or the
    /// observed HUD is switched on; Stage 3 gives the still-feed draw its own
    /// signal so this holds with both hidden.
    var stillOnActiveFeed: Bool {
        guard isLiveStreamActive, let facing = activeStreamFacing else { return false }
        let slot = facing == .back ? backQueueIndex : frontQueueIndex
        return isStill(facing: facing, slot: slot)
    }
}
