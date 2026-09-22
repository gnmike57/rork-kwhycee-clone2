import Foundation
import UIKit

/// Per-still facts Frame Check learns once and reuses: the main face, and the
/// untouched original behind a device-converted front still.
///
/// Entries are keyed by the still's object identity and hold it weakly, so a
/// still that is replaced or cleared simply stops matching — no slot
/// bookkeeping, and Swap or Promote can never point a face at the wrong photo.
@Observable
@MainActor
final class FrameCheckCache {
    final class Entry {
        weak var image: UIImage?
        var face: FaceBox?
        var faceSearched: Bool = false
        var faceSearching: Bool = false
        /// The search in flight, so a second caller waits on it instead of
        /// starting the same work again.
        var faceTask: Task<FaceBox?, Never>?
        /// The photo as imported, reduced, when the stored still is a device
        /// conversion of it. AI Expand starts from this so nothing the
        /// conversion cut has to be invented.
        var original: UIImage?

        init(image: UIImage) {
            self.image = image
        }
    }

    private(set) var entries: [ObjectIdentifier: Entry] = [:]

    private func entry(for image: UIImage) -> Entry {
        let key = ObjectIdentifier(image)
        if let existing = entries[key], existing.image === image {
            return existing
        }
        prune()
        let fresh = Entry(image: image)
        entries[key] = fresh
        return fresh
    }

    private func lookup(_ image: UIImage) -> Entry? {
        guard let existing = entries[ObjectIdentifier(image)], existing.image === image else { return nil }
        return existing
    }

    private func prune() {
        entries = entries.filter { $0.value.image != nil }
    }

    /// Bumps observation so views re-read after a background result lands.
    private func touch() {
        entries = entries
    }

    func face(for image: UIImage) -> FaceBox? {
        lookup(image)?.face
    }

    func hasSearchedFace(for image: UIImage) -> Bool {
        lookup(image)?.faceSearched ?? false
    }

    func original(for image: UIImage) -> UIImage? {
        lookup(image)?.original
    }

    func setOriginal(_ original: UIImage?, for image: UIImage) {
        entry(for: image).original = original
        touch()
    }

    /// Finds the face once per still. Safe to call from any view's `.task`.
    func ensureFace(for image: UIImage, using finder: FaceFinder) {
        guard !hasSearchedFace(for: image) else { return }
        Task { [weak self] in
            _ = await self?.resolveFace(for: image, using: finder)
        }
    }

    /// The face, waiting for a search already under way rather than starting a
    /// second one. Used by import preparation, which cannot frame a photo until
    /// it knows where the face is.
    func resolveFace(for image: UIImage, using finder: FaceFinder) async -> FaceBox? {
        let entry = entry(for: image)
        if entry.faceSearched { return entry.face }
        if let running = entry.faceTask { return await running.value }

        let task = Task { await finder.findFace(in: image) }
        entry.faceTask = task
        entry.faceSearching = true
        let face = await task.value
        entry.face = face
        entry.faceSearched = true
        entry.faceSearching = false
        entry.faceTask = nil
        touch()
        return face
    }
}

/// The page's look switches, as the preview must replay them.
nonisolated struct FramePreviewLook: Equatable, Sendable {
    var liveMotion: Bool
    var motionK: Double
    var grain: Bool
    var warmth: Bool
    var exposure: Bool

    /// Motion strength, or `nil` when the feed does not move.
    var motionKIfOn: Double? { liveMotion ? motionK : nil }

    static let still = FramePreviewLook(liveMotion: false, motionK: 1, grain: false, warmth: false, exposure: false)
}

extension BrowserViewModel {

    // MARK: - Targets

    /// The frame this ask will really be drawn into, with where that came from.
    ///
    /// Numbers come from `previewCanvasSize`, so the pill's "Sending" text and
    /// the preview can never disagree.
    func frameTarget(prompt: MediaRequestPrompt, facing: CameraFacing) -> FrameTarget {
        let size = previewCanvasSize(prompt: prompt, facing: facing)
        let asked = prompt.requestedWidth != nil || prompt.requestedHeight != nil
        if asked {
            let askedText: String
            switch (prompt.requestedWidth, prompt.requestedHeight) {
            case let (w?, h?): askedText = "\(w)×\(h)"
            case let (w?, nil): askedText = "\(w)×—"
            case let (nil, h?): askedText = "—×\(h)"
            default: askedText = "Any size"
            }
            return FrameTarget(width: size.0, height: size.1, origin: .siteRequest(asked: askedText))
        }
        return defaultFrameTarget(facing: facing, size: size)
    }

