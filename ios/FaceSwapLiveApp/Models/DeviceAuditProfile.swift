import Foundation

/// One of the fixed frame sizes a camera really snaps to.
///
/// Real hardware does not scale smoothly. It jumps to one of a short list of
/// modes, so the list is stored verbatim and in the order the platform gave it.
nonisolated struct AuditMode: Codable, Sendable, Hashable {
    var width: Int
    var height: Int

    var aspectRatio: Double {
        height == 0 ? 0 : Double(width) / Double(height)
    }

    var summary: String { "\(width)×\(height)" }
}

/// One camera exactly as the audited iPhone reported it to Safari.
nonisolated struct AuditCamera: Codable, Sendable, Identifiable {
    var id: String { deviceIdPrefix }

    /// Position in the list `enumerateDevices()` returned on the real device.
    var order: Int
    var label: String
    /// `user` or `environment`.
    var facingMode: String
    /// The handle the audit recorded for this camera.
    var deviceIdPrefix: String

    /// Every size this camera granted, in the order the platform listed them.
    var modes: [AuditMode]
    /// The rates it advertised. Nothing between these is real.
    var frameRateSteps: [Double]

    /// What an unconstrained request comes back as — the portrait default.
    var defaultMode: AuditMode
    /// What an "as large as possible" request silently substitutes to.
    var nativeMaxMode: AuditMode
    /// Rate every granted request came back at.
    var grantedFrameRate: Double

    /// Measured milliseconds for the native-maximum request on this camera.
    var nativeMaxOpenMs: Double

    var minZoom: Double
    var maxZoom: Double
    /// Empty on the cameras that published no white-balance control at all.
    var whiteBalanceModes: [String]
    /// Only the multi-lens back camera published a torch.
    var hasTorch: Bool

    // MARK: Derived from the measured modes

    /// Largest size this camera granted. Per camera — not one global ceiling.
    var maxWidth: Int { nativeMaxMode.width }
    var maxHeight: Int { nativeMaxMode.height }
    /// A single pixel was granted on every camera the audit reached.
    var minWidth: Int { 1 }
    var minHeight: Int { 1 }
    var aspectRatio: Double { nativeMaxMode.aspectRatio }

    var maxFrameRate: Double { frameRateSteps.max() ?? 30 }
    var minFrameRate: Double { frameRateSteps.min() ?? 30 }

    var grantedWidth: Int { nativeMaxMode.width }
    var grantedHeight: Int { nativeMaxMode.height }
    /// The rate the platform reported. The audit measured no separate figure,
    /// so this is the reported one rather than an invented near-miss.
    var measuredFrameRate: Double { grantedFrameRate }

    var supportsWhiteBalance: Bool { !whiteBalanceModes.isEmpty }
    var supportsZoomBelowOne: Bool { minZoom < 1 }

    /// Deterministic full-length identifier built from the captured handle so the
    /// same value is reported on every launch and across relaunches.
    var deviceId: String { AuditIdentifier.expand(deviceIdPrefix) }
    var groupId: String { AuditIdentifier.expand(deviceIdPrefix, salt: 0x9E37) }

    var isFront: Bool { facingMode == "user" }
    var resolutionSummary: String { "\(maxWidth)×\(maxHeight)" }

    /// Limits for this one camera, for the refusal path.
    var limits: AuditCapabilityLimits {
        AuditCapabilityLimits(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            minWidth: minWidth,
            minHeight: minHeight,
            maxFrameRate: maxFrameRate,
            minFrameRate: minFrameRate,
            rejectionErrorName: AuditRefusal.overconstrainedName,
            rejectionErrorMessage: AuditRefusal.invalidConstraintMessage
        )
    }

    /// Width an aspect-only request is answered from.
    ///
    /// The readings pin this precisely: an exact 16:9 ask comes back 640×359, not
    /// 640×360, which only happens if the height is truncated from a 640 base.
    static let aspectBaseWidth = 640
    static let fallbackAspect = 1.3333

    /// The size this camera answers a given request with.
    ///
    /// Matches what the readings actually show: an explicit size is honoured as
    /// asked, a missing dimension is filled in at 4:3, an aspect-only ask is
    /// answered from a 640-wide base by truncation, and anything past this
    /// camera's own ceiling comes back as its maximum rather than being refused.
    ///
    /// - Parameters:
    ///   - width: requested width, or `nil` when the site did not ask.
    ///   - height: requested height, or `nil` when the site did not ask.
    ///   - aspect: requested aspect ratio, or `nil`.
    func resolveMode(width: Int?, height: Int?, aspect: Double?) -> AuditMode {
        var out: AuditMode
        if let w = width, let h = height, w > 0, h > 0 {
            out = AuditMode(width: w, height: h)
        } else if let w = width, w > 0 {
            out = AuditMode(width: w, height: Int(Double(w) / Self.fallbackAspect))
        } else if let h = height, h > 0 {
            out = AuditMode(width: Int(Double(h) * Self.fallbackAspect), height: h)
        } else if let a = aspect, a > 0 {
            let base = Self.aspectBaseWidth
            out = AuditMode(width: base, height: Int(Double(base) / a))
        } else {
            return defaultMode
        }

        if out.width > nativeMaxMode.width || out.height > nativeMaxMode.height {
            return nativeMaxMode
        }
        return AuditMode(width: max(1, out.width), height: max(1, out.height))
    }

    /// Nearest advertised rate. Nothing between the steps exists on real hardware.
    func resolveFrameRate(_ requested: Double?) -> Double {
        guard let requested, requested > 0 else { return grantedFrameRate }
        return frameRateSteps.min {
            abs($0 - requested) < abs($1 - requested)
        } ?? grantedFrameRate
    }
}

