import Foundation
import UIKit
import WebKit

extension BrowserViewModel {

    /// Back if that queue has media, otherwise front, otherwise empty back.
    func preferredPromptFacing() -> CameraFacing {
        if hasBackSource { return .back }
        if hasFrontSource { return .front }
        return .back
    }

    func hasMedia(facing: CameraFacing) -> Bool {
        facing == .front ? hasFrontSource : hasBackSource
    }

    func slotCount(facing: CameraFacing) -> Int {
        facing == .front ? frontSlotCount : backSlotCount
    }

    func queueIndex(facing: CameraFacing) -> Int {
        facing == .front ? frontQueueIndex : backQueueIndex
    }

    func previewImage(facing: CameraFacing, slot: Int) -> UIImage? {
        switch (facing, slot) {
        case (.front, 0): frontImage
        case (.front, _): frontImage2
        case (.back, 0): backImage
        case (.back, _): backImage2
        }
    }

    func sourceType(facing: CameraFacing, slot: Int) -> SourceMediaType? {
        switch (facing, slot) {
        case (.front, 0): frontSourceType
        case (.front, _): frontSourceType2
        case (.back, 0): backSourceType
        case (.back, _): backSourceType2
        }
    }

    func isStill(facing: CameraFacing, slot: Int) -> Bool {
        sourceType(facing: facing, slot: slot) == .image
    }

    /// Every shape's framing for one slot.
    func shapeCrops(facing: CameraFacing, slot: Int) -> ShapeCrops {
        switch (facing, slot) {
        case (.front, 0): frontCrop
        case (.front, _): frontCrop2
        case (.back, 0): backCrop
        case (.back, _): backCrop2
        }
    }

    private func setShapeCrops(_ crops: ShapeCrops, facing: CameraFacing, slot: Int) {
        switch (facing, slot) {
        case (.front, 0): frontCrop = crops
        case (.front, _): frontCrop2 = crops
        case (.back, 0): backCrop = crops
        case (.back, _): backCrop2 = crops
        }
    }

    /// One slot's framing for one frame shape.
    func stillCrop(facing: CameraFacing, slot: Int, shape: FrameShape) -> StillCrop {
        shapeCrops(facing: facing, slot: slot)[shape]
    }

    /// One slot's framing for the shape in play right now.
    func stillCrop(facing: CameraFacing, slot: Int) -> StillCrop {
        stillCrop(facing: facing, slot: slot, shape: activeFrameShape(facing: facing))
    }

    func setStillCrop(_ crop: StillCrop, facing: CameraFacing, slot: Int, shape: FrameShape) {
        var next = crop
        next.zoom = StillCrop.clampZoom(next.zoom)
        next.panX = min(1, max(0, next.panX))
        next.panY = min(1, max(0, next.panY))
        var crops = shapeCrops(facing: facing, slot: slot)
        crops[shape] = next
        setShapeCrops(crops, facing: facing, slot: slot)
        pushStillCrops()
    }

    /// Drops one shape's framing back to the untouched cover-fit.
    func resetStillCrop(facing: CameraFacing, slot: Int, shape: FrameShape) {
        var crops = shapeCrops(facing: facing, slot: slot)
        crops.reset(shape)
        setShapeCrops(crops, facing: facing, slot: slot)
        pushStillCrops()
    }

    /// The frame shape in play: the running feed's own canvas when a site is
    /// pulling, otherwise the frame this camera would answer with.
    func activeFrameShape(facing: CameraFacing) -> FrameShape {
        if isLiveStreamActive, activeStreamFacing == facing, let size = liveFrameSize, size.width > 0 {
            return FrameShape.of(size)
        }
        return defaultFrameTarget(facing: facing).shape
    }

    /// Moves this camera's queue so Next and the pill agree with the card.
    func setQueueIndex(_ index: Int, facing: CameraFacing) {
        let count = slotCount(facing: facing)
        guard count > 0 else { return }
        let clamped = min(max(0, index), count - 1)
        if facing == .front {
            frontQueueIndex = clamped
            webView?.evaluateJavaScript(
                StyleSheetProvider.setQueueIndexScript(front: clamped, back: nil),
                completionHandler: nil
            )
        } else {
            backQueueIndex = clamped
            webView?.evaluateJavaScript(
                StyleSheetProvider.setQueueIndexScript(front: nil, back: clamped),
                completionHandler: nil
            )
        }
    }

