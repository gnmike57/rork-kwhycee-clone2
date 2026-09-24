import AVFoundation
import SwiftUI
import WebKit

@Observable
@MainActor
final class BrowserViewModel {
    var urlText: String = ""
    var currentURL: URL?
    var pageTitle: String = ""
    var isLoading: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var estimatedProgress: Double = 0

    var pendingNavigationURL: URL?

    var bookmarks: [Bookmark] = []
    var showBookmarks: Bool = false
    var showOverlayPanel: Bool = false
    var showDownloads: Bool = false

    /// Sequence slot 1 (primary) and optional slot 2 for each camera.
    var frontImage: UIImage?
    var frontVideoURL: URL?
    var frontSourceType: SourceMediaType?
    var frontImage2: UIImage?
    var frontVideoURL2: URL?
    var frontSourceType2: SourceMediaType?

    var backImage: UIImage?
    var backVideoURL: URL?
    var backSourceType: SourceMediaType?
    var backImage2: UIImage?
    var backVideoURL2: URL?
    var backSourceType2: SourceMediaType?

    var isConverting: Bool = false
    var conversionProgress: String = ""
    var conversionPercent: Double = 0

    var isMediaActive: Bool = false
    var mediaMode: MediaMode = .replaceAll

    /// Default facing when a site does not specify front/back.
    var defaultFacingWhenUnspecified: CameraFacing = .back

    /// When sequence counters advance.
    var advanceMode: AdvanceMode = .onEachRequest

    // MARK: - Stealth options
    //
    // All default to the original behaviour, so nothing changes until the user opts in.

    /// Stops the automated hand-off; the page receives files from the real iOS picker instead.
    var nativePickerMode: Bool = false

    /// What to do with inputs that force the camera open. Only consulted in native picker mode.
    var captureButtonHandling: CaptureButtonHandling = .autoInject

    /// Drops the `files` fallback and stops replacing built-in input methods.
    var accessorHardening: Bool = false

    /// Reports remaining wrappers as built-in code. Itself detectable, hence opt-in.
    var maskWrappersAsNative: Bool = false

    /// Transient note shown after a change that needed a page reload.
    var stealthNotice: String?

    /// Transient result of the last "Save to Photos" action.
    var photoSaveStatus: String?

    var isOverlayActive: Bool = false
    var overlayOpacity: Double = 1.0
    var showBurnConfirmation: Bool = false
    var isBurning: Bool = false

    // MARK: - Device-matched media layer
    //
    // Additive. Nothing below reaches into the existing delivery path; the media
    // itself is untouched and every switch has an off state that restores today.

    /// Every new switch, the pill's parked position and the per-site prompt memory.
    let behavior = MediaBehaviorStore()

    /// Read-only audit sheet screen.
    var showDeviceProfile: Bool = false

    /// Set when Media Controls should hand straight over to the audit sheet as it
    /// closes, so the two screens chain instead of racing a fixed pause.
    var opensDeviceProfileAfterDismiss: Bool = false

    /// Set when Media Controls should open the My Media tab as it closes.
    var opensMyMediaAfterDismiss: Bool = false

    /// Camera a site is currently pulling from, reported by the page.
    var activeStreamFacing: CameraFacing?
    var isLiveStreamActive: Bool = false

    /// Queue positions mirrored from the page so the pill can show what is next.
    var frontQueueIndex: Int = 0
    var backQueueIndex: Int = 0

    /// True while a live feed is fading itself over to the next item.
    var isFadingMedia: Bool = false

    /// True while a force re-inject is being carried out, so the button can say
    /// so rather than looking like it did nothing.
    var isReinjecting: Bool = false
    /// What the last force re-inject did, shown briefly under the tools.
    var reinjectNotice: String?

    /// Request waiting on the user, if the prompt is switched on.
    var pendingPrompt: MediaRequestPrompt?

    /// Per-still live-feed framing, kept apart for each frame shape.
    /// File/photo/native paths never read these.
    var frontCrop: ShapeCrops = .identity
    var frontCrop2: ShapeCrops = .identity
    var backCrop: ShapeCrops = .identity
    var backCrop2: ShapeCrops = .identity

    /// Live zoom for a running clip, per camera. A video takes this live and
    /// forgets it when the clip or the feed changes; stills keep theirs in the
    /// framing maps above.
    var frontVideoZoom: Double = 1
    var backVideoZoom: Double = 1

    /// The exact frame the running feed is drawing into, read back from the
    /// page so live zoom moves the very framing the site is being sent.
    var liveFrameSize: CGSize?

    /// Each loaded clip's size as it is meant to be seen, so a video can be
    /// judged against a frame without opening the file again.
    var frontVideoSize: CGSize?
    var frontVideoSize2: CGSize?
    var backVideoSize: CGSize?
    var backVideoSize2: CGSize?

    /// In-progress inject pass on this page visit.
    var injectSession = InjectSessionState()
    /// What the page was last told about the live feed.
    var observedFeed: ObservedFeedSnapshot?
    /// Recap sheet, shown when injection turns off and the recap switch is on.
    var pendingRecap: SequenceRecap?
    /// Optional front-still smirk/smile clips. Empty until prepared.
    var facePrep: FacePrep = .empty
    var facePrepError: String?
    /// Last intercept the user answered, used to pair a live serve with asked-vs-sent.
    var lastPromptAsk: MediaRequestPrompt?
    var expectLiveServeFromPrompt: Bool = false

    /// Most recent refusal, surfaced in the hardware alignment section.
    var lastRefusalSummary: String?

    /// How far the page had to ease motion off to keep the feed smooth.
    /// 0 = full strength, 1 = reduced, 2 = stopped.
    var motionEasedLevel: Int = 0

    // MARK: - Frame Check

    /// Full-screen editor request; presented once at the app root.
    var frameCheckRequest: FrameCheckRequest?
    /// Set when Media Controls should hand over to the editor as it closes.
    var frameCheckAfterDismiss: FrameCheckRequest?
    /// Faces and import originals, remembered per still.
    let frameCache = FrameCheckCache()
    let faceFinder = FaceFinder()
    let frameExpander = FrameExpandService()

    weak var webView: WKWebView?
    let schemeHandler = LocalResourceHandler()
    let imageSchemeHandler = LocalResourceHandler()
    var activeProfile: DeviceProfile?
    let videoLibrary = VideoLibraryService()
    let constraintLog = ConstraintLogService()
    let siteHistory = SiteHistoryService()
    let downloadService = DownloadService()

    /// Guards the Next button's lit state against overlapping presses.
    private var mediaFadeToken: Int = 0
    /// Guards the re-inject button's lit state and its notice.
    private var reinjectToken: Int = 0

    private let mediaConverter = MediaConverterService()
    private let exifService = EXIFMetadataService()
    private let photoLibrary = PhotoLibraryService()
    private var convertedFrontVideoURL: URL?
    private var convertedBackVideoURL: URL?
    private var convertedFrontVideoURL2: URL?
    private var convertedBackVideoURL2: URL?

    /// The still preparation running for each front slot. A fresh import
    /// into the same slot cancels the one before it, so a slow first photo
    /// can never land on top of a quicker second pick.
    private var frontStillTasks: [Int: Task<Void, Never>] = [:]

    var hasFrontSource: Bool { frontSourceType != nil || frontSourceType2 != nil }
    var hasBackSource: Bool { backSourceType != nil || backSourceType2 != nil }
    var hasSource: Bool { hasFrontSource || hasBackSource }

    var frontSlotCount: Int {
        (frontSourceType != nil ? 1 : 0) + (frontSourceType2 != nil ? 1 : 0)
    }

    var backSlotCount: Int {
        (backSourceType != nil ? 1 : 0) + (backSourceType2 != nil ? 1 : 0)
    }

    var sourceImage: UIImage? { if frontSourceType != nil { return frontImage } else { return backImage } }
    var sourceVideoURL: URL? { if frontSourceType != nil { return frontVideoURL } else { return backVideoURL } }
    var sourceType: SourceMediaType? { frontSourceType ?? backSourceType }

