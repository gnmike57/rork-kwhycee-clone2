import CoreGraphics
import Foundation

/// The one-line answer Frame Check gives about a still in a frame.
nonisolated struct FrameVerdict: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Almost nothing is lost.
        case fits
        /// A moderate amount is cut, or the face sits badly.
        case recentre
        /// The shape is too different to crop cleanly.
        case expand
    }

    enum Action: Equatable, Sendable, Identifiable {
        case centreOnFace
        case autoFit
        case expandWithAI
        case recentre

        var id: String { title }

        var title: String {
            switch self {
            case .centreOnFace: "Centre on face"
            case .autoFit: "Auto-fit"
            case .expandWithAI: "Expand with AI"
            case .recentre: "Recentre"
            }
        }

        var systemImage: String {
            switch self {
            case .centreOnFace: "person.crop.square"
            case .autoFit: "arrow.down.right.and.arrow.up.left.square"
            case .expandWithAI: "wand.and.sparkles"
            case .recentre: "scope"
            }
        }
    }

    enum Warning: Equatable, Sendable, Identifiable {
        /// The still is smaller than the frame; `factor` is frame px per still px.
        case upscaled(factor: Double)
        /// Zoom below cover-fit leaves part of the frame empty.
        case emptyEdges(fraction: Double)

        var id: String {
            switch self {
            case .upscaled: "upscaled"
            case .emptyEdges: "emptyEdges"
            }
        }

        var text: String {
            switch self {
            case .upscaled(let factor):
                return "Will be upscaled \(String(format: "%.1f", factor))×, will look soft."
            case .emptyEdges(let fraction):
                return "Empty edges visible to the site (\(Int((fraction * 100).rounded()))% of the frame)."
            }
        }
    }

    var kind: Kind
    var reason: String
    var actions: [Action]
    var warnings: [Warning]

    var needsAttention: Bool { kind != .fits }

    var title: String {
        switch kind {
        case .fits: "Fits"
        case .recentre: "Recentre or crop"
        case .expand: "Expand with AI"
        }
    }
}

/// How one still stands against one frame, for the at-a-glance readiness row.
nonisolated struct FrameReadiness: Equatable, Sendable, Identifiable {
    var target: FrameTarget
    var kind: FrameVerdict.Kind

    var id: String { target.sizeText }

    var systemImage: String {
        switch kind {
        case .fits: "checkmark"
        case .recentre: "exclamationmark"
        case .expand: "wand.and.sparkles"
        }
    }

    /// Read out for accessibility, where a coloured tick says nothing.
    var spokenSummary: String {
        switch kind {
        case .fits: "\(target.sizeText) fits"
        case .recentre: "\(target.sizeText) needs a nudge"
        case .expand: "\(target.sizeText) needs expanding"
        }
    }
}

/// Scores a still against a frame. Pure: geometry in, verdict out.
nonisolated enum FrameVerdictEngine {

    /// Below this share of the photo lost, the still simply fits.
    static let fitsBelow = 0.12
    /// From this share lost, cropping is no longer clean and expansion wins.
    static let expandFrom = 0.33
    /// Face centre further than this from the frame centre reads as off-centre.
    static let offCentreBeyond = 0.16
    /// Frame px per still px from which the stretch becomes visible.
    static let upscaleWarnFrom = 1.35

    /// - Parameters:
    ///   - shape: motion off, current crop — how the shape itself fits. The
    ///     hand-held bake margin is a deliberate cost, so it is never blamed on
    ///     the photo.
    ///   - shapeAtCover: motion off, no crop — the untouched fit.
    ///   - live: motion as the feed runs it, current crop — what the site sees.
    ///     Face safety and the warnings are judged against this one.
    static func evaluate(
        shape: FrameGeometry,
        shapeAtCover: FrameGeometry,
        live: FrameGeometry,
        face: FaceBox?,
        isPanned: Bool
    ) -> FrameVerdict {
        var warnings: [FrameVerdict.Warning] = []
        if live.drawScale >= upscaleWarnFrom {
            warnings.append(.upscaled(factor: live.drawScale))
        }
        if live.showsEmptyEdges {
            warnings.append(.emptyEdges(fraction: 1 - live.coverage))
        }

        let lost = shape.lostFraction
        let lostAtCover = shapeAtCover.lostFraction
        let lostPercent = Int((lost * 100).rounded())
        let coverPercent = Int((lostAtCover * 100).rounded())

        let faceCut = face.map(live.faceIsCut) ?? false
        let faceTouches = face.map(live.faceTouchesEdge) ?? false
        let faceFits = face.map(live.faceFitsAtSomePan) ?? true
        let offset = face.map(live.faceOffset) ?? .zero
        let faceOff = abs(offset.width) > offCentreBeyond || abs(offset.height) > offCentreBeyond

        // Expand: the shape itself is the problem, not the framing.
        if faceCut && !faceFits {
            return FrameVerdict(
                kind: .expand,
                reason: "The face can’t be kept inside this frame at any pan.",
                actions: [.expandWithAI],
                warnings: warnings
            )
        }
        let mismatch = shapeAtCover.orientationMismatch
        if lostAtCover >= expandFrom || mismatch {
            let shapeText: String
            if mismatch {
                shapeText = live.canvas.width >= live.canvas.height
                    ? "Portrait photo into a landscape frame"
                    : "Landscape photo into a portrait frame"
            } else {
                shapeText = "Too much to crop cleanly"
            }
            let detail: String
            if lost >= fitsBelow {
                detail = "\(lostPercent)% of the photo is cut."
            } else if live.showsEmptyEdges {
                detail = "it only fits by leaving empty edges."
            } else {
                detail = "\(coverPercent)% would be cut at cover-fit."
            }
            var actions: [FrameVerdict.Action] = [.expandWithAI]
            if face != nil { actions.append(.autoFit) }
            return FrameVerdict(
                kind: .expand,
                reason: "\(shapeText): \(detail)",
                actions: actions,
                warnings: warnings
            )
        }

        // Recentre or crop: moderate loss, or the face sits badly.
        var reasons: [String] = []
        if lost > fitsBelow {
            reasons.append("\(lostPercent)% of the photo is cut")
        }
        if face != nil {
            if faceCut {
                reasons.append("the face is partly cut off")
            } else if faceTouches {
                reasons.append("the face touches the motion edge")
            }
            if faceOff && !faceCut {
                reasons.append("the face sits off-centre")
            }
        }
        if !reasons.isEmpty {
            var actions: [FrameVerdict.Action] = []
            if face != nil {
                actions = [.centreOnFace, .autoFit]
            } else if isPanned || shape.crop != nil {
                actions = [.autoFit]
            } else {
                actions = [.expandWithAI]
            }
            let sentence = reasons.joined(separator: "; ")
            let reason = sentence.prefix(1).uppercased() + String(sentence.dropFirst()) + "."
            return FrameVerdict(kind: .recentre, reason: reason, actions: actions, warnings: warnings)
        }

        let reason: String
        if lostPercent > 0 {
            reason = "Fits. \(lostPercent)% trimmed at the edges."
        } else if live.lostFraction > 0.01 {
            reason = "Fits. Only the motion edge is trimmed."
        } else {
            reason = "Fits. Nothing trimmed."
        }
        return FrameVerdict(kind: .fits, reason: reason, actions: [], warnings: warnings)
    }
}
