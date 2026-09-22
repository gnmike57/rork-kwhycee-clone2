import AVFoundation
import UIKit
import CoreImage
import ImageIO

/// How the picture is reshaped on its way through.
nonisolated enum TranscodeStrategy: Sendable {
    /// Rotation, scaling and cropping run on the hardware video compositor,
    /// which also resamples to the target frame rate. First choice.
    case fast
    /// Frame-by-frame Core Image path. Slower, but survives sources the
    /// compositor refuses.
    case compatibility

    var label: String {
        switch self {
        case .fast: return "hardware"
        case .compatibility: return "compatibility"
        }
    }
}

nonisolated enum TranscodeError: LocalizedError, Sendable, Equatable {
    case unreadableSource
    case emptyDuration
    case setupFailed
    case cancelled
    case stalled
    case noFramesWritten
    case outOfSpace
    case writeFailed(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableSource:
            return "That clip could not be read. It may be in an unsupported format."
        case .emptyDuration:
            return "That clip has no playable length."
        case .setupFailed:
            return "The encoder could not be started for that clip."
        case .cancelled:
            return "Import cancelled."
        case .stalled:
            return "Encoding stopped responding, so it was stopped."
        case .noFramesWritten:
            return "No frames could be read from that clip."
        case .outOfSpace:
            return "Not enough free space on this device to prepare that clip."
        case .writeFailed(let detail):
            return "Encoding failed: \(detail)"
        case .verificationFailed(let detail):
            return "The prepared clip failed its check: \(detail)"
        }
    }

    /// Whether a second attempt on the slower, more forgiving path is worth it.
    var deservesRetry: Bool {
        switch self {
        case .cancelled, .outOfSpace, .emptyDuration, .unreadableSource:
            return false
        case .setupFailed, .stalled, .noFramesWritten, .writeFailed, .verificationFailed:
            return true
        }
    }
}

nonisolated struct TranscodeSummary: Sendable {
    var frameCount: Int
    var hasAudio: Bool
    var durationSeconds: Double
    var strategy: TranscodeStrategy
}

/// Bookkeeping for one encode: counts, the frame-rate gate and progress.
///
/// Lives entirely inside the task that drives the encode, so it needs no
/// locking — there is exactly one reader and one writer of it.
nonisolated private struct EncodeTally {
    let totalSeconds: Double
    var frames = 0
    var audioSamples = 0
    private var reportedProgress: Double = 0
    private var lastAppendedSeconds: Double?

    init(totalSeconds: Double) {
        self.totalSeconds = totalSeconds
    }

    /// Frame-rate gate for the compatibility path: keeps source timing while
    /// dropping frames the target frame rate has no room for.
    mutating func acceptsFrame(atSeconds seconds: Double, minimumInterval: Double) -> Bool {
        guard seconds.isFinite else { return false }
        guard let last = lastAppendedSeconds else {
            lastAppendedSeconds = seconds
            return true
        }
        // 5% slack so a 30fps source against a 30fps target does not lose every
        // other frame to timing jitter.
        guard seconds - last >= minimumInterval * 0.95 else { return false }
        lastAppendedSeconds = seconds
        return true
    }

    /// Records an appended frame; returns a progress value only when it has
    /// moved enough to be worth reporting.
    mutating func didAppendFrame(atSeconds seconds: Double) -> Double? {
        frames += 1
        guard totalSeconds > 0, seconds.isFinite else { return nil }
        let fraction = min(max(seconds / totalSeconds, 0), 1)
        guard fraction - reportedProgress >= 0.01 else { return nil }
        reportedProgress = fraction
        return fraction
    }
}

