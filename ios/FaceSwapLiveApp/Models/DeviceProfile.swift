import CoreGraphics
import Foundation
import UIKit

nonisolated struct CameraDeviceSpec: Codable, Sendable, Identifiable {
    var id: String
    var label: String
    var position: String
    var deviceType: String
    var uniqueID: String
    var modelID: String
    var manufacturer: String

    var maxWidth: Int
    var maxHeight: Int
    var activeWidth: Int
    var activeHeight: Int
    var maxFrameRate: Double
    var activeFrameRate: Double
    var minFrameRate: Double

    var hasFlash: Bool
    var hasTorch: Bool
    var isAutoFocusSupported: Bool
    var maxZoomFactor: Double
    var minISO: Float
    var maxISO: Float

    var supportedPresets: [String]
    var supportedFormats: [CameraFormatSpec]

    var testClipDuration: Double?
    var testClipBitrate: Int?
    var testClipCodec: String?
    var testClipColorPrimaries: String?
    var testClipTransferFunction: String?
    var testClipColorMatrix: String?
    var testClipProfileLevel: String?

    var activeColorSpace: String?
    var exposureDurationSeconds: Double?
    var focalLength: Float?
    var lensAperture: Float?
    var whiteBalanceGains: String?
}

nonisolated struct CameraFormatSpec: Codable, Sendable {
    var width: Int
    var height: Int
    var maxFrameRate: Double
    var minFrameRate: Double
    var mediaType: String
    var videoFieldOfView: Float
    var isMultiCamSupported: Bool
}

nonisolated struct MicrophoneDeviceSpec: Codable, Sendable, Identifiable {
    var id: String
    var label: String
    var uniqueID: String
    var modelID: String
    var manufacturer: String
    var position: String
    var deviceType: String

    var sampleRate: Double
    var channelCount: Int
    var preferredSampleRate: Double
    var preferredBufferDuration: Double

    var dataSources: [MicrophoneDataSource]

    var testSampleRate: Double?
    var testBitDepth: Int?
    var testChannelCount: Int?
}

nonisolated struct MicrophoneDataSource: Codable, Sendable {
    var dataSourceID: Int
    var dataSourceName: String
    var orientation: String?
    var location: String?
    var selectedPolarPattern: String?
    var supportedPolarPatterns: [String]
}

nonisolated struct WebFingerprintSpec: Codable, Sendable {
    var userAgent: String
    var platform: String
    var language: String
    var languages: [String]
    var hardwareConcurrency: Int
    var deviceMemory: Int
    var maxTouchPoints: Int
    var screenWidth: Int
    var screenHeight: Int
    var screenColorDepth: Int
    var devicePixelRatio: Double
    var timezoneOffset: Int
    var timezone: String
    var doNotTrack: String?
    var vendor: String
    var rendererInfo: String
    var vendorInfo: String
    var webglVersion: String

    /// True when these values came from a real WebView reading; false when the
    /// scan fell back with no measurement at all. `nil` on profiles saved
    /// before this field existed — treated as measured so their stored
    /// behavior is byte-for-byte unchanged.
    var wasMeasured: Bool? = nil
}

nonisolated struct DeviceHardwareSpec: Codable, Sendable {
    var modelName: String
    var modelIdentifier: String
    var systemName: String
    var systemVersion: String
    var processorCount: Int
    var physicalMemoryGB: Double
    var screenNativeBounds: String
    var screenScale: Double
    var screenNativeScale: Double
    var identifierForVendor: String?
}

nonisolated struct MediaConversionSpec: Codable, Sendable {
    var targetWidth: Int
    var targetHeight: Int
    var targetFrameRate: Int
    var targetBitrate: Int
    var targetCodec: String
    var targetColorPrimaries: String?
    var targetTransferFunction: String?
    var targetColorMatrix: String?
    var targetProfileLevel: String?

    static let allowedFrameRates: [Int] = [15, 24, 25, 30, 60]
    /// Landscape sizes, largest last. The three a site really asks for lead the
    /// list, so an import lands on one of them rather than near one.
    static let allowedResolutions: [(Int, Int)] = [
        (640, 480), (1280, 720), (1920, 1080), (3840, 2160)
    ]

    static func clampFrameRate(_ requested: Int) -> Int {
        return allowedFrameRates.min(by: { abs($0 - requested) < abs($1 - requested) }) ?? 30
    }

    /// The nearest allowed size by pixel count.
    ///
    /// Orientation is deliberately ignored here: the file-upload, photo-chooser
    /// and native-camera paths have always sized against the camera's own box
    /// and must keep doing exactly that.
    static func clampResolution(width: Int, height: Int) -> (Int, Int) {
        let requested = width * height
        return allowedResolutions.min(by: {
            abs($0.0 * $0.1 - requested) < abs($1.0 * $1.1 - requested)
        }) ?? (1280, 720)
    }

    /// The nearest allowed size, in the orientation the media was shot in.
    ///
    /// Picking purely by pixel count answers a portrait clip with a landscape
    /// box and letterboxes it, so the ladder is turned on its side for a
    /// portrait source and left alone for a landscape one. A square source
    /// keeps its square shape rather than being pushed either way.
    static func clampResolutionPreservingOrientation(width: Int, height: Int) -> (Int, Int) {
        guard width > 0, height > 0 else { return (1280, 720) }
        let nearest = clampResolution(width: width, height: height)

        switch FrameShape.of(width: width, height: height) {
        case .portrait:
            return (nearest.1, nearest.0)
        case .square:
            let side = min(nearest.0, nearest.1)
            return (side, side)
        case .widescreen, .fourThree:
            return nearest
        }
    }
}

