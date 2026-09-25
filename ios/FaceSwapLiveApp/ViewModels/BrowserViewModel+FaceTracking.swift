import Foundation

extension BrowserViewModel {
    /// A still is being drawn into a feed the page is actively pulling — the
    /// only time face tracking has anything to animate. A video in the slot,
    /// the real camera, or a page with no open feed all read false.
    ///
    /// Status pings only flow while the pill or the observed HUD is on. The
    /// living-still draw also reads the page's existing picture, so this holds
    /// with both hidden. No new page names are added.
    var stillOnActiveFeed: Bool {
        if isLiveStreamActive, let facing = activeStreamFacing {
            let slot = facing == .back ? backQueueIndex : frontQueueIndex
            if isStill(facing: facing, slot: slot) { return true }
        }
        if let feed = livingFeed, isStill(facing: feed.facing, slot: feed.slot) {
            return true
        }
        return false
    }
}