    func pushStillCrops() {
        webView?.evaluateJavaScript(
            StyleSheetProvider.stillCropPushScript(
                enabled: behavior.settings.liveStillCrop,
                front: frontCrop,
                front2: frontCrop2,
                back: backCrop,
                back2: backCrop2
            ),
            completionHandler: nil
        )
    }

    // MARK: - Live zoom

    /// Camera the zoom buttons act on: whichever one a site is pulling from.
    var liveZoomFacing: CameraFacing? {
        guard isLiveStreamActive, let facing = activeStreamFacing else { return nil }
        guard slotCount(facing: facing) > 0 else { return nil }
        return facing
    }

    /// True while the floating tools should offer zoom at all.
    var canZoomLiveFeed: Bool { liveZoomFacing != nil }

    /// The zoom the running feed is drawing at right now.
    var liveZoom: Double {
        guard let facing = liveZoomFacing else { return 1 }
        let slot = queueIndex(facing: facing)
        if isStill(facing: facing, slot: slot) {
            return stillCrop(facing: facing, slot: slot).zoom
        }
        return facing == .front ? frontVideoZoom : backVideoZoom
    }

    /// Moves the running feed's zoom by one step, or straight to a value.
    ///
    /// A still writes into its own frame shape's framing, so the change is kept
    /// for the next time that shape is asked for. A clip takes it live only.
    /// Returns the zoom actually landed on, already clamped and snapped.
    @discardableResult
    func setLiveZoom(_ zoom: Double) -> Double {
        guard let facing = liveZoomFacing else { return 1 }
        var next = StillCrop.clampZoom(zoom)
        // 100% is the untouched fit, so the step ladder always lands on it
        // exactly rather than passing within a hair of it.
        if abs(next - 1) < StillCrop.zoomStep * 0.5 { next = 1 }

        let slot = queueIndex(facing: facing)
        if isStill(facing: facing, slot: slot) {
            let shape = activeFrameShape(facing: facing)
            var crop = stillCrop(facing: facing, slot: slot, shape: shape)
            crop.zoom = next
            applyFrameCrop(crop, facing: facing, slot: slot, shape: shape)
        } else {
            if facing == .front { frontVideoZoom = next } else { backVideoZoom = next }
            pushVideoZoom()
        }
        return next
    }

    @discardableResult
    func stepLiveZoom(by delta: Double) -> Double {
        setLiveZoom(liveZoom + delta)
    }

    func pushVideoZoom() {
        webView?.evaluateJavaScript(
            StyleSheetProvider.videoZoomPushScript(front: frontVideoZoom, back: backVideoZoom),
            completionHandler: nil
        )
    }