nonisolated struct DeviceProfile: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var deviceHardware: DeviceHardwareSpec
    var cameras: [CameraDeviceSpec]
    var microphones: [MicrophoneDeviceSpec]
    var webFingerprint: WebFingerprintSpec
    var preferredFrontCameraID: String?
    var preferredBackCameraID: String?
    var preferredMicrophoneID: String?
    var mediaTestResult: MediaTestResult?
    var fingerprintBaseline: FingerprintBaselineSpec?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        deviceHardware: DeviceHardwareSpec,
        cameras: [CameraDeviceSpec],
        microphones: [MicrophoneDeviceSpec] = [],
        webFingerprint: WebFingerprintSpec,
        preferredFrontCameraID: String? = nil,
        preferredBackCameraID: String? = nil,
        preferredMicrophoneID: String? = nil,
        mediaTestResult: MediaTestResult? = nil,
        fingerprintBaseline: FingerprintBaselineSpec? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.deviceHardware = deviceHardware
        self.cameras = cameras
        self.microphones = microphones
        self.webFingerprint = webFingerprint
        self.preferredFrontCameraID = preferredFrontCameraID
        self.preferredBackCameraID = preferredBackCameraID
        self.preferredMicrophoneID = preferredMicrophoneID
        self.mediaTestResult = mediaTestResult
        self.fingerprintBaseline = fingerprintBaseline
    }

    var frontCamera: CameraDeviceSpec? {
        if let preferred = preferredFrontCameraID {
            return cameras.first { $0.id == preferred }
        }
        return cameras.first { $0.position == "front" }
    }

    var backCamera: CameraDeviceSpec? {
        if let preferred = preferredBackCameraID {
            return cameras.first { $0.id == preferred }
        }
        return cameras.first { $0.position == "back" }
    }

    var primaryMicrophone: MicrophoneDeviceSpec? {
        if let preferred = preferredMicrophoneID {
            return microphones.first { $0.id == preferred }
        }
        return microphones.first
    }

    /// - Parameter sourceSize: the media's own display size, when it is known.
    ///   A clip is then encoded in the orientation it was shot in rather than
    ///   being forced into the camera's own box, which is what made a portrait
    ///   clip arrive letterboxed inside a landscape frame.
    func conversionSpec(for camera: CameraDeviceSpec, sourceSize: CGSize? = nil) -> MediaConversionSpec {
        let measured = sourceSize.flatMap { size -> (Int, Int)? in
            guard size.width > 0, size.height > 0 else { return nil }
            return (Int(size.width.rounded()), Int(size.height.rounded()))
        }
        // Only a measured source gets the orientation-aware ladder. With no
        // size in hand this stays the camera-box sizing every existing caller
        // has always had.
        let (w, h) = measured.map {
            MediaConversionSpec.clampResolutionPreservingOrientation(width: $0.0, height: $0.1)
        } ?? MediaConversionSpec.clampResolution(
            width: camera.activeWidth,
            height: camera.activeHeight
        )
        let fps = MediaConversionSpec.clampFrameRate(Int(camera.activeFrameRate))
        let bitrate = camera.testClipBitrate ?? defaultBitrate(width: w, height: h, fps: fps)

        return MediaConversionSpec(
            targetWidth: w,
            targetHeight: h,
            targetFrameRate: fps,
            targetBitrate: bitrate,
            targetCodec: camera.testClipCodec ?? "h264",
            targetColorPrimaries: camera.testClipColorPrimaries,
            targetTransferFunction: camera.testClipTransferFunction,
            targetColorMatrix: camera.testClipColorMatrix,
            targetProfileLevel: camera.testClipProfileLevel
        )
    }

    private func defaultBitrate(width: Int, height: Int, fps: Int) -> Int {
        let pixels = width * height
        if pixels >= 3840 * 2160 {
            return fps >= 60 ? 50_000_000 : 25_000_000
        } else if pixels >= 1920 * 1080 {
            return fps >= 60 ? 17_000_000 : 10_000_000
        } else if pixels >= 1280 * 720 {
            return fps >= 60 ? 10_000_000 : 5_000_000
        }
        return 2_500_000
    }
}