/// One audio input as the audited device reported it.
///
/// Audio inputs share a group with a camera but never share an identity — the
/// audit is explicit that a shared group is what makes grouping possible.
nonisolated struct AuditMicrophone: Codable, Sendable, Identifiable {
    var id: String { deviceIdPrefix }

    var order: Int
    var label: String
    var deviceIdPrefix: String
    /// Handle of the camera this input shares a group with.
    var groupWithCameraPrefix: String?

    var sampleRate: Int
    var sampleSize: Int
    var channelCount: Int
    var echoCancellation: Bool
    var autoGainControl: Bool
    var noiseSuppression: Bool
    /// Reported input delay, in seconds, matching the audited audio stack.
    var latency: Double

    var deviceId: String { AuditIdentifier.expand(deviceIdPrefix, salt: 0x51ED) }

    /// Falls back to its own handle only when it is not grouped with a camera.
    func groupId(in cameras: [AuditCamera]) -> String {
        if let prefix = groupWithCameraPrefix,
           let camera = cameras.first(where: { $0.deviceIdPrefix == prefix }) {
            return camera.groupId
        }
        return AuditIdentifier.expand(deviceIdPrefix, salt: 0x9E37)
    }
}

/// The audio stack as measured, in the units the page reads them in.
nonisolated struct AuditAudioStack: Codable, Sendable {
    var sampleRate: Int
    /// Seconds, as `AudioContext.baseLatency` reports it.
    var baseLatency: Double
    var outputLatency: Double
    var maxChannels: Int
    /// State a freshly created context starts in.
    var initialState: String
}

/// The full graphics answer sheet the audit captured.
nonisolated struct AuditGraphicsDetail: Codable, Sendable {
    var glVersion: String
    var maxTextureSize: Int
    var maxCubeMapSize: Int
    var maxRenderbufferSize: Int
    var maxViewportWidth: Int
    var maxViewportHeight: Int
    var maxVertexAttributes: Int
    var maxVertexUniformVectors: Int
    var maxFragmentUniformVectors: Int
    var maxVaryingVectors: Int
    var maxTextureImageUnits: Int
    var maxCombinedTextureUnits: Int
    var aliasedLineWidthRange: [Int]
    var aliasedPointSizeRange: [Int]
    var colorBits: Int
    var depthBits: Int
    var stencilBits: Int
    var maxAnisotropy: Int
    var extensions: [String]

    var extensionCount: Int { extensions.count }
}

/// Display characteristics the audit measured.
nonisolated struct AuditDisplay: Codable, Sendable {
    var logicalWidth: Int
    var logicalHeight: Int
    var physicalWidth: Int
    var physicalHeight: Int
    var devicePixelRatio: Double
    var colorDepth: Int
    /// `true` when the screen reported Display P3 or wider.
    var wideGamut: Bool
    var highDynamicRange: Bool
    var safeAreaInsetsAreZero: Bool

    /// Physical pixels must equal logical points times the ratio, or the three
    /// values disagree with each other.
    var isSelfConsistent: Bool {
        Int((Double(logicalWidth) * devicePixelRatio).rounded()) == physicalWidth
            && Int((Double(logicalHeight) * devicePixelRatio).rounded()) == physicalHeight
    }
}

/// Locale and storage readings.
nonisolated struct AuditLocale: Codable, Sendable {
    var timeZone: String
    var utcOffsetMinutes: Int
    var languages: [String]
    var calendar: String
    var numberingSystem: String
    var storageQuotaBytes: Int64
    var fontsPresent: [String]
    var fontsAbsent: [String]
}

/// Decode support per codec, including the one that decodes but not smoothly.
nonisolated struct AuditCodecSupport: Codable, Sendable {
    var recorderTypes: [String]
    /// Types `MediaRecorder` specifically turned down.
    var recorderRefused: [String]
    var canvasEncodable: [String]
    var canvasRefused: [String]
}

/// A single constraint probe the audit ran, and what the real hardware answered.
nonisolated struct AuditProbe: Codable, Sendable, Identifiable {
    nonisolated enum Outcome: String, Codable, Sendable {
        case granted
        case rejected
    }

    var id: String { name }
    var name: String
    var outcome: Outcome
    var resultSummary: String
    var errorName: String?
    var errorMessage: String?
    var elapsedMilliseconds: Double?

    var wasGranted: Bool { outcome == .granted }
}

/// The exact wording the audited platform used when it turned something down.
nonisolated enum AuditRefusal {
    static let overconstrainedName = "OverconstrainedError"
    static let invalidConstraintMessage = "Invalid constraint"
    static let typeErrorName = "TypeError"
    static let nonFiniteMessage = "The provided value is non-finite"
    static let timeoutName = "CameraTimeoutError"

    /// Settings the platform named as the offending one, and nothing else.
    static let blamedConstraints = ["width", "frameRate", "deviceId", "facingMode"]
}

