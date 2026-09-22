import Foundation

/// Which path a site used to ask for media.
nonisolated enum MediaRequestKind: String, Sendable {
    /// A live camera feed via `getUserMedia`.
    case live
    /// A photo/file input. The prompt only picks which item goes out; the item itself
    /// is never altered.
    case file

    nonisolated var title: String {
        switch self {
        case .live: "Camera request"
        case .file: "File request"
        }
    }

    nonisolated var icon: String {
        switch self {
        case .live: "video.fill"
        case .file: "photo.on.rectangle.angled"
        }
    }
}

/// A single site request waiting on the user, parsed from the injected page.
nonisolated struct MediaRequestPrompt: Sendable, Identifiable {
    var id: Int
    var kind: MediaRequestKind
    var host: String
    var pageURL: String

    /// What the site asked for, already flattened out of the constraint object.
    var requestedFacing: String?
    var requestedWidth: Int?
    var requestedHeight: Int?
    var requestedFrameRate: Double?
    var wantsAudio: Bool
    /// `accept` attribute for file requests.
    var accept: String?

    /// Facing the request will be served from unless the user changes it.
    var resolvedFacing: BrowserViewModel.CameraFacing

    var requestedSizeText: String {
        guard let width = requestedWidth, let height = requestedHeight else { return "Any size" }
        return "\(width)×\(height)"
    }

    var requestedFrameRateText: String {
        guard let fps = requestedFrameRate else { return "Any rate" }
        return "\(Int(fps.rounded())) fps"
    }

    var requestedFacingText: String {
        switch requestedFacing {
        case "environment": "Back"
        case "user": "Front"
        default: "Unspecified"
        }
    }
}

/// What the user decided, sent back into the page.
nonisolated struct MediaRequestDecision: Sendable {
    var facing: BrowserViewModel.CameraFacing?
    var slot: Int?
    var cancelled: Bool

    static let proceed = MediaRequestDecision(facing: nil, slot: nil, cancelled: false)

    /// JavaScript object literal handed to the waiting page.
    var jsLiteral: String {
        var parts: [String] = ["cancel:\(cancelled)"]
        if let facing {
            parts.append("facing:'\(facing == .back ? "environment" : "user")'")
        }
        if let slot {
            parts.append("slot:\(slot)")
        }
        return "{\(parts.joined(separator: ","))}"
    }
}
