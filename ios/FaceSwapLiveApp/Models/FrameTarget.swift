import CoreGraphics
import Foundation

/// Where a frame size came from, so the preview can say so honestly.
nonisolated enum FrameTargetOrigin: Equatable, Sendable {
    /// The site asked for a size; `asked` is what it typed, which the audited
    /// camera may have answered with something else.
    case siteRequest(asked: String)
    /// The site did not ask, so the camera's own default frame is used.
    case cameraDefault(camera: String)
    /// One of the other sizes the audit saw this camera grant.
    case auditedMode(camera: String)
    /// One of the sizes sites really ask for, offered before any request.
    case commonRequest
    /// Picked by hand in the Frame Check editor.
    case custom
    /// No audit sheet and no ask: the page's own fallback frame.
    case fallback
}

/// The exact pixel frame a live feed will report and draw into.
///
/// Every Frame Check surface renders against one of these, so the picture the
/// user approves is shaped to the very size the page's canvas will be.
nonisolated struct FrameTarget: Equatable, Sendable, Hashable {
    var width: Int
    var height: Int
    var origin: FrameTargetOrigin

    var size: CGSize { CGSize(width: width, height: height) }

    var aspect: Double {
        height == 0 ? 16.0 / 9.0 : Double(width) / Double(height)
    }

    var isPortrait: Bool { height > width }

    var sizeText: String { "\(width)×\(height)" }

    /// The framing bucket this frame belongs to. Two frames of the same shape
    /// share one framing, so 1920×1080 and 1280×720 need setting up only once.
    var shape: FrameShape { FrameShape.of(width: width, height: height) }

    /// True when this is one of the sizes sites really ask for.
    var isCommonRequest: Bool { CommonFrames.isCommon(width: width, height: height) }

    /// Short caption for the size pill on the preview.
    var originText: String {
        switch origin {
        case .siteRequest(let asked):
            return asked == sizeText ? "Site asked" : "Asked \(asked)"
        case .cameraDefault(let camera):
            return "\(Self.shortCameraName(camera)) default"
        case .auditedMode(let camera):
            return "\(Self.shortCameraName(camera)) camera size"
        case .commonRequest:
            return "Most asked"
        case .custom:
            return "Custom"
        case .fallback:
            return "Default frame"
        }
    }

    /// "Front Camera" reads as "Front" on a pill that is already inside that
    /// camera's own card.
    private static func shortCameraName(_ label: String) -> String {
        let lowered = label.lowercased()
        if lowered.contains("front") { return "Front" }
        if lowered.contains("back") { return "Back" }
        return label
    }

    /// One line for pickers and the editor title.
    var menuText: String {
        switch origin {
        case .siteRequest(let asked):
            return asked == sizeText ? "\(sizeText) · site asked" : "\(sizeText) · asked \(asked)"
        case .cameraDefault(let camera):
            return "\(sizeText) · \(camera) default"
        case .auditedMode(let camera):
            return "\(sizeText) · \(camera) grants this"
        case .commonRequest:
            return "\(sizeText) · most sites ask for this"
        case .custom:
            return "\(sizeText) · custom"
        case .fallback:
            return "\(sizeText) · default"
        }
    }

    static func custom(width: Int, height: Int) -> FrameTarget {
        FrameTarget(width: max(1, width), height: max(1, height), origin: .custom)
    }

    static let fallback = FrameTarget(width: 1280, height: 720, origin: .fallback)

    func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
    }

    static func == (lhs: FrameTarget, rhs: FrameTarget) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.origin == rhs.origin
    }
}

/// Opens the full-screen Frame Check editor on one loaded still.
nonisolated struct FrameCheckRequest: Identifiable, Sendable, Equatable {
    let id: UUID
    var facing: BrowserViewModel.CameraFacing
    var slot: Int
    /// Preselected frame; `nil` means the camera's default for that facing.
    var target: FrameTarget?
    /// Start AI Expand as soon as the editor opens (the card's Expand button).
    var autoExpand: Bool

    init(facing: BrowserViewModel.CameraFacing, slot: Int, target: FrameTarget? = nil, autoExpand: Bool = false) {
        self.id = UUID()
        self.facing = facing
        self.slot = slot
        self.target = target
        self.autoExpand = autoExpand
    }
}