    /// The frame a site that asks for nothing gets from this camera.
    func defaultFrameTarget(facing: CameraFacing) -> FrameTarget {
        let camera = facing == .front ? behavior.audit.primaryFront : behavior.audit.primaryBack
        if let camera {
            return FrameTarget(
                width: camera.defaultMode.width,
                height: camera.defaultMode.height,
                origin: .cameraDefault(camera: camera.label)
            )
        }
        return .fallback
    }

    private func defaultFrameTarget(facing: CameraFacing, size: (Int, Int)) -> FrameTarget {
        let camera = facing == .front ? behavior.audit.primaryFront : behavior.audit.primaryBack
        if let camera {
            return FrameTarget(width: size.0, height: size.1, origin: .cameraDefault(camera: camera.label))
        }
        return FrameTarget(width: size.0, height: size.1, origin: .fallback)
    }

    /// Frames worth preparing for on this camera.
    ///
    /// The three sizes sites really ask for come first, then this camera's own
    /// default, then every other size the audit saw it grant.
    func frameTargetChoices(facing: CameraFacing) -> [FrameTarget] {
        var out: [FrameTarget] = CommonFrames.targets
        func add(_ candidate: FrameTarget, at index: Int? = nil) {
            guard !out.contains(where: { $0.width == candidate.width && $0.height == candidate.height }) else { return }
            if let index { out.insert(candidate, at: index) } else { out.append(candidate) }
        }
        add(defaultFrameTarget(facing: facing))
        let camera = facing == .front ? behavior.audit.primaryFront : behavior.audit.primaryBack
        if let camera {
            for mode in camera.modes {
                add(FrameTarget(width: mode.width, height: mode.height, origin: .auditedMode(camera: camera.label)))
            }
        }
        if let prompt = pendingPrompt ?? lastPromptAsk, prompt.kind == .live {
            // A live ask outranks everything: it is the frame in play right now.
            let asked = frameTarget(prompt: prompt, facing: facing)
            add(asked, at: 0)
        }
        return out
    }

    /// The frame a slot should be judged and framed against by default: the one
    /// a site is asking for right now, else the running feed's own canvas, else
    /// the camera's default.
    func workingFrameTarget(facing: CameraFacing) -> FrameTarget {
        if let prompt = pendingPrompt, prompt.kind == .live {
            return frameTarget(prompt: prompt, facing: facing)
        }
        if isLiveStreamActive, activeStreamFacing == facing, let size = liveFrameSize,
           size.width > 0, size.height > 0 {
            return FrameTarget(width: Int(size.width), height: Int(size.height), origin: .commonRequest)
        }
        return defaultFrameTarget(facing: facing)
    }

    // MARK: - Look and crop as the page applies them

    var framePreviewLook: FramePreviewLook {
        let s = behavior.settings
        return FramePreviewLook(
            liveMotion: s.liveMotion,
            motionK: s.motionStrength.multiplier,
            grain: s.sensorGrain,
            warmth: s.skinRealism,
            exposure: s.exposureBreathing
        )
    }

    /// The crop the page will actually read for one frame shape: `nil` mirrors
    /// `stillCropFor` returning `null` — switch off, or identity.
    func effectiveCrop(facing: CameraFacing, slot: Int, shape: FrameShape) -> StillCrop? {
        guard behavior.settings.liveStillCrop else { return nil }
        let crop = stillCrop(facing: facing, slot: slot, shape: shape)
        return crop.isIdentity ? nil : crop
    }

    /// The crop in play for the shape being asked for right now.
    func effectiveCrop(facing: CameraFacing, slot: Int) -> StillCrop? {
        effectiveCrop(facing: facing, slot: slot, shape: activeFrameShape(facing: facing))
    }

    /// Pixel size the page's `naturalWidth/Height` will report for this still.
    nonisolated static func pixelSize(of image: UIImage) -> CGSize {
        CGSize(
            width: (image.size.width * image.scale).rounded(),
            height: (image.size.height * image.scale).rounded()
        )
    }

    func frameGeometry(image: UIImage, target: FrameTarget, crop: StillCrop?) -> FrameGeometry {
        FrameGeometry(
            canvas: target.size,
            image: Self.pixelSize(of: image),
            crop: crop,
            motionK: framePreviewLook.motionKIfOn
        )
    }

    // MARK: - Faces

    func frameFace(for image: UIImage) -> FaceBox? {
        frameCache.face(for: image)
    }

    func ensureFrameFace(for image: UIImage) {
        frameCache.ensureFace(for: image, using: faceFinder)
    }