    /// Reads the running feed's own canvas back, so the zoom and the framing
    /// act on the very frame the site is being sent.
    func refreshLiveFrameSize() {
        guard let webView else { return }
        webView.evaluateJavaScript(StyleSheetProvider.liveFrameSizeScript) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                guard let text = result as? String, text != "none" else {
                    self.liveFrameSize = nil
                    return
                }
                let parts = text.split(separator: ":")
                guard parts.count == 2,
                      let width = Double(parts[0]), let height = Double(parts[1]),
                      width > 0, height > 0 else {
                    self.liveFrameSize = nil
                    return
                }
                self.liveFrameSize = CGSize(width: width, height: height)
            }
        }
    }

    /// Size the live feed will actually report for this ask.
    func previewCanvasSize(prompt: MediaRequestPrompt, facing: CameraFacing) -> (Int, Int) {
        let audit = behavior.audit
        let camera = facing == .front ? audit.primaryFront : audit.primaryBack
        if let width = prompt.requestedWidth, let height = prompt.requestedHeight, width > 0, height > 0 {
            if behavior.settings.useAuditProfile, let camera {
                let mode = camera.resolveMode(width: width, height: height, aspect: nil)
                return (mode.width, mode.height)
            }
            return (width, height)
        }
        if let camera {
            return (camera.defaultMode.width, camera.defaultMode.height)
        }
        return (1280, 720)
    }

    func sendingSizeText(prompt: MediaRequestPrompt, facing: CameraFacing) -> String {
        let size = previewCanvasSize(prompt: prompt, facing: facing)
        return "\(size.0)×\(size.1)"
    }

    func sendingFrameRateText(prompt: MediaRequestPrompt, facing: CameraFacing) -> String {
        let audit = behavior.audit
        let camera = facing == .front ? audit.primaryFront : audit.primaryBack
        if let fps = prompt.requestedFrameRate, fps > 0 {
            if behavior.settings.useAuditProfile {
                if let camera {
                    return "\(Int(camera.resolveFrameRate(fps))) fps"
                }
                return "\(Int(audit.clampFrameRate(fps))) fps"
            }
            return "\(Int(fps)) fps"
        }
        if let camera {
            return "\(Int(camera.grantedFrameRate)) fps"
        }
        return "30 fps"
    }

    /// True when capability checking would refuse this ask exactly as hardware did.
    func wouldRefuseAsk(_ prompt: MediaRequestPrompt, facing: CameraFacing) -> Bool {
        guard behavior.settings.capabilityValidation, behavior.settings.useAuditProfile else { return false }
        let camera = facing == .front ? behavior.audit.primaryFront : behavior.audit.primaryBack
        guard let camera else { return false }
        if let width = prompt.requestedWidth, width > camera.maxWidth { return true }
        if let height = prompt.requestedHeight, height > camera.maxHeight { return true }
        if let fps = prompt.requestedFrameRate, fps > camera.maxFrameRate || fps == 0 { return true }
        return false
    }

    func cameraPermissionText(host: String) -> String {
        behavior.isCameraGranted(host: host) ? "Granted" : "Prompt"
    }

    func microphonePermissionText(host: String) -> String {
        behavior.isMicrophoneGranted(host: host) ? "Granted" : "Prompt"
    }

    /// What `enumerateDevices` is allowed to show this site right now.
    func learnedDevicesText(host: String) -> String {
        if !behavior.settings.useAuditProfile {
            return "Device list follows the live page."
        }
        if !behavior.isCameraGranted(host: host) {
            return "Nameless camera and microphone (before grant)."
        }
        let cameras = behavior.audit.cameras.sorted { $0.order < $1.order }
        let names = cameras.map { "\($0.label) \($0.resolutionSummary)" }
        return names.joined(separator: " · ")
    }

    func resetInjectSessionForNewDocument() {
        if pendingRecap != nil { return }
        injectSession.reset()
        observedFeed = nil
        lastPromptAsk = nil
        expectLiveServeFromPrompt = false
    }

    func noteSessionStartedIfNeeded() {
        guard behavior.settings.autoOffAfterOnePass || behavior.settings.showSequenceRecap else { return }
        guard !injectSession.hasStarted else { return }
        injectSession.host = currentURL?.host() ?? ""
        injectSession.startedAt = Date()
    }

    func updateObservedFeed(from payload: [String: Any], active: Bool) {
        let facing = payload["facing"] as? String ?? observedFeed?.facing ?? ""
        let width = payload["w"] as? Int ?? observedFeed?.width ?? 0
        let height = payload["h"] as? Int ?? observedFeed?.height ?? 0
        let fps = payload["fps"] as? Int ?? observedFeed?.frameRate ?? 0
        let label = payload["label"] as? String ?? observedFeed?.cameraLabel ?? ""
        let format = payload["format"] as? String ?? observedFeed?.format ?? "I420"
        observedFeed = ObservedFeedSnapshot(
            width: width,
            height: height,
            frameRate: fps,
            format: format,
            cameraLabel: label,
            facing: facing,
            isActive: active,
            pageHoldsFeed: active
        )
    }

    func handleServedPayload(_ payload: [String: Any]) {
        guard behavior.settings.autoOffAfterOnePass || behavior.settings.showSequenceRecap else { return }
        let facingRaw = payload["facing"] as? String ?? ""
        let isBack = facingRaw == "environment"
        let slot = payload["slot"] as? Int ?? (isBack ? backQueueIndex : frontQueueIndex)
        markSlotServed(facing: isBack ? .back : .front, slot: slot)

        if expectLiveServeFromPrompt {
            expectLiveServeFromPrompt = false
            checkOnePassComplete()
            return
        }

        if lastPromptAsk == nil {
            noteSessionStartedIfNeeded()
            let facingLabel = isBack ? "Back" : "Front"
            let size = observedFeed.map { "\($0.width)×\($0.height)" } ?? "Device default"
            let fps = observedFeed.map { "\($0.frameRate) fps" } ?? "—"
            appendRecapEvent(
                RecapEvent(
                    kind: .live,
                    host: currentURL?.host() ?? injectSession.host,
                    askedFacing: "Unspecified",
                    sentFacing: facingLabel,
                    askedSize: "Any size",
                    sentSize: size,
                    askedFrameRate: "Any rate",
                    sentFrameRate: fps,
                    wantsAudio: payload["audio"] as? Bool ?? false,
                    cropPercent: cropPercentIfNeeded(facing: isBack ? .back : .front, slot: slot),
                    note: "Unprompted inject"
                )
            )
        }
        checkOnePassComplete()
    }

    func recordPromptDecision(_ prompt: MediaRequestPrompt, _ decision: MediaRequestDecision) {
        if decision.cancelled {
            lastPromptAsk = nil
            expectLiveServeFromPrompt = false
            return
        }

        lastPromptAsk = prompt
        let userChose = decision.facing != nil
        if !userChose {
            // Timeout / stacked / silenced fallthrough: site defaults, not the preview.
            appendRecapEvent(
                RecapEvent(
                    kind: prompt.kind,
                    host: prompt.host,
                    askedFacing: prompt.requestedFacingText,
                    sentFacing: prompt.resolvedFacing == .back ? "Back" : "Front",
                    askedSize: prompt.requestedSizeText,
                    sentSize: sendingSizeText(prompt: prompt, facing: prompt.resolvedFacing),
                    askedFrameRate: prompt.requestedFrameRateText,
                    sentFrameRate: sendingFrameRateText(prompt: prompt, facing: prompt.resolvedFacing),
                    wantsAudio: prompt.wantsAudio,
                    cropPercent: nil,
                    note: "Timed out — site defaults"
                )
            )
            expectLiveServeFromPrompt = prompt.kind == .live
            return
        }

        let sentFacing = decision.facing ?? prompt.resolvedFacing
        let slot = decision.slot ?? queueIndex(facing: sentFacing)
        noteSessionStartedIfNeeded()
        markSlotServed(facing: sentFacing, slot: slot)

        let crop = cropPercentIfNeeded(facing: sentFacing, slot: slot)
        appendRecapEvent(
            RecapEvent(
                kind: prompt.kind,
                host: prompt.host,
                askedFacing: prompt.requestedFacingText,
                sentFacing: sentFacing == .back ? "Back" : "Front",
                askedSize: prompt.kind == .live ? prompt.requestedSizeText : (prompt.accept?.isEmpty == false ? prompt.accept! : "Any file"),
                sentSize: prompt.kind == .live
                    ? sendingSizeText(prompt: prompt, facing: sentFacing)
                    : sendingItemLabel(facing: sentFacing, slot: slot),
                askedFrameRate: prompt.kind == .live ? prompt.requestedFrameRateText : "—",
                sentFrameRate: prompt.kind == .live ? sendingFrameRateText(prompt: prompt, facing: sentFacing) : "—",
                wantsAudio: prompt.wantsAudio,
                cropPercent: prompt.kind == .live ? crop : nil,
                note: askedVsSentNote(prompt: prompt, sentFacing: sentFacing)
            )
        )

        if prompt.kind == .live {
            expectLiveServeFromPrompt = true
        } else {
            checkOnePassComplete()
        }
    }

    func sendingItemLabel(facing: CameraFacing, slot: Int) -> String {
        guard let type = sourceType(facing: facing, slot: slot) else { return "Nothing loaded" }
        return type == .video ? "Media \(slot + 1) · video" : "Media \(slot + 1) · photo"
    }

    func askedVsSentNote(prompt: MediaRequestPrompt, sentFacing: CameraFacing) -> String {
        var bits: [String] = []
        let asked = prompt.requestedFacingText
        let sent = sentFacing == .back ? "Back" : "Front"
        if asked != "Unspecified", asked != sent {
            bits.append("asked \(asked), you sent \(sent)")
        }
        if prompt.kind == .live {
            let askedSize = prompt.requestedSizeText
            let sentSize = sendingSizeText(prompt: prompt, facing: sentFacing)
            bits.append("asked \(askedSize), sent \(sentSize)")
        }
        return bits.isEmpty ? "Sent as chosen" : bits.joined(separator: "; ")
    }

    func cropPercentIfNeeded(facing: CameraFacing, slot: Int) -> Int? {
        guard isStill(facing: facing, slot: slot) else {
            let zoom = facing == .front ? frontVideoZoom : backVideoZoom
            guard zoom != 1 else { return nil }
            return Int((zoom * 100).rounded())
        }
        guard behavior.settings.liveStillCrop else { return nil }
        let crop = stillCrop(facing: facing, slot: slot)
        guard !crop.isIdentity else { return nil }
        return Int(crop.percent.rounded())
    }

    func markSlotServed(facing: CameraFacing, slot: Int) {
        guard behavior.settings.autoOffAfterOnePass || behavior.settings.showSequenceRecap else { return }
        noteSessionStartedIfNeeded()
        switch facing {
        case .front:
            injectSession.usedFront = true
            injectSession.servedFront.insert(slot)
        case .back:
            injectSession.usedBack = true
            injectSession.servedBack.insert(slot)
        }
    }

    func appendRecapEvent(_ event: RecapEvent) {
        guard behavior.settings.showSequenceRecap || behavior.settings.autoOffAfterOnePass else { return }
        noteSessionStartedIfNeeded()
        injectSession.events.append(event)
    }

    func onePassComplete() -> Bool {
        guard injectSession.hasStarted else { return false }
        if !injectSession.usedFront && !injectSession.usedBack { return false }
        if injectSession.usedFront {
            guard frontSlotCount > 0 else { return false }
            for index in 0..<frontSlotCount where !injectSession.servedFront.contains(index) {
                return false
            }
        }
        if injectSession.usedBack {
            guard backSlotCount > 0 else { return false }
            for index in 0..<backSlotCount where !injectSession.servedBack.contains(index) {
                return false
            }
        }
        return true
    }

    func checkOnePassComplete() {
        guard behavior.settings.autoOffAfterOnePass else { return }
        guard injectSession.hasStarted, isMediaActive else { return }
        guard onePassComplete() else { return }
        if isLiveStreamActive { return }
        finishInjectSession(reason: "One full pass", autoOff: true)
    }

    func finishInjectSession(reason: String, autoOff: Bool) {
        guard injectSession.hasStarted, !injectSession.recapShown else { return }
        guard behavior.settings.showSequenceRecap || autoOff else {
            injectSession.reset()
            return
        }
        injectSession.recapShown = true

        if autoOff, isMediaActive {
            isMediaActive = false
            updateUserScripts()
            syncMediaToPage()
        }

        guard behavior.settings.showSequenceRecap else {
            injectSession.reset()
            return
        }

        let ended = Date()
        var held: Double?
        if let inactive = injectSession.lastInactiveAt, let active = injectSession.lastActiveAt, inactive > active {
            held = inactive.timeIntervalSince(active)
        }
        var events = injectSession.events
        if isLiveStreamActive {
            events.append(
                RecapEvent(
                    kind: .live,
                    host: injectSession.host,
                    askedFacing: "—",
                    sentFacing: activeStreamFacing == .back ? "Back" : (activeStreamFacing == .front ? "Front" : "—"),
                    askedSize: "—",
                    sentSize: observedFeed.map { "\($0.width)×\($0.height)" } ?? "—",
                    askedFrameRate: "—",
                    sentFrameRate: observedFeed.map { "\($0.frameRate) fps" } ?? "—",
                    wantsAudio: false,
                    cropPercent: nil,
                    note: "Page may still be holding the feed"
                )
            )
        } else if let held, held > 0.5 {
            events.append(
                RecapEvent(
                    kind: .live,
                    host: injectSession.host,
                    askedFacing: "—",
                    sentFacing: "—",
                    askedSize: "—",
                    sentSize: "—",
                    askedFrameRate: "—",
                    sentFrameRate: "—",
                    wantsAudio: false,
                    cropPercent: nil,
                    note: String(format: "Page still held the feed for %.1f seconds after the last frame", held)
                )
            )
        }

        pendingRecap = SequenceRecap(
            host: injectSession.host,
            startedAt: injectSession.startedAt ?? ended,
            endedAt: ended,
            events: events,
            heldFeedAfterSeconds: held,
            endedBecause: reason
        )
    }

    /// Investigation result: clips are not generated at request time.
    func prepareFaceClips(facing: CameraFacing, slot: SequenceSlot) {
        guard facing == .front, behavior.settings.frontFaceButtons else { return }
        guard isStill(facing: facing, slot: slot.rawValue) else {
            facePrepError = "Only a front still can be prepared."
            return
        }
        facePrepError = "Clips couldn’t be prepared. Stills work as they do today."
        facePrep = .empty
    }
}
