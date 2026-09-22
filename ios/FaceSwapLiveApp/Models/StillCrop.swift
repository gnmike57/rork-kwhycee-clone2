import Foundation

/// Per-still live-feed crop. 1.0 is today's cover-fit; above that is tighter,
/// below it leaves empty edges the site can see.
///
/// File, photo-chooser and native-camera paths never read this.
nonisolated struct StillCrop: Codable, Equatable, Sendable {
    /// Extra zoom on top of cover-fit. 1.0 = unchanged draw.
    var zoom: Double
    /// Pan through leftover overflow, 0.5 = centred.
    var panX: Double
    var panY: Double

    /// Far enough out to show what a frame is cutting, far enough in to pick a
    /// face out of a wide shot. One range, used by every zoom surface.
    static let minZoom = 0.70
    static let maxZoom = 1.80
    /// One tap of the live zoom buttons.
    static let zoomStep = 0.05

    static func clampZoom(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(maxZoom, max(minZoom, value))
    }

    static let identity = StillCrop(zoom: 1.0, panX: 0.5, panY: 0.5)

    var isIdentity: Bool {
        zoom == 1.0 && panX == 0.5 && panY == 0.5
    }

    /// Percent shown on sliders and the live readout.
    var percent: Double { zoom * 100 }

    /// Below cover-fit the picture no longer fills the frame.
    var showsEmptyEdges: Bool { zoom < 0.999 }

    mutating func setPercent(_ percent: Double) {
        zoom = Self.clampZoom(percent / 100)
    }

    /// Lowest zoom that still cover-fits the asked frame (today's 100%).
    mutating func expandToCover() {
        zoom = 1.0
        panX = 0.5
        panY = 0.5
    }

    mutating func panBy(dx: Double, dy: Double) {
        panX = min(1, max(0, panX + dx))
        panY = min(1, max(0, panY + dy))
    }
}

/// Optional front-still smirk/smile clips prepared ahead of time. Live feed only.
nonisolated struct FacePrep: Equatable, Sendable {
    var smirkURL: URL?
    var smileURL: URL?

    static let empty = FacePrep(smirkURL: nil, smileURL: nil)

    var isReady: Bool { smirkURL != nil && smileURL != nil }
}
