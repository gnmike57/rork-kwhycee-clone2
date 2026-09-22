import Foundation

// MARK: - Live Session Diagnostics

nonisolated struct LiveSessionDiagnostics: Codable, Sendable {
    var activeWidth: Int
    var activeHeight: Int
    var aspectRatio: String
    var fps: Double
    var colorSpace: String
    var orientation: String
    /// `nil` means this session's mirroring was never measured — shown as
    /// "not measured" rather than invented as a fact.
    var isMirrored: Bool?
    var isHDR: Bool
    var stabilizationMode: String
    var timestamp: Date

    init(
        activeWidth: Int = 0,
        activeHeight: Int = 0,
        aspectRatio: String = "",
        fps: Double = 0,
        colorSpace: String = "",
        orientation: String = "",
        isMirrored: Bool? = nil,
        isHDR: Bool = false,
        stabilizationMode: String = "off",
        timestamp: Date = Date()
    ) {
        self.activeWidth = activeWidth
        self.activeHeight = activeHeight
        self.aspectRatio = aspectRatio
        self.fps = fps
        self.colorSpace = colorSpace
        self.orientation = orientation
        self.isMirrored = isMirrored
        self.isHDR = isHDR
        self.stabilizationMode = stabilizationMode
        self.timestamp = timestamp
    }
}

// MARK: - Constraint Log

nonisolated struct ConstraintLogEntry: Codable, Identifiable, Sendable {
    var id: UUID
    var timestamp: Date
    var siteURL: String
    var requestedConstraints: String
    var negotiatedResult: String
    var fallbackReason: String?
    var wasSuccessful: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        siteURL: String = "",
        requestedConstraints: String = "",
        negotiatedResult: String = "",
        fallbackReason: String? = nil,
        wasSuccessful: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.siteURL = siteURL
        self.requestedConstraints = requestedConstraints
        self.negotiatedResult = negotiatedResult
        self.fallbackReason = fallbackReason
        self.wasSuccessful = wasSuccessful
    }
}

// MARK: - Media Metadata Inspector

nonisolated struct MediaMetadataReport: Codable, Sendable {
    var container: String
    var videoCodec: String
    var videoBitrate: Int
    var videoFrameRate: Double
    var keyframeInterval: Int
    var pixelFormat: String
    var rotationDegrees: Int
    var videoWidth: Int
    var videoHeight: Int

    var hasAudio: Bool
    var audioCodec: String
    var audioBitrate: Int
    var audioSampleRate: Double
    var audioChannels: Int

    var colorPrimaries: String
    var transferFunction: String
    var colorMatrix: String
    var isFullRange: Bool
    var isHDR: Bool

    init(
        container: String = "", videoCodec: String = "", videoBitrate: Int = 0,
        videoFrameRate: Double = 0, keyframeInterval: Int = 0, pixelFormat: String = "",
        rotationDegrees: Int = 0, videoWidth: Int = 0, videoHeight: Int = 0,
        hasAudio: Bool = false, audioCodec: String = "", audioBitrate: Int = 0,
        audioSampleRate: Double = 0, audioChannels: Int = 0,
        colorPrimaries: String = "", transferFunction: String = "", colorMatrix: String = "",
        isFullRange: Bool = false, isHDR: Bool = false
    ) {
        self.container = container
        self.videoCodec = videoCodec
        self.videoBitrate = videoBitrate
        self.videoFrameRate = videoFrameRate
        self.keyframeInterval = keyframeInterval
        self.pixelFormat = pixelFormat
        self.rotationDegrees = rotationDegrees
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.hasAudio = hasAudio
        self.audioCodec = audioCodec
        self.audioBitrate = audioBitrate
        self.audioSampleRate = audioSampleRate
        self.audioChannels = audioChannels
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.colorMatrix = colorMatrix
        self.isFullRange = isFullRange
        self.isHDR = isHDR
    }
}

// MARK: - Conformance Score

nonisolated struct MediaConformanceScore: Codable, Sendable {
    var overallScore: Double
    var resolutionMatch: Bool
    var fpsMatch: Bool
    var codecMatch: Bool
    var bitrateMatch: Bool
    var orientationMatch: Bool
    var audioMatch: Bool
    var details: [String]

    init(
        overallScore: Double = 0, resolutionMatch: Bool = false,
        fpsMatch: Bool = false, codecMatch: Bool = false,
        bitrateMatch: Bool = false, orientationMatch: Bool = false,
        audioMatch: Bool = false, details: [String] = []
    ) {
        self.overallScore = overallScore
        self.resolutionMatch = resolutionMatch
        self.fpsMatch = fpsMatch
        self.codecMatch = codecMatch
        self.bitrateMatch = bitrateMatch
        self.orientationMatch = orientationMatch
        self.audioMatch = audioMatch
        self.details = details
    }
}