    // MARK: - Verdicts

    /// Scores one loaded still against a frame. `nil` when the slot is not a still.
    func frameVerdict(facing: CameraFacing, slot: Int, target: FrameTarget) -> FrameVerdict? {
        guard isStill(facing: facing, slot: slot), let image = previewImage(facing: facing, slot: slot) else {
            return nil
        }
        let crop = effectiveCrop(facing: facing, slot: slot, shape: target.shape)
        let pixels = Self.pixelSize(of: image)
        let shape = FrameGeometry(canvas: target.size, image: pixels, crop: crop, motionK: nil)
        let shapeAtCover = crop == nil
            ? shape
            : FrameGeometry(canvas: target.size, image: pixels, crop: nil, motionK: nil)
        let live = frameGeometry(image: image, target: target, crop: crop)
        let stored = stillCrop(facing: facing, slot: slot, shape: target.shape)
        return FrameVerdictEngine.evaluate(
            shape: shape,
            shapeAtCover: shapeAtCover,
            live: live,
            face: frameFace(for: image),
            isPanned: stored.panX != 0.5 || stored.panY != 0.5
        )
    }

    /// How one slot stands against every frame sites really ask for, plus this
    /// camera's own default — the row shown under each item in My Media.
    func frameReadiness(facing: CameraFacing, slot: Int) -> [FrameReadiness] {
        guard sourceType(facing: facing, slot: slot) != nil else { return [] }
        var targets = CommonFrames.targets
        let fallback = defaultFrameTarget(facing: facing)
        if !targets.contains(where: { $0.shape == fallback.shape }) {
            targets.append(fallback)
        }
        if isStill(facing: facing, slot: slot) {
            return targets.compactMap { target in
                guard let verdict = frameVerdict(facing: facing, slot: slot, target: target) else { return nil }
                return FrameReadiness(target: target, kind: verdict.kind)
            }
        }
        guard let size = videoSize(facing: facing, slot: slot) else { return [] }
        return targets.map { target in
            FrameReadiness(target: target, kind: Self.clipReadiness(clip: size, target: target))
        }
    }

    /// How a clip sits in a frame.
    ///
    /// A video is drawn cover-fit and centred with no stored framing, so the
    /// only question is how much of it the frame cuts — which is the shape
    /// judgement the still engine already makes, with no crop and no motion.
    nonisolated static func clipReadiness(clip: CGSize, target: FrameTarget) -> FrameVerdict.Kind {
        let geometry = FrameGeometry(canvas: target.size, image: clip, crop: nil, motionK: nil)
        if geometry.orientationMismatch { return .expand }
        let lost = geometry.lostFraction
        if lost >= FrameVerdictEngine.expandFrom { return .expand }
        if lost > FrameVerdictEngine.fitsBelow { return .recentre }
        return .fits
    }

    /// The import check: does this still need a look before a site asks?
    ///
    /// Judged against every frame sites really ask for as well as the camera's
    /// own default, so the badge matches what a site will really request. The
    /// worst answer wins — one frame that cannot be cropped is worth flagging
    /// even when the others are clean.
    func frameNeedsAttention(facing: CameraFacing, slot: Int) -> FrameVerdict.Kind? {
        let readiness = frameReadiness(facing: facing, slot: slot)
        guard !readiness.isEmpty else { return nil }
        if readiness.contains(where: { $0.kind == .expand }) { return .expand }
        if readiness.contains(where: { $0.kind == .recentre }) { return .recentre }
        return nil
    }

    // MARK: - Actions

    /// Applies a crop to one frame shape's framing. Turns the crop switch on
    /// when it was off, because a crop the feed never reads would be a lie in
    /// the preview.
    func applyFrameCrop(_ crop: StillCrop, facing: CameraFacing, slot: Int, shape: FrameShape) {
        if !behavior.settings.liveStillCrop {
            behavior.settings.liveStillCrop = true
            applyBehaviorSettings()
        }
        setStillCrop(crop, facing: facing, slot: slot, shape: shape)
    }