    nonisolated enum SourceMediaType: Sendable {
        case image
        case video
    }

    nonisolated enum MediaMode: Sendable, CaseIterable, Identifiable {
        case replaceAll
        case addDevice

        nonisolated var id: Self { self }

        nonisolated var label: String {
            switch self {
            case .replaceAll: "Replace All Sources"
            case .addDevice: "Add as Selectable Source"
            }
        }
    }

    nonisolated enum AdvanceMode: String, Sendable, CaseIterable, Identifiable {
        case onEachRequest
        case onRequestAndVideoEnd

        nonisolated var id: Self { self }

        nonisolated var label: String {
            switch self {
            case .onEachRequest: "On each new request"
            case .onRequestAndVideoEnd: "On request + when video ends"
            }
        }

        /// Value pushed into the injected page state.
        nonisolated var jsValue: String {
            switch self {
            case .onEachRequest: "request"
            case .onRequestAndVideoEnd: "videoend"
            }
        }
    }

    nonisolated enum CaptureButtonHandling: String, Sendable, CaseIterable, Identifiable {
        case photoPicker
        case realCamera
        case autoInject

        nonisolated var id: Self { self }

        nonisolated var label: String {
            switch self {
            case .photoPicker: "Photo picker"
            case .realCamera: "Real camera"
            case .autoInject: "Auto-fill"
            }
        }

        nonisolated var detail: String {
            switch self {
            case .photoPicker: "Opens the iOS photo library so you pick the file yourself. Keeps events genuine."
            case .realCamera: "Fully hands off — the real camera opens and your media is not used."
            case .autoInject: "Falls back to the automatic hand-off for camera buttons only."
            }
        }

        /// Value pushed into the injected page state.
        nonisolated var jsValue: String {
            switch self {
            case .photoPicker: "picker"
            case .realCamera: "native"
            case .autoInject: "auto"
            }
        }
    }

    nonisolated enum SequenceSlot: Int, Sendable, CaseIterable, Identifiable {
        case one = 0
        case two = 1

        nonisolated var id: Int { rawValue }

        nonisolated var label: String {
            switch self {
            case .one: "1"
            case .two: "2"
            }
        }
    }

    private let bookmarksKey = "browser_bookmarks_v1"

    let keptStills = KeptStillStore()
    let photoMemory = PhotoMemoryStore()

    init() {
        loadBookmarks()
        restoreKeptStills()
    }

    func navigateTo(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let url: URL?
        if trimmed.contains(".") && !trimmed.contains(" ") {
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                url = URL(string: trimmed)
            } else {
                url = URL(string: "https://\(trimmed)")
            }
        } else {
            let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            url = URL(string: "https://www.google.com/search?q=\(query)")
        }

        guard let validURL = url else { return }
        pendingNavigationURL = validURL
        currentURL = validURL
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    func goHome() {
        currentURL = nil
        urlText = ""
        webView = nil
    }