// MARK: - Frame Timing / Drift

nonisolated struct FrameTimingSample: Codable, Sendable {
    var timestamp: Double
    var delta: Double
    var isDuplicate: Bool
    var isJitter: Bool
}

nonisolated struct DriftReport: Codable, Sendable {
    var averageFPS: Double
    var minDelta: Double
    var maxDelta: Double
    var jitterCount: Int
    var duplicateCount: Int
    var totalFrames: Int
    var samples: [FrameTimingSample]

    init(
        averageFPS: Double = 0, minDelta: Double = 0, maxDelta: Double = 0,
        jitterCount: Int = 0, duplicateCount: Int = 0, totalFrames: Int = 0,
        samples: [FrameTimingSample] = []
    ) {
        self.averageFPS = averageFPS
        self.minDelta = minDelta
        self.maxDelta = maxDelta
        self.jitterCount = jitterCount
        self.duplicateCount = duplicateCount
        self.totalFrames = totalFrames
        self.samples = samples
    }
}

// MARK: - Audio Route Profile

nonisolated struct AudioRouteProfile: Codable, Sendable {
    var inputRoute: String
    var sampleRate: Double
    var channelCount: Int
    /// `nil` means bit depth was never measured — shown as "not measured"
    /// rather than invented as a fact.
    var bitDepth: Int?
    var echoCancellation: Bool
    var audioSessionMode: String
    var ioBufferDuration: Double

    init(
        inputRoute: String = "", sampleRate: Double = 0,
        channelCount: Int = 0, bitDepth: Int? = nil,
        echoCancellation: Bool = false, audioSessionMode: String = "",
        ioBufferDuration: Double = 0
    ) {
        self.inputRoute = inputRoute
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.echoCancellation = echoCancellation
        self.audioSessionMode = audioSessionMode
        self.ioBufferDuration = ioBufferDuration
    }
}

// MARK: - Site History

nonisolated struct SiteHistoryEntry: Codable, Identifiable, Sendable {
    var id: UUID
    var siteURL: String
    var timestamp: Date
    var requestedConstraints: String
    var actualSettings: String
    var profileUsed: String
    var wasSuccessful: Bool

    init(
        id: UUID = UUID(),
        siteURL: String = "",
        timestamp: Date = Date(),
        requestedConstraints: String = "",
        actualSettings: String = "",
        profileUsed: String = "",
        wasSuccessful: Bool = true
    ) {
        self.id = id
        self.siteURL = siteURL
        self.timestamp = timestamp
        self.requestedConstraints = requestedConstraints
        self.actualSettings = actualSettings
        self.profileUsed = profileUsed
        self.wasSuccessful = wasSuccessful
    }
}

// MARK: - Transcode Progress Phase

nonisolated enum TranscodePhase: String, Codable, Sendable, CaseIterable {
    case analysis = "Analysis"
    case audioPrep = "Audio Prep"
    case videoEncode = "Video Encode"
    case muxing = "Muxing"
    case verification = "Verification"
    case librarySave = "Library Save"
}

nonisolated struct TranscodeProgress: Codable, Sendable {
    var currentPhase: TranscodePhase
    var phaseProgress: Double
    var overallProgress: Double
    var phaseDetails: String

    init(
        currentPhase: TranscodePhase = .analysis,
        phaseProgress: Double = 0,
        overallProgress: Double = 0,
        phaseDetails: String = ""
    ) {
        self.currentPhase = currentPhase
        self.phaseProgress = phaseProgress
        self.overallProgress = overallProgress
        self.phaseDetails = phaseDetails
    }
}

// MARK: - Debug Bundle

nonisolated struct DebugBundle: Codable, Sendable {
    var exportDate: Date
    var deviceProfile: String
    var sessionDiagnostics: String
    var constraintLogs: [ConstraintLogEntry]
    var mediaMetadata: String
    var fingerprintResults: String
    var siteHistory: [SiteHistoryEntry]

    init(
        exportDate: Date = Date(),
        deviceProfile: String = "",
        sessionDiagnostics: String = "",
        constraintLogs: [ConstraintLogEntry] = [],
        mediaMetadata: String = "",
        fingerprintResults: String = "",
        siteHistory: [SiteHistoryEntry] = []
    ) {
        self.exportDate = exportDate
        self.deviceProfile = deviceProfile
        self.sessionDiagnostics = sessionDiagnostics
        self.constraintLogs = constraintLogs
        self.mediaMetadata = mediaMetadata
        self.fingerprintResults = fingerprintResults
        self.siteHistory = siteHistory
    }
}