    func performFrameAction(
        _ action: FrameVerdict.Action,
        facing: CameraFacing,
        slot: Int,
        target: FrameTarget
    ) {
        guard let image = previewImage(facing: facing, slot: slot) else { return }
        let shape = target.shape
        let current = stillCrop(facing: facing, slot: slot, shape: shape)
        let geometry = frameGeometry(
            image: image,
            target: target,
            crop: effectiveCrop(facing: facing, slot: slot, shape: shape)
        )
        switch action {
        case .recentre:
            applyFrameCrop(
                StillCrop(zoom: current.zoom, panX: 0.5, panY: 0.5),
                facing: facing, slot: slot, shape: shape
            )
        case .centreOnFace:
            guard let face = frameFace(for: image) else { return }
            applyFrameCrop(
                geometry.cropCentering(on: face, keeping: current),
                facing: facing, slot: slot, shape: shape
            )
        case .autoFit:
            applyFrameCrop(
                geometry.cropAutoFitting(frameFace(for: image)),
                facing: facing, slot: slot, shape: shape
            )
        case .expandWithAI:
            // Started by the editor, which owns the review step.
            break
        }
    }

    // MARK: - AI Expand

    /// The photo AI Expand should start from: the import behind a converted
    /// front still when it is known, otherwise the still itself.
    func frameExpandSource(facing: CameraFacing, slot: Int) -> UIImage? {
        guard let image = previewImage(facing: facing, slot: slot) else { return nil }
        return frameCache.original(for: image) ?? image
    }

    /// Runs the expansion. The result is handed back, never loaded on its own.
    func expandFrame(facing: CameraFacing, slot: Int, target: FrameTarget) async throws -> UIImage {
        guard let source = frameExpandSource(facing: facing, slot: slot) else {
            throw FrameExpandError.imageUnreadable
        }
        return try await frameExpander.expand(source, to: target)
    }

    /// Loads an approved expansion into a slot as an ordinary still.
    ///
    /// The picture is already exactly the frame it was made for, so the
    /// device-size cover-crop is skipped — re-cropping would undo the
    /// expansion. Metadata stamping and every later step are unchanged.
    func useExpandedFrame(_ image: UIImage, facing: CameraFacing, slot: SequenceSlot) {
        loadSource(image: image, facing: facing, slot: slot, preparedForFrame: true)
    }

    // MARK: - Import preparation

    /// Frames a freshly imported still for the sizes sites really ask for.
    ///
    /// Only a frame the photo already lands in cleanly is framed: anything that
    /// would need AI Expand is left untouched and flagged instead, so that
    /// decision stays with the user. Framing the user has already set is never
    /// overwritten, and everything applied here is undone in one tap from
    /// Frame Check.
    func autoPrepareFraming(facing: CameraFacing, slot: Int) {
        guard isStill(facing: facing, slot: slot),
              let image = previewImage(facing: facing, slot: slot) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let face = await self.frameCache.resolveFace(for: image, using: self.faceFinder)
            // Finding the face takes a moment, in which the slot may have been
            // replaced, cleared or swapped. Identity settles it.
            guard self.previewImage(facing: facing, slot: slot) === image else { return }
            guard face != nil else { return }

            var targets = CommonFrames.targets
            let fallback = self.defaultFrameTarget(facing: facing)
            if !targets.contains(where: { $0.shape == fallback.shape }) {
                targets.append(fallback)
            }

            var done: Set<FrameShape> = []
            for target in targets {
                let shape = target.shape
                guard done.insert(shape).inserted else { continue }
                // Never overwrite framing that is already there.
                guard self.stillCrop(facing: facing, slot: slot, shape: shape).isIdentity else { continue }
                guard let verdict = self.frameVerdict(facing: facing, slot: slot, target: target) else { continue }
                // A shape too different to crop cleanly is the user's call.
                guard verdict.kind == .recentre else { continue }

                let crop = self.frameGeometry(image: image, target: target, crop: nil).cropAutoFitting(face)
                guard !crop.isIdentity else { continue }
                self.applyFrameCrop(crop, facing: facing, slot: slot, shape: shape)
            }
        }
    }

    /// Remembers the import behind a converted still and starts its face search.
    func noteFrameImport(stored: UIImage, original: UIImage?) {
        if let original, original !== stored {
            frameCache.setOriginal(original, for: stored)
        }
        ensureFrameFace(for: stored)
    }

    /// Reduced copy kept for AI Expand. Big enough to send, small enough to keep.
    nonisolated static func reducedOriginal(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 1600, size.width > 0, size.height > 0 else { return image }
        let scale = 1600 / longest
        let out = CGSize(
            width: max(1, (size.width * scale).rounded()),
            height: max(1, (size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: out, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: out))
        }
    }

    // MARK: - Opening the editor

    func openFrameCheck(facing: CameraFacing, slot: Int, target: FrameTarget? = nil, autoExpand: Bool = false) {
        guard isStill(facing: facing, slot: slot) else { return }
        frameCheckRequest = FrameCheckRequest(facing: facing, slot: slot, target: target, autoExpand: autoExpand)
    }
}