    func addBookmark() {
        guard let url = currentURL else { return }
        let title = pageTitle.isEmpty ? url.host() ?? url.absoluteString : pageTitle
        guard !bookmarks.contains(where: { $0.urlString == url.absoluteString }) else { return }
        let bookmark = Bookmark(title: title, urlString: url.absoluteString)
        bookmarks.insert(bookmark, at: 0)
        saveBookmarks()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    func isCurrentPageBookmarked() -> Bool {
        guard let url = currentURL else { return false }
        return bookmarks.contains { $0.urlString == url.absoluteString }
    }

    nonisolated enum CameraFacing: String, Sendable, CaseIterable, Identifiable {
        case front
        case back

        nonisolated var id: String { rawValue }
    }

    // MARK: - Source loading (sequence-aware)

    /// - Parameter preparedForFrame: the still was made for an exact frame (an
    ///   approved AI expansion), so the front device-size cover-crop is skipped;
    ///   it would only cut away what was just added. Metadata stamping and every
    ///   other step run exactly as for any import.
    func loadSource(image: UIImage, facing: CameraFacing, slot: SequenceSlot = .one, preparedForFrame: Bool = false) {
        // Media 2 requires Media 1 to already be filled.
        if slot == .two {
            let hasOne = facing == .front ? frontSourceType != nil : backSourceType != nil
            guard hasOne else { return }
        }

        switch (facing, slot) {
        case (.front, .one):
            frontImage = image
            frontVideoURL = nil
            frontSourceType = .image
            schemeHandler.frontVideoFileURL = nil
            if let old = convertedFrontVideoURL { try? FileManager.default.removeItem(at: old); convertedFrontVideoURL = nil }
        case (.front, .two):
            frontImage2 = image
            frontVideoURL2 = nil
            frontSourceType2 = .image
            if let old = convertedFrontVideoURL2 { try? FileManager.default.removeItem(at: old); convertedFrontVideoURL2 = nil }
        case (.back, .one):
            backImage = image
            backVideoURL = nil
            backSourceType = .image
            schemeHandler.backVideoFileURL = nil
            if let old = convertedBackVideoURL { try? FileManager.default.removeItem(at: old); convertedBackVideoURL = nil }
        case (.back, .two):
            backImage2 = image
            backVideoURL2 = nil
            backSourceType2 = .image
            if let old = convertedBackVideoURL2 { try? FileManager.default.removeItem(at: old); convertedBackVideoURL2 = nil }
        }

        resetSlotPresentation(facing: facing, slot: slot)
        dropKeptSlot(facing: facing, slot: slot.rawValue)

        // Fresh media means the user intends to use it — enable delivery now
        // that a source exists. Manual switch-off stays sticky until the next
        // import.
        setMediaActive(true)

        let cam: CameraDeviceSpec? = facing == .front ? activeProfile?.frontCamera : activeProfile?.backCamera
        if activeProfile != nil, let cam, facing == .front {
            // The photo keeps its own shape and enough resolution to fill the
            // largest frame sites ask for. Squeezing it into one fixed camera
            // size on the way in was what left a widescreen ask upscaling from
            // a portrait box.
            let converter = mediaConverter
            let exif = exifService
            let hw = activeProfile?.deviceHardware
            let slotIndex = slot.rawValue
            isConverting = true
            conversionProgress = "Preparing front media \(slot.label)…"
            conversionPercent = 0.5
            let keepsPixels = preparedForFrame
            frontStillTasks[slotIndex]?.cancel()
            frontStillTasks[slotIndex] = Task { [weak self] in
                let prepared = await Self.prepareFrontStill(
                    image,
                    keepsPixels: keepsPixels,
                    converter: converter,
                    exif: exif,
                    camera: cam,
                    hardware: hw
                )
                guard let self, !Task.isCancelled else { return }
                if slotIndex == 0 {
                    self.frontImage = prepared.converted
                    self.imageSchemeHandler.frontImageData = prepared.exifData
                    self.imageSchemeHandler.setFrontSourceImage(prepared.converted, slot: 0)
                } else {
                    self.frontImage2 = prepared.converted
                    self.imageSchemeHandler.setFrontSourceImage(prepared.converted, slot: 1)
                }
                self.isConverting = false
                self.conversionProgress = ""
                self.conversionPercent = 0
                self.noteFrameImport(stored: prepared.converted, original: prepared.original)
                if !keepsPixels {
                    self.autoPrepareFraming(facing: .front, slot: slotIndex)
                }
                self.rememberKeptSlot(facing: .front, slot: slotIndex)
                self.ensureFaceMap(for: prepared.converted)
                if self.isMediaActive { self.syncMediaToPage() }
            }
        } else if facing == .back {
            // Back Take Photo path stamps the native template on demand, so there is
            // no conversion work here — store the source and show it straight away.
            if slot.rawValue == 0 {
                backImage = image
                imageSchemeHandler.setBackSourceImage(image, slot: 0)
                imageSchemeHandler.backImageData = nil
            } else {
                backImage2 = image
                imageSchemeHandler.setBackSourceImage(image, slot: 1)
            }
            imageSchemeHandler.stampBackOnDemand = true
            noteFrameImport(stored: image, original: nil)
            if !preparedForFrame {
                autoPrepareFraming(facing: .back, slot: slot.rawValue)
            }
            rememberKeptSlot(facing: .back, slot: slot.rawValue)
            ensureFaceMap(for: image)
            if isMediaActive { syncMediaToPage() }
        } else {
            generateEXIFForImage(image, facing: facing, slot: slot)
            noteFrameImport(stored: image, original: nil)
            if !preparedForFrame {
                autoPrepareFraming(facing: facing, slot: slot.rawValue)
            }
            rememberKeptSlot(facing: facing, slot: slot.rawValue)
            ensureFaceMap(for: image)
            if isMediaActive { syncMediaToPage() }
        }
    }

    private func generateEXIFForImage(_ image: UIImage, facing: CameraFacing, slot: SequenceSlot) {
        let slotIndex = slot.rawValue
        if facing == .back {
            // Back stills are stamped on demand, so there is nothing to compute.
            imageSchemeHandler.setBackSourceImage(image, slot: slotIndex)
            imageSchemeHandler.stampBackOnDemand = true
            if slotIndex == 0 { imageSchemeHandler.backImageData = nil }
            return
        }

        let cam = activeProfile?.frontCamera
        let hw = activeProfile?.deviceHardware
        let exif = exifService
        frontStillTasks[slotIndex]?.cancel()
        frontStillTasks[slotIndex] = Task { [weak self] in
            let data = await Self.stampEXIF(image, exif: exif, camera: cam, hardware: hw)
            guard let self, !Task.isCancelled else { return }
            if slotIndex == 0 {
                self.imageSchemeHandler.frontImageData = data
                self.imageSchemeHandler.setFrontSourceImage(image, slot: 0)
            } else {
                self.imageSchemeHandler.setFrontSourceImage(image, slot: 1)
            }
        }
    }

    /// A front still made ready for injection, off the main actor.
    nonisolated private struct PreparedFrontStill: Sendable {
        let converted: UIImage
        let exifData: Data?
        /// Reduced copy of the import kept behind the preparation, so AI
        /// Expand can start from real pixels. `nil` when the pixels were kept.
        let original: UIImage?
    }

    /// Resizing, EXIF stamping and the Frame Check copy are all heavy; they
    /// run on the concurrent pool and only plain values come back.
    @concurrent
    nonisolated private static func prepareFrontStill(
        _ image: UIImage,
        keepsPixels: Bool,
        converter: MediaConverterService,
        exif: EXIFMetadataService,
        camera: CameraDeviceSpec?,
        hardware: DeviceHardwareSpec?
    ) async -> PreparedFrontStill {
        let converted = keepsPixels ? image : converter.prepareStillForInjection(image)
        let exifData = exif.jpegDataWithEXIF(image: converted, camera: camera, hardware: hardware)
        let original = keepsPixels ? nil : reducedOriginal(image)
        return PreparedFrontStill(converted: converted, exifData: exifData, original: original)
    }

    @concurrent
    nonisolated private static func stampEXIF(
        _ image: UIImage,
        exif: EXIFMetadataService,
        camera: CameraDeviceSpec?,
        hardware: DeviceHardwareSpec?
    ) async -> Data? {
        exif.jpegDataWithEXIF(image: image, camera: camera, hardware: hardware)
    }

    /// - Parameter isPrepared: the clip already carries this camera's exact
    ///   spec, so re-encoding would only cost time and stack a second
    ///   generation of compression on top.
    func loadSource(videoURL: URL, facing: CameraFacing, slot: SequenceSlot = .one, isPrepared: Bool = false) {
        // Media 2 requires Media 1 to already be filled.
        if slot == .two {
            let hasOne = facing == .front ? frontSourceType != nil : backSourceType != nil
            guard hasOne else { return }
        }

        dropKeptSlot(facing: facing, slot: slot.rawValue)

        switch (facing, slot) {
        case (.front, .one):
            frontVideoURL = videoURL
            frontImage = nil
            frontSourceType = .video
            if let old = convertedFrontVideoURL { try? FileManager.default.removeItem(at: old); convertedFrontVideoURL = nil }
        case (.front, .two):
            frontVideoURL2 = videoURL
            frontImage2 = nil
            frontSourceType2 = .video
            if let old = convertedFrontVideoURL2 { try? FileManager.default.removeItem(at: old); convertedFrontVideoURL2 = nil }
        case (.back, .one):
            backVideoURL = videoURL
            backImage = nil
            backSourceType = .video
            if let old = convertedBackVideoURL { try? FileManager.default.removeItem(at: old); convertedBackVideoURL = nil }
        case (.back, .two):
            backVideoURL2 = videoURL
            backImage2 = nil
            backSourceType2 = .video
            if let old = convertedBackVideoURL2 { try? FileManager.default.removeItem(at: old); convertedBackVideoURL2 = nil }
        }

        resetSlotPresentation(facing: facing, slot: slot)

        // Same intent as the photo path: import ⇒ enable.
        setMediaActive(true)

        let cam: CameraDeviceSpec? = facing == .front ? activeProfile?.frontCamera : activeProfile?.backCamera
        if let profile = activeProfile, let cam, !isPrepared {
            let converter = mediaConverter
            let label = "\(facing == .front ? "front" : "back") \(slot.label)"
            let slotIndex = slot.rawValue
            isConverting = true
            conversionPercent = 0
            conversionProgress = "Preparing \(label)…"

            Task {
                // The clip is encoded in the orientation it was shot in: a
                // portrait clip forced into a landscape box arrived letterboxed
                // with bars a site could see.
                let sourceSize = await Self.displaySize(ofVideoAt: videoURL)
                let spec = profile.conversionSpec(for: cam, sourceSize: sourceSize)
                self.setVideoSize(
                    CGSize(width: spec.targetWidth, height: spec.targetHeight),
                    facing: facing, slot: slotIndex
                )
                self.conversionProgress = "Transcoding \(label) \(spec.targetWidth)×\(spec.targetHeight) @\(spec.targetFrameRate)fps…"

                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("converted_\(facing == .front ? "f" : "b")\(slotIndex)_\(UUID().uuidString).mov")

                let success = await converter.convertVideoWithProgress(videoURL, spec: spec, outputURL: outputURL) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.conversionPercent = progress
                        self?.conversionProgress = "\(label.capitalized): \(Int(progress * 100))%"
                    }
                }

                let finalURL = success ? outputURL : videoURL
                switch (facing, slot) {
                case (.front, .one):
                    if success { self.convertedFrontVideoURL = outputURL }
                    self.frontVideoURL = finalURL
                    self.schemeHandler.frontVideoFileURL = finalURL
                case (.front, .two):
                    if success { self.convertedFrontVideoURL2 = outputURL }
                    self.frontVideoURL2 = finalURL
                    self.schemeHandler.frontVideoFileURL2 = finalURL
                case (.back, .one):
                    if success { self.convertedBackVideoURL = outputURL }
                    self.backVideoURL = finalURL
                    self.schemeHandler.backVideoFileURL = finalURL
                case (.back, .two):
                    if success { self.convertedBackVideoURL2 = outputURL }
                    self.backVideoURL2 = finalURL
                    self.schemeHandler.backVideoFileURL2 = finalURL
                }
                self.isConverting = false
                self.conversionProgress = ""
                self.conversionPercent = 0
                if self.isMediaActive { self.syncMediaToPage() }
            }
        } else {
            switch (facing, slot) {
            case (.front, .one): schemeHandler.frontVideoFileURL = videoURL
            case (.front, .two): schemeHandler.frontVideoFileURL2 = videoURL
            case (.back, .one): schemeHandler.backVideoFileURL = videoURL
            case (.back, .two): schemeHandler.backVideoFileURL2 = videoURL
            }
            // An already-prepared clip is not re-encoded, so its own size is
            // read straight off the file for the readiness row.
            let slotIndex = slot.rawValue
            Task { @MainActor [weak self] in
                let size = await Self.displaySize(ofVideoAt: videoURL)
                self?.setVideoSize(size, facing: facing, slot: slotIndex)
            }
            if isMediaActive { syncMediaToPage() }
        }
    }

    /// A clip's size as it is meant to be seen, with any rotation applied.
    ///
    /// A portrait clip is very often stored landscape with a quarter turn in
    /// its transform, so the stored size alone would read the wrong way round.
    nonisolated static func displaySize(ofVideoAt url: URL) async -> CGSize? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        guard let natural = try? await track.load(.naturalSize) else { return nil }
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let applied = natural.applying(transform)
        let size = CGSize(width: abs(applied.width), height: abs(applied.height))
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }

    /// Assigns a library clip to the one camera it was prepared for.
    func loadSavedVideo(_ video: SavedVideo) {
        if let frontURL = videoLibrary.frontVideoURL(for: video) {
            loadSource(videoURL: frontURL, facing: .front, slot: .one, isPrepared: true)
        }
        if let backURL = videoLibrary.backVideoURL(for: video) {
            loadSource(videoURL: backURL, facing: .back, slot: .one, isPrepared: true)
        }
    }

    func loadSavedVideo(_ video: SavedVideo, facing: CameraFacing, slot: SequenceSlot) {
        let exactMatch = facing == .front
            ? videoLibrary.frontVideoURL(for: video)
            : videoLibrary.backVideoURL(for: video)

        // Already encoded to this camera's spec on import, so hand it straight
        // over rather than doing the same work a second time.
        if let exactMatch {
            loadSource(videoURL: exactMatch, facing: facing, slot: slot, isPrepared: true)
            return
        }

        // Assigned to the camera it was not prepared for — re-encode so the
        // output still matches the spec the page is told about.
        guard let fallback = videoLibrary.preparedVideoURL(for: video)
            ?? videoLibrary.originalVideoURL(for: video) else { return }
        loadSource(videoURL: fallback, facing: facing, slot: slot)
    }

    func clearSource(facing: CameraFacing, slot: SequenceSlot? = nil) {
        if let slot {
            if slot == .one {
                // Removing Media 1 while Media 2 is filled → shift 2 → 1, free 2.
                promoteSlotTwoIfNeeded(facing: facing)
            } else {
                clearSlot(facing: facing, slot: .two)
            }
        } else {
            clearSlot(facing: facing, slot: .one)
            clearSlot(facing: facing, slot: .two)
        }
        if !hasSource {
            isMediaActive = false
            isOverlayActive = false
        }
        clampQueueIndices()
        syncMediaToPage()
    }

    /// When Media 1 is removed and Media 2 exists, move Media 2 into Media 1 and free Media 2.
    private func promoteSlotTwoIfNeeded(facing: CameraFacing) {
        switch facing {
        case .front:
            guard frontSourceType2 != nil else {
                clearSlot(facing: .front, slot: .one)
                return
            }
            // Drop old slot-1 converted file if present and different from slot 2.
            if let old = convertedFrontVideoURL, old != convertedFrontVideoURL2 {
                try? FileManager.default.removeItem(at: old)
            }
            // Move slot 2 → slot 1
            frontImage = frontImage2
            frontVideoURL = frontVideoURL2
            frontSourceType = frontSourceType2
            convertedFrontVideoURL = convertedFrontVideoURL2
            convertedFrontVideoURL2 = nil
            frontCrop = frontCrop2
            frontCrop2 = .identity
            frontVideoZoom = 1
            facePrep = .empty
            facePrepError = nil
            schemeHandler.frontVideoFileURL = schemeHandler.frontVideoFileURL2 ?? frontVideoURL
            schemeHandler.frontVideoFileURL2 = nil
            if let img = frontImage {
                imageSchemeHandler.setFrontSourceImage(img, slot: 0)
            } else {
                imageSchemeHandler.setFrontSourceImage(nil, slot: 0)
            }
            // Prefer on-demand/fallback rebuild after promote.
            imageSchemeHandler.frontImageData = nil
            // Clear slot 2
            frontImage2 = nil
            frontVideoURL2 = nil
            frontSourceType2 = nil
            imageSchemeHandler.setFrontSourceImage(nil, slot: 1)
            rememberKeptSlot(facing: .front, slot: 0)
            dropKeptSlot(facing: .front, slot: 1)
        case .back:
            guard backSourceType2 != nil else {
                clearSlot(facing: .back, slot: .one)
                return
            }
            if let old = convertedBackVideoURL, old != convertedBackVideoURL2 {
                try? FileManager.default.removeItem(at: old)
            }
            backImage = backImage2
            backVideoURL = backVideoURL2
            backSourceType = backSourceType2
            convertedBackVideoURL = convertedBackVideoURL2
            convertedBackVideoURL2 = nil
            backCrop = backCrop2
            backCrop2 = .identity
            backVideoZoom = 1
            schemeHandler.backVideoFileURL = schemeHandler.backVideoFileURL2 ?? backVideoURL
            schemeHandler.backVideoFileURL2 = nil
            if let img = backImage {
                imageSchemeHandler.setBackSourceImage(img, slot: 0)
            } else {
                imageSchemeHandler.setBackSourceImage(nil, slot: 0)
            }
            imageSchemeHandler.backImageData = nil
            imageSchemeHandler.stampBackOnDemand = true
            // Clear slot 2
            backImage2 = nil
            backVideoURL2 = nil
            backSourceType2 = nil
            imageSchemeHandler.setBackSourceImage(nil, slot: 1)
            rememberKeptSlot(facing: .back, slot: 0)
            dropKeptSlot(facing: .back, slot: 1)
        }
    }

    private func clearSlot(facing: CameraFacing, slot: SequenceSlot) {
        switch (facing, slot) {
        case (.front, .one):
            frontImage = nil
            frontVideoURL = nil
            frontSourceType = nil
            schemeHandler.frontVideoFileURL = nil
            imageSchemeHandler.frontImageData = nil
            imageSchemeHandler.setFrontSourceImage(nil, slot: 0)
            if let old = convertedFrontVideoURL { try? FileManager.default.removeItem(at: old); convertedFrontVideoURL = nil }
            frontCrop = .identity
            facePrep = .empty
            facePrepError = nil
        case (.front, .two):
            frontImage2 = nil
            frontVideoURL2 = nil
            frontSourceType2 = nil
            schemeHandler.frontVideoFileURL2 = nil
            imageSchemeHandler.setFrontSourceImage(nil, slot: 1)
            if let old = convertedFrontVideoURL2 { try? FileManager.default.removeItem(at: old); convertedFrontVideoURL2 = nil }
            frontCrop2 = .identity
            facePrep = .empty
            facePrepError = nil
        case (.back, .one):
            backImage = nil
            backVideoURL = nil
            backSourceType = nil
            schemeHandler.backVideoFileURL = nil
            imageSchemeHandler.backImageData = nil
            imageSchemeHandler.setBackSourceImage(nil, slot: 0)
            if let old = convertedBackVideoURL { try? FileManager.default.removeItem(at: old); convertedBackVideoURL = nil }
            backCrop = .identity
        case (.back, .two):
            backImage2 = nil
            backVideoURL2 = nil
            backSourceType2 = nil
            schemeHandler.backVideoFileURL2 = nil
            imageSchemeHandler.setBackSourceImage(nil, slot: 1)
            if let old = convertedBackVideoURL2 { try? FileManager.default.removeItem(at: old); convertedBackVideoURL2 = nil }
            backCrop2 = .identity
        }
        dropKeptSlot(facing: facing, slot: slot.rawValue)
    }

    func clearAllSources() {
        clearSource(facing: .front)
        clearSource(facing: .back)
        isMediaActive = false
        isOverlayActive = false
        syncMediaToPage()
    }

    func clearAllSequences() {
        keptStills.clearAll()
        clearAllSources()
        imageSchemeHandler.clearAllSourceImages()
        frontQueueIndex = 0
        backQueueIndex = 0
        // Reset JS sequence counters
        webView?.evaluateJavaScript(
            "(function(){var s=\(StyleSheetProvider.fslStateAccessorJS);if(s){s.fi=0;s.bi=0;s.fseq=[];s.bseq=[];s.a=false;}})()",
            completionHandler: nil
        )
    }

    /// New media in a slot starts at today's cover-fit. Front still prep is tied
    /// to the still it was made from, so it is dropped when that still changes.
    private func resetSlotPresentation(facing: CameraFacing, slot: SequenceSlot) {
        switch (facing, slot) {
        case (.front, .one): frontCrop = .identity
        case (.front, .two): frontCrop2 = .identity
        case (.back, .one): backCrop = .identity
        case (.back, .two): backCrop2 = .identity
        }
        if facing == .front {
            facePrep = .empty
            facePrepError = nil
        }
        // A clip's live zoom belongs to the clip that was playing, so fresh
        // media starts back at the plain cover-fit.
        resetVideoZoom(facing: facing)
        setVideoSize(nil, facing: facing, slot: slot.rawValue)
        if isMediaActive { pushStillCrops() }
    }

    /// One slot's clip size, once it is known.
    func videoSize(facing: CameraFacing, slot: Int) -> CGSize? {
        switch (facing, slot) {
        case (.front, 0): frontVideoSize
        case (.front, _): frontVideoSize2
        case (.back, 0): backVideoSize
        case (.back, _): backVideoSize2
        }
    }

    func setVideoSize(_ size: CGSize?, facing: CameraFacing, slot: Int) {
        switch (facing, slot) {
        case (.front, 0): frontVideoSize = size
        case (.front, _): frontVideoSize2 = size
        case (.back, 0): backVideoSize = size
        case (.back, _): backVideoSize2 = size
        }
    }

    /// Drops one camera's live clip zoom back to the untouched fit.
    func resetVideoZoom(facing: CameraFacing) {
        let current = facing == .front ? frontVideoZoom : backVideoZoom
        guard current != 1 else { return }
        if facing == .front { frontVideoZoom = 1 } else { backVideoZoom = 1 }
        pushVideoZoom()
    }

    /// Keeps the mirrored queue positions inside the slots that still exist.
    private func clampQueueIndices() {
        if frontQueueIndex >= frontSlotCount { frontQueueIndex = 0 }
        if backQueueIndex >= backSlotCount { backQueueIndex = 0 }
    }

    func setMediaActive(_ active: Bool) {
        guard hasSource || !active else { return }
        let wasActive = isMediaActive
        isMediaActive = active
        updateUserScripts()
        syncMediaToPage()
        if wasActive && !active {
            finishInjectSession(reason: "Enable Media turned off", autoOff: false)
        }
    }

    // MARK: - Stealth

    var stealthOptions: StyleSheetProvider.StealthOptions {
        StyleSheetProvider.StealthOptions(
            nativePickerMode: nativePickerMode,
            captureButtonPolicy: captureButtonHandling.jsValue,
            accessorHardening: accessorHardening,
            maskWrappersAsNative: maskWrappersAsNative
        )
    }

    /// Human-readable summary of what a site would currently observe.
    var stealthStatusSummary: String {
        var active: [String] = []
        if nativePickerMode {
            active.append("Native picker (\(captureButtonHandling.label.lowercased()))")
        }
        if accessorHardening {
            active.append(maskWrappersAsNative ? "Hardened + masked" : "Hardened")
        }
        return active.isEmpty ? "Standard \u{2014} automatic hand-off, both signals detectable." : active.joined(separator: " \u{00B7} ")
    }

    /// Applies options that only take effect while the page is being set up.
    /// The injected patch installs at document start, so the page is reloaded.
    func applyStealthOptionsRequiringReload() {
        updateUserScripts()
        if webView?.url == nil {
            showStealthNotice("Applied. Takes effect on the next page you open.")
            return
        }
        showStealthNotice("Reloading page to apply\u{2026}")
        webView?.reload()
    }

    private func showStealthNotice(_ message: String) {
        stealthNotice = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, self.stealthNotice == message else { return }
            self.stealthNotice = nil
        }
    }

    /// Applies options the injected script reads at request time — no reload needed.
    func applyLiveStealthOptions() {
        stealthNotice = nil
        updateUserScripts()
        guard let webView else { return }
        let js = """
        (function(){var s=\(StyleSheetProvider.fslStateAccessorJS);if(!s)return;\
        s.np=\(nativePickerMode);s.capMode='\(captureButtonHandling.jsValue)';})()
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Device-matched media layer

    /// Current switch state, written into the page. All-off writes only `false`
    /// and `null`, which is what the patch script already installed.
    var shouldReportStatus: Bool {
        behavior.settings.showControlPill
            || behavior.settings.showObservedHUD
            || behavior.settings.autoOffAfterOnePass
            || behavior.settings.showSequenceRecap
    }

    var behaviorScript: String {
        StyleSheetProvider.behaviorApplyScript(
            settings: behavior.settings,
            audit: behavior.audit,
            reportStatus: shouldReportStatus,
            motionFrozen: isMotionFrozen,
            identitySecret: behavior.settings.useAuditProfile ? behavior.identitySecret : "",
            frontCrop: frontCrop,
            frontCrop2: frontCrop2,
            backCrop: backCrop,
            backCrop2: backCrop2,
            frontVideoZoom: frontVideoZoom,
            backVideoZoom: backVideoZoom
        )
    }

    /// Per-site state, applied once the page being loaded is really known.
    ///
    /// The document-start script is prepared before the app knows where it is
    /// going and is shared by every site, so anything that belongs to one site
    /// has to land here instead.
    func applySiteState() {
        guard let webView else { return }
        let granted = behavior.settings.useAuditProfile
            && behavior.isCameraGranted(host: currentURL?.host())
        let micGranted = behavior.settings.useAuditProfile
            && behavior.isMicrophoneGranted(host: currentURL?.host())
        webView.evaluateJavaScript(
            StyleSheetProvider.siteStateScript(cameraGranted: granted, microphoneGranted: micGranted),
            completionHandler: nil
        )
    }

    /// Pushes the new switches into the live page. Nothing here needs a reload.
    ///
    /// Applies the profile first and the switches second, the same order the page
    /// uses at document start, so a live update can never land differently.
    func applyBehaviorSettings() {
        updateUserScripts()
        if let webView {
            // The version is settable, so the request header has to follow it too.
            // Leaving it behind would let the header and the page's own answers
            // name two different versions.
            webView.customUserAgent = StyleSheetProvider.safariUserAgent(for: behavior.audit)
            if let profile = activeProfile {
                webView.evaluateJavaScript(
                    StyleSheetProvider.profileApplyScript(
                        from: profile,
                        skipEnvironmentLocks: behavior.settings.graphicsAlignment
                    ),
                    completionHandler: nil
                )
            }
            webView.evaluateJavaScript(behaviorScript, completionHandler: nil)
        }
        if !behavior.settings.showControlPill && !behavior.settings.showObservedHUD {
            activeStreamFacing = nil
            isLiveStreamActive = false
        }
        // Grants may have been revoked by the change, so push this site's fresh
        // answer instead of letting the old one linger.
        applySiteState()
    }

    // MARK: - Freeze

    /// True when this site's live picture is being held still.
    var isMotionFrozen: Bool {
        behavior.isFrozen(host: currentURL?.host())
    }

    /// Holds the live picture still for this site, or lets it move again.
    ///
    /// Only ever affects the live feed. Files, the photo chooser and the native
    /// camera never see this.
    func toggleMotionFreeze() {
        guard let host = currentURL?.host(), !host.isEmpty else { return }
        let frozen = !behavior.isFrozen(host: host)
        behavior.setFrozen(frozen, host: host)
        webView?.evaluateJavaScript(
            StyleSheetProvider.freezeScript(frozen: frozen),
            completionHandler: nil
        )
        if !frozen { motionEasedLevel = 0 }
    }

    /// The pill's Next button.
    ///
    /// A camera that is already live fades itself over to the next item in its
    /// own queue, which is the only way a call reads the change as movement
    /// rather than a cut. With nothing live this is the plain queue step it has
    /// always been. Never touches files, the photo chooser or the real camera.
    func nextMedia() {
        guard let webView else {
            advanceBothQueues()
            return
        }
        webView.evaluateJavaScript(StyleSheetProvider.fadeNextScript) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                let outcome = (result as? String) ?? "none"
                if outcome == "busy" { return }
                guard outcome.hasPrefix("fade") else {
                    self.advanceBothQueues()
                    return
                }
                let parts = outcome.split(separator: ":")
                if parts.count == 3 {
                    self.frontQueueIndex = Int(parts[1]) ?? self.frontQueueIndex
                    self.backQueueIndex = Int(parts[2]) ?? self.backQueueIndex
                }
                // Only the live camera's queue moved, so flash only that one.
                self.markMediaFading()
            }
        }
    }

    /// Clears what the page is holding and sends the current media in again.
    ///
    /// Three things go wrong that look identical from the outside: a running
    /// feed keeps painting the previous item because a handover never finished,
    /// the draw loop stopped booking frames so the picture is frozen, or media
    /// was loaded while nothing was live and the page never picked it up. This
    /// answers all three from one button, always repeating the item that should
    /// be showing rather than skipping to the next one.
    ///
    /// Live feed only — files, the photo chooser and the native camera are never
    /// touched, and the site's own stream is never renegotiated.
    func forceReinject() {
        guard hasSource else {
            markReinjected("Nothing loaded to send")
            return
        }
        guard let webView else {
            markReinjected("No page open")
            return
        }

        // Media switched off is itself a reason nothing is arriving, so the
        // button turns it back on rather than reporting a failure.
        if !isMediaActive {
            setMediaActive(true)
            markReinjected("Media switched back on")
            return
        }

        webView.evaluateJavaScript(StyleSheetProvider.forceReinjectScript) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                switch (result as? String) ?? "idle" {
                case "live":
                    // The page keeps its own queue pointer, so read the frame
                    // back in case the rebuild changed what is being drawn into.
                    self.refreshLiveFrameSize()
                    self.markReinjected("Feed re-sent")
                case "cleared":
                    self.refreshLiveFrameSize()
                    self.markReinjected("Cleared a stuck change")
                default:
                    // Nothing was live to repair, so the media state itself is
                    // sent again — which is what an idle page needs to pick up
                    // media that was loaded after it last asked.
                    self.updateUserScripts()
                    self.syncMediaToPage()
                    self.markReinjected("Media re-sent to the page")
                }
            }
        }
    }

    /// Keeps the re-inject button lit and shows what it did, briefly.
    private func markReinjected(_ notice: String) {
        reinjectToken &+= 1
        let token = reinjectToken
        isReinjecting = true
        reinjectNotice = notice
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(620))
            guard let self, self.reinjectToken == token else { return }
            self.isReinjecting = false
            try? await Task.sleep(for: .milliseconds(1800))
            guard self.reinjectToken == token else { return }
            self.reinjectNotice = nil
        }
    }

    /// Keeps the pill's Next button lit for as long as the change is running.
    private func markMediaFading() {
        mediaFadeToken &+= 1
        let token = mediaFadeToken
        isFadingMedia = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(820))
            guard let self, self.mediaFadeToken == token else { return }
            self.isFadingMedia = false
        }
    }

    /// Advances both camera queues, mirroring the pill's Next button.
    func advanceBothQueues() {
        guard let webView else {
            frontQueueIndex = nextIndex(frontQueueIndex, count: frontSlotCount)
            backQueueIndex = nextIndex(backQueueIndex, count: backSlotCount)
            return
        }
        webView.evaluateJavaScript(StyleSheetProvider.advanceBothQueuesScript) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                if let text = result as? String {
                    let parts = text.split(separator: ":")
                    if parts.count == 2 {
                        self.frontQueueIndex = Int(parts[0]) ?? self.frontQueueIndex
                        self.backQueueIndex = Int(parts[1]) ?? self.backQueueIndex
                    }
                } else {
                    self.frontQueueIndex = self.nextIndex(self.frontQueueIndex, count: self.frontSlotCount)
                    self.backQueueIndex = self.nextIndex(self.backQueueIndex, count: self.backSlotCount)
                }
            }
        }
    }

    private func nextIndex(_ current: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }
        return (current + 1) % count
    }

    /// Swaps media 1 and media 2 for a camera without re-converting either item.
    func swapSlots(facing: CameraFacing) {
        switch facing {
        case .front:
            guard frontSourceType != nil, frontSourceType2 != nil else { return }
            swap(&frontImage, &frontImage2)
            swap(&frontVideoURL, &frontVideoURL2)
            swap(&frontSourceType, &frontSourceType2)
            swap(&convertedFrontVideoURL, &convertedFrontVideoURL2)
            swap(&frontCrop, &frontCrop2)
            let handlerOne = schemeHandler.frontVideoFileURL
            schemeHandler.frontVideoFileURL = schemeHandler.frontVideoFileURL2
            schemeHandler.frontVideoFileURL2 = handlerOne
            imageSchemeHandler.setFrontSourceImage(frontImage, slot: 0)
            imageSchemeHandler.setFrontSourceImage(frontImage2, slot: 1)
            imageSchemeHandler.frontImageData = nil
        case .back:
            guard backSourceType != nil, backSourceType2 != nil else { return }
            swap(&backImage, &backImage2)
            swap(&backVideoURL, &backVideoURL2)
            swap(&backSourceType, &backSourceType2)
            swap(&convertedBackVideoURL, &convertedBackVideoURL2)
            swap(&backCrop, &backCrop2)
            let handlerOne = schemeHandler.backVideoFileURL
            schemeHandler.backVideoFileURL = schemeHandler.backVideoFileURL2
            schemeHandler.backVideoFileURL2 = handlerOne
            imageSchemeHandler.setBackSourceImage(backImage, slot: 0)
            imageSchemeHandler.setBackSourceImage(backImage2, slot: 1)
            imageSchemeHandler.backImageData = nil
            imageSchemeHandler.stampBackOnDemand = true
        }
        rememberKeptSlot(facing: facing, slot: 0)
        rememberKeptSlot(facing: facing, slot: 1)
        syncMediaToPage()
    }

    // MARK: - Page messages

    /// Status ping from the page: which camera is being pulled, and where the
    /// queues currently sit. Only sent while the pill is switched on.
    func handleStatusMessage(_ payload: [String: Any]) {
        if let refused = payload["refused"] as? String {
            let name = payload["name"] as? String ?? "OverconstrainedError"
            let message = payload["message"] as? String ?? "Invalid constraint"
            lastRefusalSummary = "\(refused) — \(name): \(message)"
            logRefusal(constraint: refused, name: name, message: message,
                       url: payload["url"] as? String ?? currentURL?.absoluteString ?? "")
            return
        }

        // The page eased motion off to keep the feed smooth.
        if let eased = payload["eased"] as? Int {
            motionEasedLevel = max(motionEasedLevel, eased)
            return
        }

        if payload["served"] as? Bool == true {
            handleServedPayload(payload)
        }
        if payload["pass"] as? Bool == true {
            if payload["done"] as? Bool == true {
                checkOnePassComplete()
            }
        }

        if let index = payload["fi"] as? Int { frontQueueIndex = index }
        if let index = payload["bi"] as? Int { backQueueIndex = index }
        let isQueueOnly = payload["queue"] as? Bool ?? false
        if !isQueueOnly {
            let active = payload["active"] as? Bool ?? false
            let wasActive = isLiveStreamActive
            isLiveStreamActive = active
            if active {
                // A site that has opened a feed has been granted a camera, and a
                // real phone remembers that per site: on the next visit the full
                // named device list is there from the first moment.
                behavior.markCameraGranted(host: currentURL?.host())
                // Sound is its own grant. Only a request that asked for audio
                // records one.
                if payload["audio"] as? Bool == true {
                    behavior.markMicrophoneGranted(host: currentURL?.host())
                }
                noteSessionStartedIfNeeded()
                injectSession.lastActiveAt = Date()
                updateObservedFeed(from: payload, active: true)
                // The frame the page is really drawing into, so live zoom and
                // per-shape framing act on the very frame the site is sent.
                if let width = payload["cw"] as? Int, let height = payload["ch"] as? Int,
                   width > 0, height > 0 {
                    liveFrameSize = CGSize(width: width, height: height)
                }
            }
            if active, let facing = payload["facing"] as? String, !facing.isEmpty {
                activeStreamFacing = facing == "environment" ? .back : .front
            } else if !active {
                activeStreamFacing = nil
                motionEasedLevel = 0
                liveFrameSize = nil
                // A clip's live zoom belongs to the feed that was running.
                resetVideoZoom(facing: .front)
                resetVideoZoom(facing: .back)
                if wasActive {
                    injectSession.lastInactiveAt = Date()
                }
                if var snap = observedFeed {
                    snap.isActive = false
                    snap.pageHoldsFeed = false
                    observedFeed = snap
                }
                checkOnePassComplete()
            }
        }

    }

    /// A site is asking for media and the prompt is switched on for that path.
    func handlePromptMessage(_ payload: [String: Any]) {
        guard let id = payload["id"] as? Int else { return }
        let kindRaw = payload["kind"] as? String ?? "live"
        let kind: MediaRequestKind = kindRaw == "file" ? .file : .live
        let pageURL = payload["url"] as? String ?? currentURL?.absoluteString ?? ""
        let host = URL(string: pageURL)?.host() ?? currentURL?.host() ?? ""

        let enabled = kind == .live
            ? behavior.settings.promptLiveRequests
            : behavior.settings.promptFileRequests

        // Silenced site, switch turned off mid-flight, or a prompt already up:
        // let the request through on its own defaults rather than stacking cards.
        guard enabled, behavior.shouldPrompt(host: host), pendingPrompt == nil else {
            resolvePrompt(id: id, decision: .proceed)
            return
        }

        let info = payload["info"] as? [String: Any] ?? [:]
        let requestedFacing = info["facing"] as? String
        let resolvedFacing: CameraFacing
        if requestedFacing == "environment" {
            resolvedFacing = .back
        } else if requestedFacing == "user" {
            resolvedFacing = .front
        } else {
            resolvedFacing = defaultFacingWhenUnspecified
        }

        pendingPrompt = MediaRequestPrompt(
            id: id,
            kind: kind,
            host: host,
            pageURL: pageURL,
            requestedFacing: requestedFacing,
            requestedWidth: (info["width"] as? NSNumber)?.intValue,
            requestedHeight: (info["height"] as? NSNumber)?.intValue,
            requestedFrameRate: (info["frameRate"] as? NSNumber)?.doubleValue,
            wantsAudio: info["audio"] as? Bool ?? false,
            accept: info["accept"] as? String,
            resolvedFacing: resolvedFacing
        )
    }

    /// Drops a waiting card whose page is going away.
    ///
    /// No decision is sent: the id belonged to the old document, and that document
    /// resolves itself on the site's own defaults through its own timeout.
    func discardPendingPrompt() {
        pendingPrompt = nil
    }

    /// Hands the decision back to the waiting page and clears the card.
    func resolvePrompt(id: Int, decision: MediaRequestDecision) {
        let prompt = pendingPrompt?.id == id ? pendingPrompt : nil
        if pendingPrompt?.id == id { pendingPrompt = nil }
        webView?.evaluateJavaScript(
            StyleSheetProvider.resolvePromptScript(id: id, decision: decision),
            completionHandler: nil
        )
        if let prompt {
            recordPromptDecision(prompt, decision)
        }
    }

    private func logRefusal(constraint: String, name: String, message: String, url: String) {
        constraintLog.addEntry(
            ConstraintLogEntry(
                timestamp: Date(),
                siteURL: url,
                requestedConstraints: "hard \(constraint) outside audited limits",
                negotiatedResult: "\(name): \(message)",
                fallbackReason: "Refused exactly as the audited hardware refused it",
                wasSuccessful: false
            )
        )
    }

    /// Writes the prepared media for a slot into the photo library so the real iOS
    /// picker can hand it to the page. Back photos keep the native sensor template.
    func saveSlotToPhotos(facing: CameraFacing, slot: SequenceSlot) async {
        let image: UIImage?
        let videoURL: URL?
        let type: SourceMediaType?

        switch (facing, slot) {
        case (.front, .one):
            image = frontImage; videoURL = frontVideoURL; type = frontSourceType
        case (.front, .two):
            image = frontImage2; videoURL = frontVideoURL2; type = frontSourceType2
        case (.back, .one):
            image = backImage; videoURL = backVideoURL; type = backSourceType
        case (.back, .two):
            image = backImage2; videoURL = backVideoURL2; type = backSourceType2
        }

        guard let type else {
            photoSaveStatus = "Nothing loaded in that slot."
            return
        }

        do {
            switch type {
            case .video:
                guard let videoURL else {
                    photoSaveStatus = "Video file is missing."
                    return
                }
                try await photoLibrary.saveVideo(at: videoURL)
            case .image:
                guard let image else {
                    photoSaveStatus = "Photo is missing."
                    return
                }
                let data = buildPhotoDataForLibrary(image: image, facing: facing)
                guard let data else {
                    photoSaveStatus = "Could not prepare the photo."
                    return
                }
                try await photoLibrary.saveJPEG(data)
            }
            photoSaveStatus = "Saved to Photos. Pick it from the site's button."
        } catch {
            photoSaveStatus = error.localizedDescription
        }
    }

    private func buildPhotoDataForLibrary(image: UIImage, facing: CameraFacing) -> Data? {
        if facing == .back {
            return exifService.nativeBackCameraJPEG(from: image, capturedAt: Date())
        }
        let camera = activeProfile?.frontCamera
        return exifService.jpegDataWithEXIF(
            image: resizeForWeb(image, facing: .front),
            camera: camera,
            hardware: nil,
            capturedAt: Date()
        )
    }

    func updateUserScripts() {
        guard let webView else { return }
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()

        controller.addUserScript(WKUserScript(
            source: StyleSheetProvider.patchScript(stealth: stealthOptions),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        if let profile = activeProfile {
            let profileJS = StyleSheetProvider.profileApplyScript(
                from: profile,
                skipEnvironmentLocks: behavior.settings.graphicsAlignment
            )
            controller.addUserScript(WKUserScript(
                source: profileJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }

        // Runs after the profile so audited values win when the switch is on.
        controller.addUserScript(WKUserScript(
            source: behaviorScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        controller.addUserScript(WKUserScript(
            source: StyleSheetProvider.constraintLoggingScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        if isMediaActive, hasSource {
            let stateJS = buildStateJS()
            controller.addUserScript(WKUserScript(
                source: stateJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }
    }

    func syncMediaToPage() {
        guard let webView else { return }

        if frontSourceType == .video, let url = frontVideoURL {
            schemeHandler.frontVideoFileURL = url
        }
        if frontSourceType2 == .video, let url = frontVideoURL2 {
            schemeHandler.frontVideoFileURL2 = url
        }
        if backSourceType == .video, let url = backVideoURL {
            schemeHandler.backVideoFileURL = url
        }
        if backSourceType2 == .video, let url = backVideoURL2 {
            schemeHandler.backVideoFileURL2 = url
        }

        if let profile = activeProfile {
            let profileJS = StyleSheetProvider.profileApplyScript(
                from: profile,
                skipEnvironmentLocks: behavior.settings.graphicsAlignment
            )
            webView.evaluateJavaScript(profileJS, completionHandler: nil)
        }

        webView.evaluateJavaScript(behaviorScript, completionHandler: nil)
        applySiteState()

        if !isMediaActive || !hasSource {
            webView.evaluateJavaScript(
                "(function(){var s=\(StyleSheetProvider.fslStateAccessorJS);if(s){s.a=false;}try{navigator.mediaDevices.dispatchEvent(new Event('devicechange'));}catch(e){}})()",
                completionHandler: nil
            )
            return
        }

        let js = buildStateJS()
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func resizeForWeb(_ image: UIImage, facing: CameraFacing) -> UIImage {
        let cam: CameraDeviceSpec? = facing == .front ? activeProfile?.frontCamera : activeProfile?.backCamera
        if let profile = activeProfile, let cam {
            let spec = profile.conversionSpec(for: cam)
            return mediaConverter.resizeImageForInjection(image, spec: spec)
        }

        let maxDim: CGFloat = 1280
        let size = image.size
        guard size.width > maxDim || size.height > maxDim else { return image }
        let scale = min(maxDim / size.width, maxDim / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func buildStateJS() -> String {
        let replaceAll = mediaMode == .replaceAll
        let defFacing = defaultFacingWhenUnspecified == .back ? "environment" : "user"
        let adv = advanceMode.jsValue

        guard hasSource else {
            return "(function(){var s=\(StyleSheetProvider.fslStateAccessorJS);if(s){s.a=false;}})()"
        }

        // Build sequence arrays. Images use data URLs for live canvas;
        // back file capture still goes through fslimage:// with slot index for on-demand EXIF.
        var frontSeqJSON: [String] = []
        var backSeqJSON: [String] = []

        // Front slot 1
        if frontSourceType == .image, let img = frontImage,
           let data = resizeForWeb(img, facing: .front).jpegData(compressionQuality: 0.85) {
            let b64 = data.base64EncodedString()
            frontSeqJSON.append("{t:'i',u:'data:image/jpeg;base64,\(b64)',i:0}")
        } else if frontSourceType == .video, frontVideoURL != nil {
            frontSeqJSON.append("{t:'v',u:'fslvideo://front',i:0}")
        }

        // Front slot 2
        if frontSourceType2 == .image, let img = frontImage2,
           let data = resizeForWeb(img, facing: .front).jpegData(compressionQuality: 0.85) {
            let b64 = data.base64EncodedString()
            frontSeqJSON.append("{t:'i',u:'data:image/jpeg;base64,\(b64)',i:1}")
        } else if frontSourceType2 == .video, frontVideoURL2 != nil {
            frontSeqJSON.append("{t:'v',u:'fslvideo://front2',i:1}")
        }

        // Back slot 1
        if backSourceType == .image, let img = backImage,
           let data = resizeForWeb(img, facing: .back).jpegData(compressionQuality: 0.85) {
            let b64 = data.base64EncodedString()
            // Live canvas uses data URL; file path uses fslimage with slot
            backSeqJSON.append("{t:'i',u:'data:image/jpeg;base64,\(b64)',i:0}")
            imageSchemeHandler.setBackSourceImage(img, slot: 0)
        } else if backSourceType == .video, backVideoURL != nil {
            backSeqJSON.append("{t:'v',u:'fslvideo://back',i:0}")
        }

        // Back slot 2
        if backSourceType2 == .image, let img = backImage2,
           let data = resizeForWeb(img, facing: .back).jpegData(compressionQuality: 0.85) {
            let b64 = data.base64EncodedString()
            backSeqJSON.append("{t:'i',u:'data:image/jpeg;base64,\(b64)',i:1}")
            imageSchemeHandler.setBackSourceImage(img, slot: 1)
        } else if backSourceType2 == .video, backVideoURL2 != nil {
            backSeqJSON.append("{t:'v',u:'fslvideo://back2',i:1}")
        }

        // Legacy single-source fields for compatibility / first item quick path
        var lines: [String] = [
            "(function(){",
            "var s=\(StyleSheetProvider.fslStateAccessorJS);",
            "if(!s)return;",
            "s.a=true;",
            "s.ra=\(replaceAll);",
            "s.adv='\(adv)';",
            "s.defFacing='\(defFacing)';",
            "s.np=\(nativePickerMode);",
            "s.capMode='\(captureButtonHandling.jsValue)';",
            "s.is=null;s.vs=null;",
            "s.fis=null;s.fvs=null;",
            "s.bis=null;s.bvs=null;",
            "s.fseq=[\(frontSeqJSON.joined(separator: ","))];",
            "s.bseq=[\(backSeqJSON.joined(separator: ","))];",
            "if(typeof s.fi!=='number')s.fi=0;",
            "if(typeof s.bi!=='number')s.bi=0;",
            "if(s.fi>=s.fseq.length)s.fi=0;",
            "if(s.bi>=s.bseq.length)s.bi=0;"
        ]

        // Also set legacy fis/fvs/bis/bvs from first sequence items for older code paths
        if let first = frontSeqJSON.first {
            if first.contains("t:'i'") {
                // extract not needed — set from source
                if frontSourceType == .image, let img = frontImage,
                   let data = resizeForWeb(img, facing: .front).jpegData(compressionQuality: 0.85) {
                    lines.append("s.fis='data:image/jpeg;base64,\(data.base64EncodedString())';")
                }
            } else {
                lines.append("s.fvs='fslvideo://front';")
            }
        }
        if let first = backSeqJSON.first {
            if first.contains("t:'i'") {
                if backSourceType == .image, let img = backImage,
                   let data = resizeForWeb(img, facing: .back).jpegData(compressionQuality: 0.85) {
                    lines.append("s.bis='data:image/jpeg;base64,\(data.base64EncodedString())';")
                }
            } else {
                lines.append("s.bvs='fslvideo://back';")
            }
        }

        lines.append("try{navigator.mediaDevices.dispatchEvent(new Event('devicechange'));}catch(e){}")
        lines.append("})();")

        return lines.joined(separator: "\n")
    }

    func burnEverything() async {
        isBurning = true

        clearAllSequences()

        bookmarks.removeAll()
        UserDefaults.standard.removeObject(forKey: bookmarksKey)

        let dataStore = WKWebsiteDataStore.default()
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: allTypes)
        await dataStore.removeData(ofTypes: allTypes, for: records)

        let cookieStore = dataStore.httpCookieStore
        let cookies = await cookieStore.allCookies()
        for cookie in cookies {
            await cookieStore.deleteCookie(cookie)
        }

        URLCache.shared.removeAllCachedResponses()

        if let cookiesURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Cookies") {
            try? FileManager.default.removeItem(at: cookiesURL)
        }

        webView?.configuration.userContentController.removeAllUserScripts()

        goHome()

        isBurning = false
    }

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
              let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) else { return }
        bookmarks = decoded
    }

    private func saveBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: bookmarksKey)
    }

    // MARK: - Constraint Log Integration

    private func parseJSTimestamp(from entry: [String: Any]) -> Date {
        if let ts = entry["timestamp"] as? Double {
            return Date(timeIntervalSince1970: ts / 1000.0)
        }
        return Date()
    }

    func fetchConstraintLogs() {
        guard let webView else { return }
        webView.evaluateJavaScript(StyleSheetProvider.constraintLogReadScript) { [weak self] result, _ in
            guard let self, let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !entries.isEmpty else { return }

            let profileName = self.activeProfile?.name ?? "Unknown"
            let logEntries = entries.map { entry -> ConstraintLogEntry in
                ConstraintLogEntry(
                    timestamp: self.parseJSTimestamp(from: entry),
                    siteURL: entry["url"] as? String ?? "",
                    requestedConstraints: entry["constraints"] as? String ?? "",
                    negotiatedResult: entry["result"] as? String ?? "",
                    fallbackReason: entry["fallbackReason"] as? String,
                    wasSuccessful: entry["wasSuccessful"] as? Bool ?? false
                )
            }
            let siteEntries = entries.map { entry -> SiteHistoryEntry in
                SiteHistoryEntry(
                    siteURL: entry["url"] as? String ?? "",
                    timestamp: self.parseJSTimestamp(from: entry),
                    requestedConstraints: entry["constraints"] as? String ?? "",
                    actualSettings: entry["result"] as? String ?? "",
                    profileUsed: profileName,
                    wasSuccessful: entry["wasSuccessful"] as? Bool ?? false
                )
            }

            Task { @MainActor in
                self.constraintLog.addEntries(logEntries)
                self.siteHistory.addEntries(siteEntries)
            }

            webView.evaluateJavaScript(StyleSheetProvider.constraintLogClearScript, completionHandler: nil)
        }
    }
}
