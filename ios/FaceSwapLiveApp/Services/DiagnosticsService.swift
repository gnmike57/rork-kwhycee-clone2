import Foundation
import AVFoundation
import UIKit
import CoreImage

@Observable
@MainActor
final class DiagnosticsService {

    var liveDiagnostics: LiveSessionDiagnostics?
    var driftReport: DriftReport?
    var audioRouteProfile: AudioRouteProfile?

    private var frameTimes: [Double] = []
    private var lastFrameTime: Double = 0

    // MARK: - Live Session Diagnostics

    func captureLiveDiagnostics(from device: AVCaptureDevice) {
        let activeFormat = device.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)

        let aspectRatio: String
        if height > 0 {
            let ratio = Double(width) / Double(height)
            aspectRatio = String(format: "%.2f:1", ratio)
        } else {
            aspectRatio = "unknown"
        }

        let frameRateRange = device.activeVideoMinFrameDuration
        let fps = frameRateRange.timescale > 0
            ? Double(frameRateRange.timescale) / Double(frameRateRange.value)
            : 0

        let colorSpace: String
        if #available(iOS 14.1, *) {
            switch device.activeColorSpace {
            case .sRGB: colorSpace = "sRGB"
            case .P3_D65: colorSpace = "P3_D65"
            case .HLG_BT2020: colorSpace = "HLG_BT2020"
            case .appleLog: colorSpace = "appleLog"
            @unknown default: colorSpace = "unknown"
            }
        } else {
            switch device.activeColorSpace {
            case .sRGB: colorSpace = "sRGB"
            case .P3_D65: colorSpace = "P3_D65"
            case .HLG_BT2020: colorSpace = "HLG_BT2020"
            @unknown default: colorSpace = "unknown"
            }
        }

        let orientation = UIDevice.current.orientation
        let orientationStr: String
        switch orientation {
        case .portrait: orientationStr = "portrait"
        case .portraitUpsideDown: orientationStr = "portraitUpsideDown"
        case .landscapeLeft: orientationStr = "landscapeLeft"
        case .landscapeRight: orientationStr = "landscapeRight"
        case .faceUp: orientationStr = "faceUp"
        case .faceDown: orientationStr = "faceDown"
        default: orientationStr = "unknown"
        }

        let isHDR = activeFormat.isVideoHDRSupported
        let stabilization = activeFormat.isVideoStabilizationModeSupported(.cinematic)
            ? "cinematic" : "off"

        liveDiagnostics = LiveSessionDiagnostics(
            activeWidth: width,
            activeHeight: height,
            aspectRatio: aspectRatio,
            fps: fps,
            colorSpace: colorSpace,
            orientation: orientationStr,
            isMirrored: nil,
            isHDR: isHDR,
            stabilizationMode: stabilization,
            timestamp: Date()
        )
    }

    // MARK: - Audio Route Profile

    func captureAudioRouteProfile() {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute

        let inputName = route.inputs.first?.portName ?? "none"
        let sampleRate = session.sampleRate
        let channelCount = session.inputNumberOfChannels
        let ioBufferDuration = session.ioBufferDuration
        let mode = session.mode

        let echoCancellation = (mode == .voiceChat || mode == .videoChat)

        audioRouteProfile = AudioRouteProfile(
            inputRoute: inputName,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitDepth: nil,
            echoCancellation: echoCancellation,
            audioSessionMode: mode.rawValue,
            ioBufferDuration: ioBufferDuration
        )
    }

    // MARK: - Frame Timing

    func recordFrameTiming(_ timestamp: Double) {
        frameTimes.append(timestamp)
        if frameTimes.count > 300 {
            frameTimes.removeFirst(frameTimes.count - 300)
        }

        guard lastFrameTime > 0 else {
            lastFrameTime = timestamp
            return
        }

        lastFrameTime = timestamp
    }

    // MARK: - Drift Report

    func generateDriftReport() {
        guard frameTimes.count >= 2 else { return }

        var deltas: [Double] = []
        for i in 1..<frameTimes.count {
            deltas.append(frameTimes[i] - frameTimes[i - 1])
        }

        let sortedDeltas = deltas.sorted()
        let median = sortedDeltas[sortedDeltas.count / 2]

        var jitterCount = 0
        var duplicateCount = 0

        for delta in deltas {
            if delta < 0.001 {
                duplicateCount += 1
            } else if abs(delta - median) > median * 0.5 {
                jitterCount += 1
            }
        }

        let totalDelta = deltas.reduce(0, +)
        let averageFPS = totalDelta > 0 ? Double(deltas.count) / totalDelta : 0
        let minDelta = sortedDeltas.first ?? 0
        let maxDelta = sortedDeltas.last ?? 0

        let sampleCount = min(60, deltas.count)
        let sampleStart = deltas.count - sampleCount
        var samples: [FrameTimingSample] = []

        for i in sampleStart..<deltas.count {
            let delta = deltas[i]
            let isDuplicate = delta < 0.001
            let isJitter = !isDuplicate && abs(delta - median) > median * 0.5

            samples.append(FrameTimingSample(
                timestamp: frameTimes[i + 1],
                delta: delta,
                isDuplicate: isDuplicate,
                isJitter: isJitter
            ))
        }

        driftReport = DriftReport(
            averageFPS: averageFPS,
            minDelta: minDelta,
            maxDelta: maxDelta,
            jitterCount: jitterCount,
            duplicateCount: duplicateCount,
            totalFrames: frameTimes.count,
            samples: samples
        )
    }

    // MARK: - Media File Inspection

    static func inspectMediaFile(at url: URL) async -> MediaMetadataReport? {
        let asset = AVURLAsset(url: url)

        let container = url.pathExtension.lowercased()

        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }

        let formatDescriptions = (try? await videoTrack.load(.formatDescriptions)) ?? []
        let estimatedDataRate = (try? await videoTrack.load(.estimatedDataRate)) ?? 0
        let nominalFrameRate = (try? await videoTrack.load(.nominalFrameRate)) ?? 0
        let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity

        var videoCodec = ""
        var pixelFormat = ""
        var colorPrimaries = ""
        var transferFunction = ""
        var colorMatrix = ""
        var isFullRange = false

        if let formatDesc = formatDescriptions.first {
            let subType = CMFormatDescriptionGetMediaSubType(formatDesc)
            switch subType {
            case kCMVideoCodecType_H264:
                videoCodec = "h264"
            case kCMVideoCodecType_HEVC:
                videoCodec = "hevc"
            default:
                videoCodec = String(fourCharCode: subType)
            }

            if let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] {
                colorPrimaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String ?? ""
                transferFunction = extensions[kCVImageBufferTransferFunctionKey as String] as? String ?? ""
                colorMatrix = extensions[kCVImageBufferYCbCrMatrixKey as String] as? String ?? ""

                if let pixelAspect = extensions[kCVImageBufferPixelAspectRatioKey as String] as? [String: Any] {
                    let hSpacing = pixelAspect["HorizontalSpacing"] as? Int ?? 1
                    let vSpacing = pixelAspect["VerticalSpacing"] as? Int ?? 1
                    pixelFormat = "PAR \(hSpacing):\(vSpacing)"
                } else {
                    pixelFormat = ""
                }

                if let fullRange = extensions[kCMFormatDescriptionExtension_FullRangeVideo as String] as? Bool {
                    isFullRange = fullRange
                }
            }
        }

        let rotationDegrees: Int
        let angle = atan2(preferredTransform.b, preferredTransform.a)
        let degrees = angle * 180 / .pi
        rotationDegrees = Int(round(degrees < 0 ? degrees + 360 : degrees))

        let isHDR = transferFunction.contains("HLG") || transferFunction.contains("PQ")
            || transferFunction.contains("SMPTE_ST_2084")

        // Audio track info
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let hasAudio = !audioTracks.isEmpty
        var audioCodec = ""
        var audioSampleRate: Double = 0
        var audioChannels = 0
        var audioBitrate = 0

        if let audioTrack = audioTracks.first {
            let audioFormats = (try? await audioTrack.load(.formatDescriptions)) ?? []
            let audioDataRate = (try? await audioTrack.load(.estimatedDataRate)) ?? 0
            audioBitrate = Int(audioDataRate)

            if let audioFormat = audioFormats.first {
                let audioSubType = CMFormatDescriptionGetMediaSubType(audioFormat)
                switch audioSubType {
                case kAudioFormatMPEG4AAC:
                    audioCodec = "aac"
                case kAudioFormatLinearPCM:
                    audioCodec = "pcm"
                case kAudioFormatOpus:
                    audioCodec = "opus"
                default:
                    audioCodec = String(fourCharCode: audioSubType)
                }

                if let streamBasicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat) {
                    audioSampleRate = streamBasicDesc.pointee.mSampleRate
                    audioChannels = Int(streamBasicDesc.pointee.mChannelsPerFrame)
                }
            }
        }

        return MediaMetadataReport(
            container: container,
            videoCodec: videoCodec,
            videoBitrate: Int(estimatedDataRate),
            videoFrameRate: Double(nominalFrameRate),
            pixelFormat: pixelFormat,
            rotationDegrees: rotationDegrees,
            videoWidth: Int(naturalSize.width),
            videoHeight: Int(naturalSize.height),
            hasAudio: hasAudio,
            audioCodec: audioCodec,
            audioBitrate: audioBitrate,
            audioSampleRate: audioSampleRate,
            audioChannels: audioChannels,
            colorPrimaries: colorPrimaries,
            transferFunction: transferFunction,
            colorMatrix: colorMatrix,
            isFullRange: isFullRange,
            isHDR: isHDR
        )
    }

    // MARK: - Conformance Scoring

    static func scoreConformance(media: MediaMetadataReport, camera: CameraDeviceSpec) -> MediaConformanceScore {
        var details: [String] = []
        var matchCount = 0

        let resolutionMatch = abs(media.videoWidth - camera.activeWidth) <= Int(Double(camera.activeWidth) * 0.1)
            && abs(media.videoHeight - camera.activeHeight) <= Int(Double(camera.activeHeight) * 0.1)
        if resolutionMatch { matchCount += 1 }
        details.append("Resolution: media \(media.videoWidth)x\(media.videoHeight) vs camera \(camera.activeWidth)x\(camera.activeHeight) → \(resolutionMatch ? "match" : "mismatch")")

        let fpsMatch = abs(media.videoFrameRate - camera.activeFrameRate) <= 5
        if fpsMatch { matchCount += 1 }
        details.append("FPS: media \(String(format: "%.1f", media.videoFrameRate)) vs camera \(String(format: "%.1f", camera.activeFrameRate)) → \(fpsMatch ? "match" : "mismatch")")

        let cameraCodec = camera.testClipCodec ?? ""
        let codecMatch = media.videoCodec.lowercased() == cameraCodec.lowercased()
        if codecMatch { matchCount += 1 }
        details.append("Codec: media \(media.videoCodec) vs camera \(cameraCodec) → \(codecMatch ? "match" : "mismatch")")

        let cameraBitrate = camera.testClipBitrate ?? 0
        let bitrateMatch: Bool
        if cameraBitrate > 0 {
            bitrateMatch = abs(media.videoBitrate - cameraBitrate) <= Int(Double(cameraBitrate) * 0.3)
        } else {
            bitrateMatch = false
        }
        if bitrateMatch { matchCount += 1 }
        details.append("Bitrate: media \(media.videoBitrate) vs camera \(cameraBitrate) → \(bitrateMatch ? "match" : "mismatch")")

        let orientationMatch = media.rotationDegrees == 0
        if orientationMatch { matchCount += 1 }
        details.append("Orientation: rotation \(media.rotationDegrees)° → \(orientationMatch ? "match" : "mismatch")")

        let audioMatch = media.hasAudio
        if audioMatch { matchCount += 1 }
        details.append("Audio: \(audioMatch ? "present" : "missing") → \(audioMatch ? "match" : "mismatch")")

        let overallScore = Double(matchCount) / 6.0 * 100.0

        return MediaConformanceScore(
            overallScore: overallScore,
            resolutionMatch: resolutionMatch,
            fpsMatch: fpsMatch,
            codecMatch: codecMatch,
            bitrateMatch: bitrateMatch,
            orientationMatch: orientationMatch,
            audioMatch: audioMatch,
            details: details
        )
    }
}

// MARK: - Helpers

private extension String {
    init(fourCharCode code: UInt32) {
        self = String(
            format: "%c%c%c%c",
            (code >> 24) & 0xFF,
            (code >> 16) & 0xFF,
            (code >> 8) & 0xFF,
            code & 0xFF
        )
    }


}