/// Limits handed to the injected page so a request the real device refused is
/// refused here in exactly the same way.
nonisolated struct AuditCapabilityLimits: Codable, Sendable {
    var maxWidth: Int
    var maxHeight: Int
    var minWidth: Int
    var minHeight: Int
    var maxFrameRate: Double
    var minFrameRate: Double
    /// Error name Safari raised for an unsatisfiable hard constraint.
    var rejectionErrorName: String
    /// Error message Safari raised alongside it.
    var rejectionErrorMessage: String
}

/// Browser-level values recorded during the audit.
nonisolated struct AuditWebEnvironment: Codable, Sendable {
    /// Safari version, on its own so the user agent can never disagree with it.
    var safariVersion: String
    var iosVersion: String
    var navigatorPlatform: String
    var navigatorVendor: String
    var pdfViewerEnabled: Bool

    var display: AuditDisplay
    var hardwareConcurrency: Int
    /// `nil` means the real device did not expose `navigator.deviceMemory` at all.
    var deviceMemory: Int?
    var maxTouchPoints: Int

    var glRenderer: String
    var glVendor: String
    var glUnmaskedVendor: String
    var glShadingLanguageVersion: String
    var graphics: AuditGraphicsDetail

    var audio: AuditAudioStack
    var locale: AuditLocale
    var codecs: AuditCodecSupport

    /// Permission state before anything has been asked for.
    var cameraPermission: String
    var microphonePermission: String

    /// Readings the real device refuses to expose at all. Held as absent rather
    /// than filled in, because a value here is itself the tell.
    var networkInfoExposed: Bool
    var batteryApiExposed: Bool

    // MARK: Back-compatible accessors

    var screenWidth: Int { display.logicalWidth }
    var screenHeight: Int { display.logicalHeight }
    var devicePixelRatio: Double { display.devicePixelRatio }
    var colorDepth: Int { display.colorDepth }
    var supportedRecordingTypes: [String] { codecs.recorderTypes }

    /// Built from the version rather than stored, so the two cannot drift apart.
    ///
    /// OPEN QUESTION: `Mobile/15E148` is the build token from the recorded
    /// report. Your report does not name the token it expects, so this one is
    /// kept verbatim rather than replaced with an invented one. If a later
    /// capture shows a different token, this is the only line to change — the
    /// version parts are derived and follow automatically.
    var userAgent: String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS \(iosVersion.replacingOccurrences(of: ".", with: "_"))"
            + " like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)"
            + " Version/\(safariVersion) Mobile/15E148 Safari/604.1"
    }
}