/// Prepares photos and clips to a camera's exact spec.
///
/// Holds no state of its own. Every encode builds its reader and writer
/// inside one background task and drives both to the end there, so nothing
/// AVFoundation owns is ever shared between threads, and cancelling the task
/// is all it takes to abandon the encode.
nonisolated final class MediaConverterService: Sendable {
    /// An encode whose writer accepts nothing for this long is treated as wedged.
    private static let stallTimeout: Duration = .seconds(30)

    /// How long the pump rests when neither writer input can take more.
    private static let idleInterval: Duration = .milliseconds(4)

    // MARK: - Orientation

    /// EXIF-style orientation that puts the track's frames upright.
    ///
    /// The back camera stores a +90° rotation and the front camera -90° (often
    /// with a horizontal mirror), so the direction must come from the transform
    /// itself — turning everything one way is what made front-camera output
    /// upside down.
    nonisolated static func displayOrientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let angle = atan2(transform.b, transform.a)
        let degrees = Int((angle * 180 / .pi).rounded())
        let normalized = ((degrees % 360) + 360) % 360
        let mirrored = (transform.a * transform.d - transform.b * transform.c) < 0
        switch (normalized, mirrored) {
        case (0, false): return .up
        case (0, true): return .downMirrored
        case (90, false): return .right
        case (90, true): return .leftMirrored
        case (180, false): return .down
        case (180, true): return .upMirrored
        case (270, false): return .left
        case (270, true): return .rightMirrored
        default: return .up
        }
    }

    /// Transform that stands a track upright, scales it to cover the target
    /// frame and centres the overflow — the video equivalent of aspect-fill.
    nonisolated static func aspectFillTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        targetSize: CGSize
    ) -> CGAffineTransform {
        let rotated = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        var transform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -rotated.minX, y: -rotated.minY)
        )

        let displayWidth = abs(rotated.width)
        let displayHeight = abs(rotated.height)
        guard displayWidth > 0, displayHeight > 0 else { return transform }

        let scale = max(targetSize.width / displayWidth, targetSize.height / displayHeight)
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

        let scaledWidth = displayWidth * scale
        let scaledHeight = displayHeight * scale
        transform = transform.concatenating(CGAffineTransform(
            translationX: (targetSize.width - scaledWidth) / 2,
            y: (targetSize.height - scaledHeight) / 2
        ))
        return transform
    }

    // MARK: - Images

    func convertImage(_ image: UIImage, spec: MediaConversionSpec) -> UIImage {
        resizeImageForInjection(image, spec: spec)
    }

    /// Prepares an imported photo for injection.
    ///
    /// The photo keeps its own shape — nothing is cropped away on the way in —
    /// and it is only ever scaled down, never up: just far enough that the
    /// largest frame sites ask for is still covered without stretching. A photo
    /// already smaller than that is left at its own size rather than being
    /// blown up into pixels it never had.
    func prepareStillForInjection(
        _ image: UIImage,
        covering frame: CGSize = CGSize(
            width: CommonFrames.widest.width,
            height: CommonFrames.widest.height
        ),
        maximumLongEdge: CGFloat = 4032
    ) -> UIImage {
        let pixels = CGSize(
            width: (image.size.width * image.scale).rounded(),
            height: (image.size.height * image.scale).rounded()
        )
        guard pixels.width > 0, pixels.height > 0 else { return image }

        // The smallest scale that still covers the frame on both axes. At or
        // above 1 the photo is already no larger than it needs to be.
        var scale = max(frame.width / pixels.width, frame.height / pixels.height)
        if scale >= 1 { scale = 1 }

        // A very large photo is bounded so a pair of imports cannot exhaust
        // memory, which matters more than the pixels past this point.
        let longEdge = max(pixels.width, pixels.height) * scale
        if longEdge > maximumLongEdge {
            scale *= maximumLongEdge / longEdge
        }
        guard scale < 0.999 else { return image }

        let out = CGSize(
            width: max(1, (pixels.width * scale).rounded()),
            height: max(1, (pixels.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: out, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: out))
        }
    }

    func resizeImageForInjection(_ image: UIImage, spec: MediaConversionSpec) -> UIImage {
        let targetSize = CGSize(width: spec.targetWidth, height: spec.targetHeight)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.black.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: targetSize))

            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            let imageAspect = imageSize.width / imageSize.height
            let targetAspect = targetSize.width / targetSize.height

            let drawRect: CGRect
            if imageAspect > targetAspect {
                let h = targetSize.height
                let w = h * imageAspect
                drawRect = CGRect(x: (targetSize.width - w) / 2, y: 0, width: w, height: h)
            } else {
                let w = targetSize.width
                let h = w / imageAspect
                drawRect = CGRect(x: 0, y: (targetSize.height - h) / 2, width: w, height: h)
            }
            image.draw(in: drawRect)
        }
    }

    // MARK: - Space

    /// Rough worst-case output size, used to fail early instead of mid-encode.
    nonisolated static func estimatedOutputBytes(spec: MediaConversionSpec, seconds: Double) -> Int64 {
        let videoBits = Double(spec.targetBitrate) * max(seconds, 1)
        let audioBits = 128_000.0 * max(seconds, 1)
        return Int64((videoBits + audioBits) / 8 * 1.25)
    }

    nonisolated static func hasFreeSpace(forBytes bytes: Int64, at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return true
        }
        // Leave headroom so the device is never driven to zero.
        return available > bytes + 150_000_000
    }

    // MARK: - Video

    /// Prepares a clip to one camera's exact spec.
    ///
    /// Timing follows the source: length, frame rate and playback speed are
    /// preserved, so a 60fps clip targeted at 30fps drops frames instead of
    /// turning into slow motion. Picture and sound come off separate readers,
    /// so sound never depends on the picture finishing first, and one loop
    /// feeds whichever writer input has room. The whole encode runs off the
    /// main actor; cancelling the calling task abandons it and removes the
    /// half-written file.
    @concurrent
    func transcode(
        source: URL,
        spec: MediaConversionSpec,
        outputURL: URL,
        strategy: TranscodeStrategy = .fast,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> TranscodeSummary {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw TranscodeError.unreadableSource
        }

        let asset = AVURLAsset(url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw TranscodeError.unreadableSource
        }

        let duration = (try? await asset.load(.duration)) ?? .zero
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds.isFinite, totalSeconds > 0.01 else { throw TranscodeError.emptyDuration }

        let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
        guard naturalSize.width > 0, naturalSize.height > 0 else { throw TranscodeError.unreadableSource }

        guard Self.hasFreeSpace(
            forBytes: Self.estimatedOutputBytes(spec: spec, seconds: totalSeconds),
            at: outputURL.deletingLastPathComponent()
        ) else {
            throw TranscodeError.outOfSpace
        }

        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first

        let targetFrameRate = max(1, spec.targetFrameRate)
        let targetSize = CGSize(width: spec.targetWidth, height: spec.targetHeight)
        let pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        // MARK: Readers

        guard let videoReader = try? AVAssetReader(asset: asset) else { throw TranscodeError.setupFailed }

        var compositionOutput: AVAssetReaderVideoCompositionOutput?
        var trackOutput: AVAssetReaderTrackOutput?

        switch strategy {
        case .fast:
            let composition = AVMutableVideoComposition()
            composition.renderSize = targetSize
            composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layer.setTransform(
                Self.aspectFillTransform(
                    naturalSize: naturalSize,
                    preferredTransform: preferredTransform,
                    targetSize: targetSize
                ),
                at: .zero
            )

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
            instruction.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            instruction.layerInstructions = [layer]
            composition.instructions = [instruction]

            let output = AVAssetReaderVideoCompositionOutput(
                videoTracks: [videoTrack],
                videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
            )
            output.videoComposition = composition
            output.alwaysCopiesSampleData = false
            guard videoReader.canAdd(output) else { throw TranscodeError.setupFailed }
            videoReader.add(output)
            compositionOutput = output

        case .compatibility:
            let output = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
            )
            output.alwaysCopiesSampleData = false
            guard videoReader.canAdd(output) else { throw TranscodeError.setupFailed }
            videoReader.add(output)
            trackOutput = output
        }

        // Audio gets its own reader. Two outputs on one reader have to be
        // drained in lockstep or the reader wedges — that is what used to make
        // sound disappear.
        var audioReader: AVAssetReader?
        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack, let reader = try? AVAssetReader(asset: asset) {
            let output = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioReader = reader
                audioOutput = output
            }
        }

        guard videoReader.startReading() else { throw TranscodeError.setupFailed }
        if let reader = audioReader, !reader.startReading() {
            // Sound is optional; a silent clip still beats a failed import.
            audioReader = nil
            audioOutput = nil
        }

        // MARK: Writer

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
            videoReader.cancelReading()
            audioReader?.cancelReading()
            throw TranscodeError.setupFailed
        }
        writer.shouldOptimizeForNetworkUse = false

        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: spec.targetBitrate,
            AVVideoExpectedSourceFrameRateKey: targetFrameRate,
            AVVideoMaxKeyFrameIntervalKey: targetFrameRate
        ]
        if let profileLevel = spec.targetProfileLevel {
            compressionProps[AVVideoProfileLevelKey] = profileLevel
        }

        var writerSettings: [String: Any] = [
            AVVideoCodecKey: spec.targetCodec == "hevc" ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: spec.targetWidth,
            AVVideoHeightKey: spec.targetHeight,
            AVVideoCompressionPropertiesKey: compressionProps
        ]
        if let colorPrimaries = spec.targetColorPrimaries,
           let transferFunc = spec.targetTransferFunction,
           let colorMatrix = spec.targetColorMatrix {
            writerSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: colorPrimaries,
                AVVideoTransferFunctionKey: transferFunc,
                AVVideoYCbCrMatrixKey: colorMatrix
            ]
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = .identity
        guard writer.canAdd(videoInput) else {
            videoReader.cancelReading()
            audioReader?.cancelReading()
            throw TranscodeError.setupFailed
        }
        writer.add(videoInput)

        // Only the compatibility path renders its own frames and needs a pool.
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        if strategy == .compatibility {
            adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: spec.targetWidth,
                    kCVPixelBufferHeightKey as String: spec.targetHeight
                ]
            )
        }

        // The sound input is only added once its reader is known to be
        // running, so the writer never waits on an input nothing will feed.
        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ])
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard writer.startWriting() else {
            videoReader.cancelReading()
            audioReader?.cancelReading()
            throw TranscodeError.writeFailed(writer.error?.localizedDescription ?? "writer refused to start")
        }
        writer.startSession(atSourceTime: .zero)

        // MARK: Pump

        let minimumInterval = 1.0 / Double(targetFrameRate)
        let ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
        let orientation = Self.displayOrientation(for: preferredTransform)
        var tally = EncodeTally(totalSeconds: totalSeconds)

        /// Tears the encode down and hands back the reason, so every failure
        /// path is one `throw abandon(...)`.
        func abandon(_ error: TranscodeError) -> TranscodeError {
            videoReader.cancelReading()
            audioReader?.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            return error
        }

        do {
            var videoDone = false
            var audioDone = audioInput == nil
            var lastProgress = ContinuousClock.now

            while !(videoDone && audioDone) {
                try Task.checkCancellation()
                var progressed = false

                if !videoDone, videoInput.isReadyForMoreMediaData {
                    progressed = true
                    let next: CMSampleBuffer?
                    switch strategy {
                    case .fast: next = compositionOutput?.copyNextSampleBuffer()
                    case .compatibility: next = trackOutput?.copyNextSampleBuffer()
                    }

                    guard let sampleBuffer = next else {
                        if videoReader.status == .failed {
                            throw abandon(.writeFailed(
                                videoReader.error?.localizedDescription ?? "could not read the clip"
                            ))
                        }
                        videoInput.markAsFinished()
                        videoDone = true
                        continue
                    }

                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let seconds = CMTimeGetSeconds(pts)

                    switch strategy {
                    case .fast:
                        // The compositor already produced the target size and
                        // cadence, so the buffer goes straight through with its
                        // own timestamp intact.
                        guard videoInput.append(sampleBuffer) else {
                            throw abandon(.writeFailed(
                                writer.error?.localizedDescription ?? "a frame was rejected"
                            ))
                        }
                        if let progress = tally.didAppendFrame(atSeconds: seconds) {
                            onProgress?(progress)
                        }

                    case .compatibility:
                        // Drop frames the target frame rate has no room for,
                        // rather than stretching the clip.
                        guard tally.acceptsFrame(atSeconds: seconds, minimumInterval: minimumInterval),
                              let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                              let adaptor,
                              let pool = adaptor.pixelBufferPool else {
                            continue
                        }

                        var image = CIImage(cvPixelBuffer: sourceBuffer)
                        if orientation != .up { image = image.oriented(orientation) }

                        let sourceWidth = image.extent.width
                        let sourceHeight = image.extent.height
                        guard sourceWidth > 0, sourceHeight > 0 else { continue }

                        let scale = max(targetSize.width / sourceWidth, targetSize.height / sourceHeight)
                        image = image
                            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                            .transformed(by: CGAffineTransform(
                                translationX: (targetSize.width - sourceWidth * scale) / 2,
                                y: (targetSize.height - sourceHeight * scale) / 2
                            ))
                            .cropped(to: CGRect(origin: .zero, size: targetSize))

                        var rendered: CVPixelBuffer?
                        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &rendered)
                        guard let outputBuffer = rendered else { continue }
                        ciContext.render(image, to: outputBuffer)

                        guard adaptor.append(outputBuffer, withPresentationTime: pts) else {
                            throw abandon(.writeFailed(
                                writer.error?.localizedDescription ?? "a frame was rejected"
                            ))
                        }
                        if let progress = tally.didAppendFrame(atSeconds: seconds) {
                            onProgress?(progress)
                        }
                    }
                    lastProgress = ContinuousClock.now
                }

                if !audioDone, let audioInput, let audioOutput, audioInput.isReadyForMoreMediaData {
                    progressed = true
                    guard let sample = audioOutput.copyNextSampleBuffer() else {
                        audioInput.markAsFinished()
                        audioDone = true
                        continue
                    }
                    if audioInput.append(sample) {
                        tally.audioSamples += 1
                    } else {
                        // Losing sound is not worth failing the clip.
                        audioInput.markAsFinished()
                        audioDone = true
                    }
                    lastProgress = ContinuousClock.now
                }

                if !progressed {
                    // Neither input has room: the writer is draining. A writer
                    // that never comes back is wedged, and reporting that beats
                    // waiting forever.
                    if ContinuousClock.now - lastProgress > Self.stallTimeout {
                        throw abandon(.stalled)
                    }
                    try await Task.sleep(for: Self.idleInterval)
                }
            }

            guard tally.frames > 0 else { throw abandon(.noFramesWritten) }

            await writer.finishWriting()
            guard writer.status == .completed else {
                try? FileManager.default.removeItem(at: outputURL)
                throw TranscodeError.writeFailed(
                    writer.error?.localizedDescription ?? "the file could not be finished"
                )
            }

            onProgress?(1.0)
            return TranscodeSummary(
                frameCount: tally.frames,
                hasAudio: audioInput != nil && tally.audioSamples > 0,
                durationSeconds: totalSeconds,
                strategy: strategy
            )
        } catch is CancellationError {
            throw abandon(.cancelled)
        }
    }

    // MARK: - Verification

    /// Confirms a finished file is the right shape, the right length, and can
    /// actually be decoded — so a broken encode never reaches a camera slot.
    @concurrent
    func verify(url: URL, spec: MediaConversionSpec, expectedSeconds: Double) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TranscodeError.verificationFailed("the file is missing")
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        guard size > 1024 else {
            throw TranscodeError.verificationFailed("the file is empty")
        }

        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            throw TranscodeError.verificationFailed("it has no video track")
        }

        let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let orientation = Self.displayOrientation(for: transform)
        let isPortrait = orientation == .right || orientation == .left
            || orientation == .rightMirrored || orientation == .leftMirrored
        let width = Int(isPortrait ? naturalSize.height : naturalSize.width)
        let height = Int(isPortrait ? naturalSize.width : naturalSize.height)

        guard abs(width - spec.targetWidth) <= 2, abs(height - spec.targetHeight) <= 2 else {
            throw TranscodeError.verificationFailed(
                "it came out \(width)×\(height) instead of \(spec.targetWidth)×\(spec.targetHeight)"
            )
        }

        let duration = CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero)
        guard duration.isFinite, duration > 0 else {
            throw TranscodeError.verificationFailed("it has no length")
        }
        if expectedSeconds > 0 {
            let drift = abs(duration - expectedSeconds)
            guard drift <= max(0.5, expectedSeconds * 0.05) else {
                throw TranscodeError.verificationFailed(
                    String(format: "it runs %.1fs instead of %.1fs", duration, expectedSeconds)
                )
            }
        }

        // Decode one frame: the only real proof it plays.
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let probe = CMTime(seconds: min(0.1, duration / 2), preferredTimescale: 600)
        guard (try? await generator.image(at: probe)) != nil else {
            throw TranscodeError.verificationFailed("it could not be played back")
        }
    }

    // MARK: - Compatibility wrappers

    /// Kept for the browser's per-slot conversion path.
    func convertVideo(_ inputURL: URL, spec: MediaConversionSpec) async -> URL? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("converted_\(UUID().uuidString).mov")
        let ok = await convertVideoWithProgress(inputURL, spec: spec, outputURL: outputURL, onProgress: nil)
        return ok ? outputURL : nil
    }

    @discardableResult
    func convertVideoWithProgress(
        _ inputURL: URL,
        spec: MediaConversionSpec,
        outputURL: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async -> Bool {
        do {
            _ = try await transcode(
                source: inputURL,
                spec: spec,
                outputURL: outputURL,
                strategy: .fast,
                onProgress: onProgress
            )
            return true
        } catch {
            guard let transcodeError = error as? TranscodeError, transcodeError.deservesRetry else {
                return false
            }
            do {
                _ = try await transcode(
                    source: inputURL,
                    spec: spec,
                    outputURL: outputURL,
                    strategy: .compatibility,
                    onProgress: onProgress
                )
                return true
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                return false
            }
        }
    }
}
