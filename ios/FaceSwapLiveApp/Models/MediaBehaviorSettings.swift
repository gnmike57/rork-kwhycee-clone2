import Foundation

/// How much hand-held movement the live feed adds to a still photo.
nonisolated enum MotionStrength: String, Codable, Sendable, CaseIterable, Identifiable {
    case barelyThere
    case natural
    case handHeld

    nonisolated var id: String { rawValue }

    nonisolated var label: String {
        switch self {
        case .barelyThere: "Barely There"
        case .natural: "Natural"
        case .handHeld: "Hand-held"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .barelyThere: "Almost imperceptible, and crops barely anything."
        case .natural: "A steady hand resting on a surface. Crops a little more."
        case .handHeld: "Held up and moving. Most alive, most visible, crops most. Ships as the default."
        }
    }

    /// Multiplier applied to every motion component.
    nonisolated var multiplier: Double {
        switch self {
        case .barelyThere: 0.45
        case .natural: 1.0
        case .handHeld: 1.9
        }
    }
}

/// Every switch added by the device-matched media work.
///
/// `allOff` reproduces the app's behaviour from before this feature set,
/// byte-for-byte. `default` is what ships.
///
/// New keys decode as off when missing, so an existing saved settings blob
/// is not reset just because this struct grew.
nonisolated struct MediaBehaviorSettings: Codable, Sendable, Equatable {
    /// Report the audited camera list and clamp values to audited limits.
    var useAuditProfile: Bool = true

    /// Floating quick-access pill over the browser.
    var showControlPill: Bool = true

    /// Ask before a site opens a live camera feed.
    var promptLiveRequests: Bool = true
    /// Ask before handing a file to a photo/file input.
    var promptFileRequests: Bool = true
    /// Maximum seconds the card waits before proceeding on site defaults.
    var promptHoldSeconds: Double = 20

    /// Hand-held movement for stills shown as a live feed. Live feed only.
    ///
    /// Ships at full hand-held strength: the feed reads as a phone in the hand
    /// rather than a tripod. Every other strength remains one tap away, and
    /// "Restore shipped defaults" returns here.
    var liveMotion: Bool = true
    var motionStrength: MotionStrength = .handHeld

    /// Sensor grain, baked in once when the feed starts. Live feed only.
    var sensorGrain: Bool = false
    /// Irregular frame delivery for the live feed. Live feed only.
    var frameTimingJitter: Bool = true
    /// Warmth pass, baked in once when the feed starts. Live feed only.
    var skinRealism: Bool = true

    /// Brightness and warmth drift, plus the settle after a hand-over.
    ///
    /// Live feed only. Costs nothing per frame: the drift rides on the wipe the
    /// draw already does and the opacity of the blit it already makes.
    var exposureBreathing: Bool = true

    /// Graphics chip, screen and codec answers sourced from the audit.
    var graphicsAlignment: Bool = true
    /// Refuse requests the audited hardware refused, with the identical error.
    var capabilityValidation: Bool = true

    /// Safari version reported to sites. Empty means the audited value.
    ///
    /// Kept here rather than baked into the reference sheet so it can be changed
    /// without a rebuild. The user agent and the photo stamp both read from it,
    /// so the two can never end up claiming different versions.
    var safariVersionOverride: String = ""

    /// Per-still 50–120% crop on the live feed. Off = today's cover-fit.
    var liveStillCrop: Bool = false
    /// Tiny overlay of what the page is told about the live feed.
    var showObservedHUD: Bool = false
    /// Stop wrapping after every loaded item on used cameras has been served.
    var autoOffAfterOnePass: Bool = false
    /// Show an honest asked-vs-sent timeline when injection turns off.
    var showSequenceRecap: Bool = false
    /// Optional front-still smirk/smile prep. Off = no extra buttons.
    var frontFaceButtons: Bool = false

    static let `default` = MediaBehaviorSettings()

    /// Pre-upgrade behaviour. Nothing new runs.
    static let allOff = MediaBehaviorSettings(
        useAuditProfile: false,
        showControlPill: false,
        promptLiveRequests: false,
        promptFileRequests: false,
        promptHoldSeconds: 20,
        liveMotion: false,
        motionStrength: .barelyThere,
        sensorGrain: false,
        frameTimingJitter: false,
        skinRealism: false,
        exposureBreathing: false,
        graphicsAlignment: false,
        capabilityValidation: false,
        safariVersionOverride: "",
        liveStillCrop: false,
        showObservedHUD: false,
        autoOffAfterOnePass: false,
        showSequenceRecap: false,
        frontFaceButtons: false
    )

    /// True when the app behaves exactly as it did before this feature set.
    ///
    /// Only the switches that actually change behaviour are compared. The hold
    /// time, the motion strength and the version override do nothing while their
    /// own switch is off, so changing any of them must not stop this reading as
    /// pre-upgrade.
    var isPreUpgradeBehavior: Bool {
        !useAuditProfile
            && !showControlPill
            && !promptLiveRequests
            && !promptFileRequests
            && !liveMotion
            && !sensorGrain
            && !frameTimingJitter
            && !skinRealism
            && !exposureBreathing
            && !graphicsAlignment
            && !capabilityValidation
            && !liveStillCrop
            && !showObservedHUD
            && !autoOffAfterOnePass
            && !showSequenceRecap
            && !frontFaceButtons
    }

    enum CodingKeys: String, CodingKey {
        case useAuditProfile
        case showControlPill
        case promptLiveRequests
        case promptFileRequests
        case promptHoldSeconds
        case liveMotion
        case motionStrength
        case sensorGrain
        case frameTimingJitter
        case skinRealism
        case exposureBreathing
        case graphicsAlignment
        case capabilityValidation
        case safariVersionOverride
        case liveStillCrop
        case showObservedHUD
        case autoOffAfterOnePass
        case showSequenceRecap
        case frontFaceButtons
    }

    init(
        useAuditProfile: Bool = true,
        showControlPill: Bool = true,
        promptLiveRequests: Bool = true,
        promptFileRequests: Bool = true,
        promptHoldSeconds: Double = 20,
        liveMotion: Bool = true,
        motionStrength: MotionStrength = .handHeld,
        sensorGrain: Bool = false,
        frameTimingJitter: Bool = true,
        skinRealism: Bool = true,
        exposureBreathing: Bool = true,
        graphicsAlignment: Bool = true,
        capabilityValidation: Bool = true,
        safariVersionOverride: String = "",
        liveStillCrop: Bool = false,
        showObservedHUD: Bool = false,
        autoOffAfterOnePass: Bool = false,
        showSequenceRecap: Bool = false,
        frontFaceButtons: Bool = false
    ) {
        self.useAuditProfile = useAuditProfile
        self.showControlPill = showControlPill
        self.promptLiveRequests = promptLiveRequests
        self.promptFileRequests = promptFileRequests
        self.promptHoldSeconds = promptHoldSeconds
        self.liveMotion = liveMotion
        self.motionStrength = motionStrength
        self.sensorGrain = sensorGrain
        self.frameTimingJitter = frameTimingJitter
        self.skinRealism = skinRealism
        self.exposureBreathing = exposureBreathing
        self.graphicsAlignment = graphicsAlignment
        self.capabilityValidation = capabilityValidation
        self.safariVersionOverride = safariVersionOverride
        self.liveStillCrop = liveStillCrop
        self.showObservedHUD = showObservedHUD
        self.autoOffAfterOnePass = autoOffAfterOnePass
        self.showSequenceRecap = showSequenceRecap
        self.frontFaceButtons = frontFaceButtons
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        useAuditProfile = try c.decodeIfPresent(Bool.self, forKey: .useAuditProfile) ?? true
        showControlPill = try c.decodeIfPresent(Bool.self, forKey: .showControlPill) ?? true
        promptLiveRequests = try c.decodeIfPresent(Bool.self, forKey: .promptLiveRequests) ?? true
        promptFileRequests = try c.decodeIfPresent(Bool.self, forKey: .promptFileRequests) ?? true
        promptHoldSeconds = try c.decodeIfPresent(Double.self, forKey: .promptHoldSeconds) ?? 20
        liveMotion = try c.decodeIfPresent(Bool.self, forKey: .liveMotion) ?? true
        motionStrength = try c.decodeIfPresent(MotionStrength.self, forKey: .motionStrength) ?? .handHeld
        sensorGrain = try c.decodeIfPresent(Bool.self, forKey: .sensorGrain) ?? false
        frameTimingJitter = try c.decodeIfPresent(Bool.self, forKey: .frameTimingJitter) ?? true
        skinRealism = try c.decodeIfPresent(Bool.self, forKey: .skinRealism) ?? true
        exposureBreathing = try c.decodeIfPresent(Bool.self, forKey: .exposureBreathing) ?? true
        graphicsAlignment = try c.decodeIfPresent(Bool.self, forKey: .graphicsAlignment) ?? true
        capabilityValidation = try c.decodeIfPresent(Bool.self, forKey: .capabilityValidation) ?? true
        safariVersionOverride = try c.decodeIfPresent(String.self, forKey: .safariVersionOverride) ?? ""
        liveStillCrop = try c.decodeIfPresent(Bool.self, forKey: .liveStillCrop) ?? false
        showObservedHUD = try c.decodeIfPresent(Bool.self, forKey: .showObservedHUD) ?? false
        autoOffAfterOnePass = try c.decodeIfPresent(Bool.self, forKey: .autoOffAfterOnePass) ?? false
        showSequenceRecap = try c.decodeIfPresent(Bool.self, forKey: .showSequenceRecap) ?? false
        frontFaceButtons = try c.decodeIfPresent(Bool.self, forKey: .frontFaceButtons) ?? false
    }
}

/// Where the user parked the floating pill.
nonisolated struct PillPlacement: Codable, Sendable, Equatable {
    /// Vertical position as a fraction of the usable height, 0 = top.
    var verticalFraction: Double = 0.82
    /// Which side it snapped to.
    var isLeftEdge: Bool = false
    /// Tucked away into the edge tab.
    var isTucked: Bool = false

    static let `default` = PillPlacement()
}