/// Offline reference sheet built from the deep probe run on the user's iPhone.
///
/// This is the single source of truth for what the hardware can do. It works
/// with no network connection. Every value here was measured; nothing is
/// inferred or filled in from a lookup table.
nonisolated struct DeviceAuditProfile: Codable, Sendable {
    var deviceName: String
    var capturedNote: String
    var cameras: [AuditCamera]
    var microphones: [AuditMicrophone]
    var web: AuditWebEnvironment
    var probes: [AuditProbe]

    /// EXIF values a camera-app photo off this device carries.
    var photoSignature: AuditPhotoSignature

    var frontCameras: [AuditCamera] { cameras.filter(\.isFront) }
    var backCameras: [AuditCamera] { cameras.filter { !$0.isFront } }

    /// The plain "Front Camera" / "Back Camera" entries Safari shows by default.
    var primaryFront: AuditCamera? { cameras.first { $0.label == "Front Camera" } }
    var primaryBack: AuditCamera? { cameras.first { $0.label == "Back Camera" } }

    /// The default input, for the places that only need one.
    var microphone: AuditMicrophone {
        microphones.min { $0.order < $1.order } ?? AuditMicrophone(
            order: 0,
            label: "iPhone Microphone",
            deviceIdPrefix: "0000000000",
            groupWithCameraPrefix: nil,
            sampleRate: 48000,
            sampleSize: 16,
            channelCount: 1,
            echoCancellation: true,
            autoGainControl: true,
            noiseSuppression: true,
            latency: 0
        )
    }

    var rejectedProbes: [AuditProbe] { probes.filter { !$0.wasGranted } }

    /// Total devices reported once permission exists.
    var grantedDeviceCount: Int { cameras.count + microphones.count }

    /// Widest limits across every camera, for callers with no camera in hand.
    var limits: AuditCapabilityLimits {
        AuditCapabilityLimits(
            maxWidth: cameras.map(\.maxWidth).max() ?? 4032,
            maxHeight: cameras.map(\.maxHeight).max() ?? 4032,
            minWidth: 1,
            minHeight: 1,
            maxFrameRate: cameras.map(\.maxFrameRate).max() ?? 60,
            minFrameRate: cameras.map(\.minFrameRate).min() ?? 15,
            rejectionErrorName: AuditRefusal.overconstrainedName,
            rejectionErrorMessage: AuditRefusal.invalidConstraintMessage
        )
    }

    func camera(withPrefix prefix: String) -> AuditCamera? {
        cameras.first { $0.deviceIdPrefix == prefix }
    }

    /// Attacks the reference sheet with its own readings.
    ///
    /// No single value gets a device caught — disagreements between values do, so
    /// each pair is checked against its partner rather than each value on its own.
    /// Anything failing here is a contradiction a page could find.
    func crossCheck() -> [AuditCrossCheck] {
        var out: [AuditCrossCheck] = []

        func check(_ name: String, _ passed: Bool, _ detail: String) {
            out.append(AuditCrossCheck(name: name, passed: passed, detail: detail))
        }

        // The user agent and the photo stamp must claim one version, not two.
        // Only checkable when the stamp names a version at all; the recorded
        // report says this path names none, so there is nothing to disagree with.
        if photoSignature.carriesCameraIdentity {
            check("Version vs photo stamp",
                  web.safariVersion == photoSignature.software,
                  "user agent " + web.safariVersion + " · stamp " + photoSignature.software)
        }

        // Camera identity and capture times are absent together in the report.
        // A file carrying one but not the other is a hybrid no path produces.
        check("Photo stamp identity vs times",
              photoSignature.carriesCameraIdentity == photoSignature.carriesCaptureTimestamps,
              photoSignature.carriesCameraIdentity
                ? "names " + photoSignature.model + " and times it"
                : "names no make, model, lens or time — as recorded")

        let uaCarries = web.userAgent.contains("Version/" + web.safariVersion)
        check("Version vs user agent text", uaCarries,
              uaCarries ? "the built string carries it" : "the two disagree")

        // Running the newer graphics mode forces the newer shading language.
        let wantsNewShading = web.graphics.glVersion.contains("2.0")
        check("Graphics mode vs shading version",
              wantsNewShading == web.glShadingLanguageVersion.contains("3.00"),
              web.graphics.glVersion + " · " + web.glShadingLanguageVersion)

        // Logical points times the ratio has to equal the physical panel.
        let screen = web.display
        check("Screen vs pixel ratio vs panel", screen.isSelfConsistent,
              "\(screen.logicalWidth)×\(screen.logicalHeight) at "
                + "\(Int(screen.devicePixelRatio))× = "
                + "\(screen.physicalWidth)×\(screen.physicalHeight)")

        // A base latency is a whole buffer of frames at the sample rate.
        let frames = web.audio.baseLatency * Double(web.audio.sampleRate)
        check("Sample rate vs input latency",
              abs(frames - frames.rounded()) < 0.25,
              "\(web.audio.baseLatency)s at \(web.audio.sampleRate) Hz = "
                + "\(Int(frames.rounded())) frames")

        check("Extension count vs list",
              web.graphics.extensionCount == web.graphics.extensions.count,
              "\(web.graphics.extensionCount) named")

        let namingOK = cameras.allSatisfy {
            $0.label.lowercased().contains("front") == $0.isFront
        }
        check("Camera name vs side", namingOK,
              namingOK ? "all \(cameras.count) agree" : "a name contradicts its side")

        let ceilingOK = cameras.allSatisfy { $0.modes.contains($0.nativeMaxMode) }
        check("Camera ceiling vs its own sizes", ceilingOK,
              ceilingOK ? "each maximum is a size it offers"
                        : "a maximum is not a size it offers")

        let rateOK = cameras.allSatisfy { $0.frameRateSteps.contains($0.grantedFrameRate) }
        check("Granted rate vs advertised rates", rateOK,
              rateOK ? "every granted rate is one it advertises"
                     : "a granted rate is not advertised")

        // The measured oddity: an exact 16:9 ask comes back one pixel short.
        let wide = primaryBack?.resolveMode(width: nil, height: nil, aspect: 1.7778)
        check("Exact 16:9 answer", wide == AuditMode(width: 640, height: 359),
              wide.map { "\($0.width)×\($0.height)" } ?? "no back camera")

        let square = primaryBack?.resolveMode(width: nil, height: nil, aspect: 1)
        check("Exact 1:1 answer", square == AuditMode(width: 640, height: 640),
              square.map { "\($0.width)×\($0.height)" } ?? "no back camera")

        // Nothing may share an identity; inputs share only a group.
        var identities = cameras.map(\.deviceId)
        identities.append(contentsOf: microphones.map(\.deviceId))
        check("No shared identities", Set(identities).count == identities.count,
              "\(identities.count) devices, \(Set(identities).count) distinct")

        let grouped = microphones.allSatisfy { mic in
            guard let prefix = mic.groupWithCameraPrefix else { return false }
            return cameras.contains { $0.deviceIdPrefix == prefix }
        }
        check("Every input grouped with a real camera", grouped,
              grouped ? "\(microphones.count) inputs grouped"
                      : "an input names no real camera")

        check("List state vs permission answer",
              web.cameraPermission == "prompt" && web.microphonePermission == "prompt",
              "camera " + web.cameraPermission + " · microphone " + web.microphonePermission)

        check("Readings the device withholds",
              web.deviceMemory == nil && !web.networkInfoExposed && !web.batteryApiExposed,
              "memory, network and battery all absent")

        let torchCount = cameras.filter(\.hasTorch).count
        let wbCount = cameras.filter(\.supportsWhiteBalance).count
        let subUnityZoom = cameras.filter(\.supportsZoomBelowOne).count
        check("Controls only where measured",
              torchCount == 1 && wbCount == 3 && subUnityZoom == 1,
              "\(torchCount) torch · \(wbCount) white balance · \(subUnityZoom) below 1×")

        check("Photo colour vs rotation path",
              photoSignature.colorSpace == "Uncalibrated"
                && photoSignature.iccProfileName == "Display P3"
                && photoSignature.orientation == "top-left",
              photoSignature.colorSpace + " · " + photoSignature.iccProfileName
                + " · " + photoSignature.orientation)

        return out
    }

    /// Only the pairs that disagree. Empty is the answer we want.
    var crossCheckFailures: [AuditCrossCheck] { crossCheck().filter { !$0.passed } }

    /// The camera a plain facing request lands on.
    func defaultCamera(facing: String) -> AuditCamera? {
        facing == "environment" ? primaryBack ?? backCameras.first
                                : primaryFront ?? frontCameras.first
    }

    /// Applies a user-supplied Safari version without a rebuild. The user agent
    /// and the photo stamp both read from it, so they move together.
    func withSafariVersion(_ version: String) -> DeviceAuditProfile {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != web.safariVersion else { return self }
        var copy = self
        copy.web.safariVersion = trimmed
        copy.photoSignature.software = trimmed
        return copy
    }

    /// Pulls a value back to the nearest genuine one the hardware reported.
    func clampFrameRate(_ requested: Double) -> Double {
        min(max(requested, limits.minFrameRate), limits.maxFrameRate)
    }

    func clampWidth(_ requested: Int) -> Int {
        min(max(requested, limits.minWidth), limits.maxWidth)
    }

    func clampHeight(_ requested: Int) -> Int {
        min(max(requested, limits.minHeight), limits.maxHeight)
    }

    // MARK: - The measured device

    /// Every camera granted the same nine sizes apart from its own maximum.
    private static func modeLadder(nativeMax: AuditMode) -> [AuditMode] {
        [
            nativeMax,
            AuditMode(width: 3840, height: 2160),
            AuditMode(width: 1920, height: 1080),
            AuditMode(width: 1280, height: 720),
            AuditMode(width: 640, height: 480),
            AuditMode(width: 720, height: 1280),
            // An exact 16:9 ask really comes back one pixel short of 360.
            AuditMode(width: 640, height: 359),
            AuditMode(width: 640, height: 640),
            AuditMode(width: 480, height: 640)
        ]
    }

    private static let rateSteps: [Double] = [15, 30, 60]
    private static let portraitDefault = AuditMode(width: 480, height: 640)
    private static let wideMax = AuditMode(width: 4032, height: 3024)
    private static let squareMax = AuditMode(width: 4032, height: 4032)

    static let iPhone: DeviceAuditProfile = DeviceAuditProfile(
        deviceName: "iPhone 17 · iOS 18.7 · Safari 27.0",
        capturedNote: "Captured from the on-device deep probe run. Stored offline.",
        cameras: [
            AuditCamera(
                order: 0,
                label: "Front Ultra Wide Camera",
                facingMode: "user",
                deviceIdPrefix: "DD9F9811",
                modes: modeLadder(nativeMax: squareMax),
                frameRateSteps: rateSteps,
                defaultMode: portraitDefault,
                nativeMaxMode: squareMax,
                grantedFrameRate: 30,
                nativeMaxOpenMs: 2131,
                minZoom: 1, maxZoom: 10,
                whiteBalanceModes: ["manual", "continuous"],
                hasTorch: false
            ),
            AuditCamera(
                order: 1,
                label: "Back Dual Wide Camera",
                facingMode: "environment",
                deviceIdPrefix: "7A857F26",
                modes: modeLadder(nativeMax: wideMax),
                frameRateSteps: rateSteps,
                defaultMode: portraitDefault,
                nativeMaxMode: wideMax,
                grantedFrameRate: 30,
                nativeMaxOpenMs: 1584,
                // The multi-lens device is the only one that goes below 1×.
                minZoom: 0.5, maxZoom: 10,
                whiteBalanceModes: ["manual", "continuous"],
                hasTorch: true
            ),
            AuditCamera(
                order: 2,
                label: "Back Ultra Wide Camera",
                facingMode: "environment",
                deviceIdPrefix: "976E5E80",
                modes: modeLadder(nativeMax: wideMax),
                frameRateSteps: rateSteps,
                defaultMode: portraitDefault,
                nativeMaxMode: wideMax,
                grantedFrameRate: 30,
                nativeMaxOpenMs: 1436,
                minZoom: 1, maxZoom: 10,
                whiteBalanceModes: ["manual", "continuous"],
                hasTorch: false
            ),
            AuditCamera(
                order: 3,
                label: "Back Camera",
                facingMode: "environment",
                deviceIdPrefix: "8A26BF73",
                modes: modeLadder(nativeMax: wideMax),
                frameRateSteps: rateSteps,
                defaultMode: portraitDefault,
                nativeMaxMode: wideMax,
                grantedFrameRate: 30,
                nativeMaxOpenMs: 1251,
                minZoom: 1, maxZoom: 10,
                // This one published no white-balance control at all.
                whiteBalanceModes: [],
                hasTorch: false
            ),
            AuditCamera(
                order: 4,
                label: "Front Camera",
                facingMode: "user",
                deviceIdPrefix: "6172750B",
                modes: modeLadder(nativeMax: wideMax),
                frameRateSteps: rateSteps,
                defaultMode: portraitDefault,
                nativeMaxMode: wideMax,
                grantedFrameRate: 30,
                nativeMaxOpenMs: 1488,
                minZoom: 1, maxZoom: 10,
                whiteBalanceModes: [],
                hasTorch: false
            )
        ],
        // Four inputs, each grouped with a camera and none sharing an identity.
        microphones: [
            AuditMicrophone(
                order: 0,
                label: "iPhone Microphone",
                deviceIdPrefix: "8A26BF73A0",
                groupWithCameraPrefix: "8A26BF73",
                sampleRate: 48000, sampleSize: 16, channelCount: 1,
                echoCancellation: true, autoGainControl: true, noiseSuppression: true,
                latency: 0.002667
            ),
            AuditMicrophone(
                order: 1,
                label: "iPhone Microphone",
                deviceIdPrefix: "6172750BA1",
                groupWithCameraPrefix: "6172750B",
                sampleRate: 48000, sampleSize: 16, channelCount: 1,
                echoCancellation: true, autoGainControl: true, noiseSuppression: true,
                latency: 0.002667
            ),
            AuditMicrophone(
                order: 2,
                label: "iPhone Microphone",
                deviceIdPrefix: "7A857F26A2",
                groupWithCameraPrefix: "7A857F26",
                sampleRate: 48000, sampleSize: 16, channelCount: 1,
                echoCancellation: true, autoGainControl: true, noiseSuppression: true,
                latency: 0.002667
            ),
            AuditMicrophone(
                order: 3,
                label: "iPhone Microphone",
                deviceIdPrefix: "DD9F9811A3",
                groupWithCameraPrefix: "DD9F9811",
                sampleRate: 48000, sampleSize: 16, channelCount: 1,
                echoCancellation: true, autoGainControl: true, noiseSuppression: true,
                latency: 0.002667
            )
        ],
        web: AuditWebEnvironment(
            safariVersion: "27.0",
            iosVersion: "18.7",
            navigatorPlatform: "iPhone",
            navigatorVendor: "Apple Computer, Inc.",
            pdfViewerEnabled: true,
            display: AuditDisplay(
                logicalWidth: 402,
                logicalHeight: 874,
                physicalWidth: 1206,
                physicalHeight: 2622,
                devicePixelRatio: 3,
                colorDepth: 24,
                wideGamut: true,
                highDynamicRange: true,
                safeAreaInsetsAreZero: true
            ),
            hardwareConcurrency: 4,
            deviceMemory: nil,
            maxTouchPoints: 5,
            glRenderer: "Apple GPU",
            glVendor: "Apple Inc.",
            glUnmaskedVendor: "Apple Inc.",
            // WebGL 2 is active, so the shading language has to be the 3.00 one.
            glShadingLanguageVersion: "WebGL GLSL ES 3.00",
            graphics: AuditGraphicsDetail(
                glVersion: "WebGL 2.0",
                maxTextureSize: 16384,
                maxCubeMapSize: 16384,
                maxRenderbufferSize: 16384,
                maxViewportWidth: 16384,
                maxViewportHeight: 16384,
                maxVertexAttributes: 16,
                maxVertexUniformVectors: 1024,
                maxFragmentUniformVectors: 1024,
                maxVaryingVectors: 31,
                maxTextureImageUnits: 16,
                maxCombinedTextureUnits: 32,
                aliasedLineWidthRange: [1, 1],
                aliasedPointSizeRange: [1, 511],
                colorBits: 8,
                depthBits: 24,
                stencilBits: 0,
                maxAnisotropy: 16,
                extensions: [
                    "EXT_clip_control",
                    "EXT_color_buffer_float",
                    "EXT_color_buffer_half_float",
                    "EXT_conservative_depth",
                    "EXT_depth_clamp",
                    "EXT_float_blend",
                    "EXT_polygon_offset_clamp",
                    "EXT_render_snorm",
                    "EXT_texture_compression_bptc",
                    "EXT_texture_compression_rgtc",
                    "EXT_texture_filter_anisotropic",
                    "EXT_texture_mirror_clamp_to_edge",
                    "EXT_texture_norm16",
                    "KHR_parallel_shader_compile",
                    "NV_shader_noperspective_interpolation",
                    "OES_draw_buffers_indexed",
                    "OES_sample_variables",
                    "OES_shader_multisample_interpolation",
                    "OES_texture_float_linear",
                    "WEBGL_blend_func_extended",
                    "WEBGL_clip_cull_distance",
                    "WEBGL_compressed_texture_astc",
                    "WEBGL_compressed_texture_etc",
                    "WEBGL_compressed_texture_etc1",
                    "WEBGL_compressed_texture_pvrtc",
                    "WEBGL_compressed_texture_s3tc",
                    "WEBGL_compressed_texture_s3tc_srgb",
                    "WEBGL_debug_renderer_info",
                    "WEBGL_debug_shaders",
                    "WEBGL_lose_context",
                    "WEBGL_multi_draw",
                    "WEBGL_polygon_mode",
                    "WEBGL_provoking_vertex",
                    "WEBGL_render_shared_exponent",
                    "WEBGL_stencil_texturing",
                    "WEBKIT_WEBGL_compressed_texture_pvrtc"
                ]
            ),
            audio: AuditAudioStack(
                sampleRate: 48000,
                baseLatency: 0.002667,
                outputLatency: 0,
                maxChannels: 2,
                initialState: "suspended"
            ),
            locale: AuditLocale(
                timeZone: "Australia/Melbourne",
                utcOffsetMinutes: 600,
                languages: ["en-AU"],
                calendar: "gregory",
                numberingSystem: "latn",
                storageQuotaBytes: 41_231_686_042,
                fontsPresent: [
                    "Arial", "Avenir", "Avenir Next", "Baskerville", "Bodoni 72",
                    "Courier", "Courier New", "Didot", "Futura", "Georgia",
                    "Gill Sans", "Helvetica", "Helvetica Neue", "Hiragino Sans",
                    "Impact", "Menlo", "Optima", "Palatino", "Papyrus",
                    "PingFang SC", "Rockwell", "Thonburi", "Times",
                    "Times New Roman", "Trebuchet MS", "Verdana", "Zapfino"
                ],
                fontsAbsent: [
                    "Arial Black", "Arial Narrow", "Bookman", "Cambria", "Candara",
                    "Comic Sans MS", "Consolas", "Droid Sans", "Franklin Gothic",
                    "Garamond", "Geneva", "Lucida Grande", "Monaco", "Noto Sans",
                    "Roboto", "Segoe UI", "SF Pro Text", "Tahoma"
                ]
            ),
            codecs: AuditCodecSupport(
                recorderTypes: [
                    "video/mp4",
                    "video/mp4; codecs=\"avc1.42E01E\"",
                    "video/webm",
                    "video/webm; codecs=\"vp8\"",
                    "video/webm; codecs=\"vp9\"",
                    "audio/webm",
                    "audio/webm; codecs=\"opus\"",
                    "audio/mp4",
                    "audio/mp4; codecs=\"mp4a.40.2\""
                ],
                recorderRefused: [
                    "video/mp4; codecs=\"hvc1\"",
                    "video/webm; codecs=\"h264\"",
                    "video/webm; codecs=\"av01\""
                ],
                canvasEncodable: ["image/jpeg", "image/png", "image/avif", "image/heic"],
                canvasRefused: ["image/webp", "image/heif"]
            ),
            // Nothing has been asked for yet, which is what the audit captured
            // before its first request.
            cameraPermission: "prompt",
            microphonePermission: "prompt",
            networkInfoExposed: false,
            batteryApiExposed: false
        ),
        probes: [
            AuditProbe(name: "Native maximum", outcome: .granted,
                       resultSummary: "4032×4032 · 30 fps · user — size substituted, not refused",
                       elapsedMilliseconds: 2131),
            AuditProbe(name: "4K UHD landscape", outcome: .granted,
                       resultSummary: "3840×2160 · 30 fps · AR 1.778", elapsedMilliseconds: 212),
            AuditProbe(name: "1080p landscape", outcome: .granted,
                       resultSummary: "1920×1080 · 30 fps · AR 1.778", elapsedMilliseconds: 488),
            AuditProbe(name: "720p landscape", outcome: .granted,
                       resultSummary: "1280×720 · 30 fps · AR 1.778", elapsedMilliseconds: 339),
            AuditProbe(name: "VGA landscape", outcome: .granted,
                       resultSummary: "640×480 · 30 fps · AR 1.333", elapsedMilliseconds: 617),
            AuditProbe(name: "720p portrait", outcome: .granted,
                       resultSummary: "720×1280 · 30 fps · AR 0.563", elapsedMilliseconds: 196),
            AuditProbe(name: "Aspect ratio 16:9", outcome: .granted,
                       resultSummary: "640×359 · AR 1.783 — one pixel short of 360",
                       elapsedMilliseconds: 498),
            AuditProbe(name: "Aspect ratio 1:1", outcome: .granted,
                       resultSummary: "640×640 · AR 1", elapsedMilliseconds: 359),
            AuditProbe(name: "Exactly 15 fps", outcome: .granted,
                       resultSummary: "640×480 · 15 fps", elapsedMilliseconds: 344),
            AuditProbe(name: "Exactly 60 fps", outcome: .granted,
                       resultSummary: "640×480 · 60 fps", elapsedMilliseconds: 375),
            AuditProbe(name: "Single pixel 1×1", outcome: .granted,
                       resultSummary: "1×1 · 30 fps · AR 1", elapsedMilliseconds: 133),
            AuditProbe(name: "1080×1080 with 16:9 demanded", outcome: .granted,
                       resultSummary: "1080×1080 · AR 1 — the contradiction was granted",
                       elapsedMilliseconds: 280),
            AuditProbe(name: "Exactly 120 fps", outcome: .rejected,
                       resultSummary: "above the rate this camera advertised",
                       errorName: AuditRefusal.overconstrainedName,
                       errorMessage: AuditRefusal.invalidConstraintMessage,
                       elapsedMilliseconds: 20),
            AuditProbe(name: "99999×99999", outcome: .rejected,
                       resultSummary: "blamed width",
                       errorName: AuditRefusal.overconstrainedName,
                       errorMessage: AuditRefusal.invalidConstraintMessage,
                       elapsedMilliseconds: 6),
            AuditProbe(name: "Width range floor above ceiling", outcome: .rejected,
                       resultSummary: "min 4000, max 100 — blamed width",
                       errorName: AuditRefusal.overconstrainedName,
                       errorMessage: AuditRefusal.invalidConstraintMessage,
                       elapsedMilliseconds: 2),
            AuditProbe(name: "Zero frames a second", outcome: .rejected,
                       resultSummary: "blamed frameRate",
                       errorName: AuditRefusal.overconstrainedName,
                       errorMessage: AuditRefusal.invalidConstraintMessage,
                       elapsedMilliseconds: 2),
            AuditProbe(name: "Frame rate of not-a-number", outcome: .rejected,
                       resultSummary: "thrown out before any camera saw it",
                       errorName: AuditRefusal.typeErrorName,
                       errorMessage: AuditRefusal.nonFiniteMessage,
                       elapsedMilliseconds: 1),
            AuditProbe(name: "Camera id belonging to nothing", outcome: .rejected,
                       resultSummary: "blamed deviceId",
                       errorName: AuditRefusal.overconstrainedName,
                       errorMessage: AuditRefusal.invalidConstraintMessage,
                       elapsedMilliseconds: 6),
            AuditProbe(name: "This camera pinned, opposite side demanded", outcome: .rejected,
                       resultSummary: "blamed facingMode",
                       errorName: AuditRefusal.overconstrainedName,
                       errorMessage: AuditRefusal.invalidConstraintMessage,
                       elapsedMilliseconds: 9)
        ],
        photoSignature: .cameraApp
    )
}

/// One pair of values that has to agree with its partner.
///
/// The readings' real lesson is that no single value gets a device caught —
/// disagreements between values do. So every pair is checked against its partner
/// rather than each value being checked on its own.
nonisolated struct AuditCrossCheck: Sendable, Identifiable {
    var id: String { name }
    var name: String
    var passed: Bool
    var detail: String
}

/// The EXIF a camera-app photo off the audited device carries.
///
/// Only device and lens values live here. Exposure and timestamps are
/// deliberately absent: copying per-shot values across every frame is itself a
/// tell, so those are generated fresh per photo instead.
nonisolated struct AuditPhotoSignature: Codable, Sendable {
    var make: String
    var model: String
    var hostComputer: String
    var software: String
    var lensMake: String
    /// `Uncalibrated` is how Apple marks a wide-gamut file.
    var colorSpace: String
    var iccProfileName: String
    /// Rotation a camera-app file carries, matching the colour setting's path.
    var orientation: String
    var resolutionUnit: String
    var xResolution: Int
    var yResolution: Int
    var exifVersion: String
    var flashpixVersion: String
    var sceneType: String
    var sensingMethod: String
    var yCbCrPositioning: String
    var tiffByteOrder: String
    var jfifVersion: String
    var chromaSubsampling: String
    var hasEmbeddedThumbnail: Bool

    /// Whether a file off this path names the camera at all.
    ///
    /// The recorded report settles a disagreement between the two source
    /// documents. The correlation brief's table claims a camera-app file carries
    /// make, model, software, lens and maker note; the report of what the target
    /// site actually received lists none of them. The report wins, because it is
    /// what a site really sees. Writing identity a real file lacks is metadata no
    /// browser can produce on this path, which by the brief's own logic makes a
    /// photo easier to pick out rather than harder.
    ///
    /// `make`, `model`, `hostComputer`, `software` and `lensMake` stay here as
    /// reference values, but nothing is stamped from them while this is false.
    var carriesCameraIdentity: Bool

    /// Whether a file off this path carries capture times.
    ///
    /// Absent in the report for the same reason, and absent together with the
    /// identity — a file with times but no camera is a hybrid no path produces.
    var carriesCaptureTimestamps: Bool

    static let cameraApp = AuditPhotoSignature(
        make: "Apple",
        model: "iPhone 17",
        hostComputer: "iPhone 17",
        software: "27.0",
        lensMake: "Apple",
        colorSpace: "Uncalibrated",
        iccProfileName: "Display P3",
        orientation: "top-left",
        resolutionUnit: "inches",
        xResolution: 72,
        yResolution: 72,
        exifVersion: "0232",
        flashpixVersion: "0100",
        sceneType: "A directly photographed image",
        sensingMethod: "One-chip color area sensor",
        yCbCrPositioning: "centered",
        tiffByteOrder: "MM",
        jfifVersion: "1.01",
        chromaSubsampling: "4:2:0",
        hasEmbeddedThumbnail: false,
        carriesCameraIdentity: false,
        carriesCaptureTimestamps: false
    )
}

/// Turns a captured identifier handle into a stable, full-length Safari value.
nonisolated enum AuditIdentifier {
    /// The recording shows a standard UUID for every device identifier. The
    /// audit recorded the leading handle only, so the tail is filled
    /// deterministically — same input, same output, forever, including across
    /// relaunches — and the version/variant nibbles are set the way a real
    /// v4 UUID carries them.
    static func expand(_ prefix: String, salt: UInt64 = 0) -> String {
        let cleaned = prefix.uppercased().filter { $0.isHexDigit }
        guard !cleaned.isEmpty else { return "00000000-0000-4000-8000-000000000000" }

        var state: UInt64 = salt &+ 0xCBF2_9CE4_8422_2325
        for byte in cleaned.utf8 {
            state = (state ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }

        var hex = cleaned.lowercased()
        let digits = Array("0123456789abcdef")
        while hex.count < 32 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let index = Int((state >> 33) % 16)
            hex.append(digits[index])
        }

        var chars = Array(hex.prefix(32))
        chars[12] = "4"
        chars[16] = "8"
        let body = String(chars)
        let pieces = [
            String(body.prefix(8)),
            String(body.dropFirst(8).prefix(4)),
            String(body.dropFirst(12).prefix(4)),
            String(body.dropFirst(16).prefix(4)),
            String(body.dropFirst(20))
        ]
        return pieces.joined(separator: "-")
    }
}
