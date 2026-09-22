import AVFoundation
import UIKit
import WebKit

nonisolated enum SetupPhase: Sendable {
    case idle
    case requestingPermissions
    case discoveringDevices
    case testingDevice(String)
    case discoveringMicrophones
    case testingMicrophone(String)
    case gatheringWebFingerprint
    case mediaTestReal
    case mediaTestProcessed
    case mediaTestComparing
    case complete
    case failed(String)

    var label: String {
        switch self {
        case .idle: "Ready"
        case .requestingPermissions: "Requesting permissions…"
        case .discoveringDevices: "Discovering devices…"
        case .testingDevice(let name): "Testing \(name)…"
        case .discoveringMicrophones: "Discovering microphones…"
        case .testingMicrophone(let name): "Testing \(name)…"
        case .gatheringWebFingerprint: "Gathering web fingerprint…"
        case .mediaTestReal: "Loading Loom media test (real)…"
        case .mediaTestProcessed: "Loading Loom media test (processed)…"
        case .mediaTestComparing: "Comparing original vs processed…"
        case .complete: "Setup complete"
        case .failed(let msg): "Failed: \(msg)"
        }
    }
}

@Observable
@MainActor
final class SetupService {
    var phase: SetupPhase = .idle
    var progress: Double = 0
    var isScanning: Bool = false

    private var webView: WKWebView?
    private let mediaTestService = MediaTestService()
    private let fingerprintService = FingerprintService()

    func runFullScan() async -> DeviceProfile? {
        isScanning = true
        progress = 0

        phase = .requestingPermissions
        progress = 0.05

        let camGranted = await requestPermission(for: .video)
        guard camGranted else {
            phase = .failed("Camera permission denied")
            isScanning = false
            return nil
        }

        let micGranted = await requestPermission(for: .audio)
        guard micGranted else {
            phase = .failed("Microphone permission denied")
            isScanning = false
            return nil
        }
        progress = 0.1

        phase = .discoveringDevices
        let hardware = gatherHardwareSpec()
        progress = 0.12

        let captureDevices = discoverAllDevices()
        progress = 0.15

        var deviceSpecs: [CameraDeviceSpec] = []
        let deviceCount = max(captureDevices.count, 1)

        for (index, device) in captureDevices.enumerated() {
            phase = .testingDevice(device.localizedName)
            let spec = await testDevice(device)
            deviceSpecs.append(spec)
            progress = 0.15 + (0.45 * Double(index + 1) / Double(deviceCount))
        }

        phase = .discoveringMicrophones
        progress = 0.62
        let micDevices = discoverAllMicrophones()
        var micSpecs: [MicrophoneDeviceSpec] = []
        let micCount = max(micDevices.count, 1)

        for (index, device) in micDevices.enumerated() {
            phase = .testingMicrophone(device.localizedName)
            let spec = await testMicrophoneDevice(device)
            micSpecs.append(spec)
            progress = 0.62 + (0.1 * Double(index + 1) / Double(micCount))
        }

        phase = .gatheringWebFingerprint
        progress = 0.75
        let fingerprint = await gatherWebFingerprint()
        progress = 0.76

        let fpBaseline = await fingerprintService.captureBaseline()
        progress = 0.78

        let frontDev = deviceSpecs.first { $0.position == "front" }
        let backDev = deviceSpecs.first { $0.position == "back" }

        var tempProfile = DeviceProfile(
            name: hardware.modelName,
            deviceHardware: hardware,
            cameras: deviceSpecs,
            microphones: micSpecs,
            webFingerprint: fingerprint,
            preferredFrontCameraID: frontDev?.id,
            preferredBackCameraID: backDev?.id,
            preferredMicrophoneID: micSpecs.first?.id,
            fingerprintBaseline: fpBaseline
        )

        phase = .mediaTestReal
        progress = 0.80
        let testResult = await mediaTestService.runMediaTest(profile: tempProfile)
        progress = 0.98

        if let testResult {
            tempProfile.mediaTestResult = testResult
        }

        phase = .complete
        progress = 1.0
        isScanning = false
        return tempProfile
    }

    private func requestPermission(for mediaType: AVMediaType) async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: mediaType)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        default:
            return false
        }
    }

    private func gatherHardwareSpec() -> DeviceHardwareSpec {
        let device = UIDevice.current
        let screen = UIScreen.main
        let processInfo = ProcessInfo.processInfo

        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "Unknown"
            }
        }

        return DeviceHardwareSpec(
            modelName: device.model + " " + device.name,
            modelIdentifier: identifier,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            processorCount: processInfo.processorCount,
            physicalMemoryGB: Double(processInfo.physicalMemory) / (1024 * 1024 * 1024),
            screenNativeBounds: "\(Int(screen.nativeBounds.width))x\(Int(screen.nativeBounds.height))",
            screenScale: screen.scale,
            screenNativeScale: screen.nativeScale,
            identifierForVendor: device.identifierForVendor?.uuidString
        )
    }

    private func discoverAllDevices() -> [AVCaptureDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera,
                .builtInDualCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera,
                .builtInTrueDepthCamera,
                .builtInLiDARDepthCamera
            ],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices
    }

    private func discoverAllMicrophones() -> [AVCaptureDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices
    }

    private func testDevice(_ device: AVCaptureDevice) async -> CameraDeviceSpec {
        let position: String
        switch device.position {
        case .front: position = "front"
        case .back: position = "back"
        default: position = "unspecified"
        }

        let deviceTypeString = deviceTypeLabel(device.deviceType)

        let presets: [AVCaptureSession.Preset] = [
            .low, .medium, .high, .photo,
            .hd1280x720, .hd1920x1080, .hd4K3840x2160,
            .vga640x480, .iFrame960x540, .iFrame1280x720
        ]
        var supportedPresetNames: [String] = []
        let tempSession = AVCaptureSession()
        if let input = try? AVCaptureDeviceInput(device: device) {
            tempSession.beginConfiguration()
            if tempSession.canAddInput(input) {
                tempSession.addInput(input)
            }
            tempSession.commitConfiguration()
            for preset in presets {
                if tempSession.canSetSessionPreset(preset) {
                    supportedPresetNames.append(preset.rawValue)
                }
            }
        }

        var formats: [CameraFormatSpec] = []
        var maxWidth = 0
        var maxHeight = 0
        var globalMaxFPS: Double = 0
        var globalMinFPS: Double = 999

        for format in device.formats {
            let desc = format.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            let w = Int(dims.width)
            let h = Int(dims.height)

            var fmtMaxFPS: Double = 0
            var fmtMinFPS: Double = 999
            for range in format.videoSupportedFrameRateRanges {
                fmtMaxFPS = max(fmtMaxFPS, range.maxFrameRate)
                fmtMinFPS = min(fmtMinFPS, range.minFrameRate)
            }

            if w * h > maxWidth * maxHeight {
                maxWidth = w
                maxHeight = h
            }
            globalMaxFPS = max(globalMaxFPS, fmtMaxFPS)
            globalMinFPS = min(globalMinFPS, fmtMinFPS)

            let mediaType = CMFormatDescriptionGetMediaSubType(desc)
            let mediaTypeStr = String(format: "%c%c%c%c",
                                       (mediaType >> 24) & 0xFF,
                                       (mediaType >> 16) & 0xFF,
                                       (mediaType >> 8) & 0xFF,
                                       mediaType & 0xFF)

            formats.append(CameraFormatSpec(
                width: w,
                height: h,
                maxFrameRate: fmtMaxFPS,
                minFrameRate: fmtMinFPS,
                mediaType: mediaTypeStr,
                videoFieldOfView: format.videoFieldOfView,
                isMultiCamSupported: format.isMultiCamSupported
            ))
        }

        let activeFormat = device.activeFormat
        let activeDims = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)
        // `activeVideoMinFrameDuration` is the shortest interval the device will
        // deliver (the fastest rate); `activeVideoMaxFrameDuration` is the longest
        // (slowest). Diagnostics reads the min side, so the stored active rate must
        // too — reading the max side made conversion target the slowest rate while
        // diagnostics showed the fastest.
        let activeMinFPS = device.activeVideoMinFrameDuration.isValid && device.activeVideoMinFrameDuration.seconds > 0
            ? 1.0 / device.activeVideoMinFrameDuration.seconds
            : 30

        let colorSpace: String
        switch device.activeColorSpace {
        case .sRGB: colorSpace = "sRGB"
        case .P3_D65: colorSpace = "P3_D65"
        case .HLG_BT2020: colorSpace = "HLG_BT2020"
        case .appleLog: colorSpace = "AppleLog"
        @unknown default: colorSpace = "unknown"
        }

        let exposureSecs = CMTimeGetSeconds(device.exposureDuration)
        // AVFoundation exposes the field of view in degrees, not a focal length in
        // millimetres — stamping 69° as 69mm produced impossible lens values. The
        // EXIF layer falls back to the report-sourced values when this is nil.
        let lensAperture = device.lensAperture

        let gains = device.deviceWhiteBalanceGains
        let gainsStr = String(format: "R:%.2f G:%.2f B:%.2f", gains.redGain, gains.greenGain, gains.blueGain)

        var testBitrate: Int?
        var testDuration: Double?
        var testCodec: String?
        var testColorPrimaries: String?
        var testTransferFunc: String?
        var testColorMatrix: String?
        var testProfileLevel: String?

        let clipResult = await recordTestClip(device: device)
        if let clip = clipResult {
            testBitrate = clip.bitrate
            testDuration = clip.duration
            testCodec = clip.codec
            testColorPrimaries = clip.colorPrimaries
            testTransferFunc = clip.transferFunction
            testColorMatrix = clip.colorMatrix
            testProfileLevel = clip.profileLevel
            try? FileManager.default.removeItem(at: clip.url)
        }

        return CameraDeviceSpec(
            id: device.uniqueID,
            label: device.localizedName,
            position: position,
            deviceType: deviceTypeString,
            uniqueID: device.uniqueID,
            modelID: device.modelID,
            manufacturer: device.manufacturer,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            activeWidth: Int(activeDims.width),
            activeHeight: Int(activeDims.height),
            maxFrameRate: globalMaxFPS,
            activeFrameRate: activeMinFPS,
            minFrameRate: globalMinFPS,
            hasFlash: device.hasFlash,
            hasTorch: device.hasTorch,
            isAutoFocusSupported: device.isFocusModeSupported(.autoFocus),
            maxZoomFactor: device.maxAvailableVideoZoomFactor,
            minISO: device.activeFormat.minISO,
            maxISO: device.activeFormat.maxISO,
            supportedPresets: supportedPresetNames,
            supportedFormats: formats,
            testClipDuration: testDuration,
            testClipBitrate: testBitrate,
            testClipCodec: testCodec,
            testClipColorPrimaries: testColorPrimaries,
            testClipTransferFunction: testTransferFunc,
            testClipColorMatrix: testColorMatrix,
            testClipProfileLevel: testProfileLevel,
            activeColorSpace: colorSpace,
            exposureDurationSeconds: exposureSecs,
            focalLength: nil,
            lensAperture: lensAperture,
            whiteBalanceGains: gainsStr
        )
    }

    private func testMicrophoneDevice(_ device: AVCaptureDevice) async -> MicrophoneDeviceSpec {
        let position: String
        switch device.position {
        case .front: position = "front"
        case .back: position = "back"
        default: position = "unspecified"
        }

        let deviceTypeStr: String
        if device.deviceType == .microphone {
            deviceTypeStr = "Built-in Microphone"
        } else {
            deviceTypeStr = "Microphone"
        }

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .measurement)
        try? audioSession.setActive(true)

        let sampleRate = audioSession.sampleRate
        let channelCount = audioSession.inputNumberOfChannels
        let preferredSampleRate = audioSession.preferredSampleRate
        let preferredBufferDuration = audioSession.preferredIOBufferDuration

        var dataSources: [MicrophoneDataSource] = []
        if let sources = audioSession.inputDataSources {
            for source in sources {
                let patterns = source.supportedPolarPatterns?.map { patternName($0) } ?? []
                let selectedPattern = source.selectedPolarPattern.map { patternName($0) }

                dataSources.append(MicrophoneDataSource(
                    dataSourceID: source.dataSourceID.intValue,
                    dataSourceName: source.dataSourceName,
                    orientation: source.orientation?.rawValue,
                    location: source.location?.rawValue,
                    selectedPolarPattern: selectedPattern,
                    supportedPolarPatterns: patterns
                ))
            }
        }

        var testSampleRate: Double?
        var testBitDepth: Int?
        var testChannelCount: Int?

        let testResult = await recordTestAudio(device: device)
        if let result = testResult {
            testSampleRate = result.sampleRate
            testBitDepth = result.bitDepth
            testChannelCount = result.channelCount
        }

        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

        return MicrophoneDeviceSpec(
            id: device.uniqueID,
            label: device.localizedName,
            uniqueID: device.uniqueID,
            modelID: device.modelID,
            manufacturer: device.manufacturer,
            position: position,
            deviceType: deviceTypeStr,
            sampleRate: sampleRate,
            channelCount: channelCount,
            preferredSampleRate: preferredSampleRate > 0 ? preferredSampleRate : sampleRate,
            preferredBufferDuration: preferredBufferDuration,
            dataSources: dataSources,
            testSampleRate: testSampleRate,
            testBitDepth: testBitDepth,
            testChannelCount: testChannelCount
        )
    }

    private func patternName(_ pattern: AVAudioSession.PolarPattern) -> String {
        switch pattern {
        case .cardioid: return "cardioid"
        case .subcardioid: return "subcardioid"
        case .omnidirectional: return "omnidirectional"
        case .stereo: return "stereo"
        default: return pattern.rawValue
        }
    }

    /// Records a short clip and reads its encoding back. Runs off the main
    /// actor so `startRunning()` never blocks the UI, and gives up after five
    /// seconds rather than leaving the scan stuck on one camera.
    private func recordTestClip(device: AVCaptureDevice) async -> TestClipResult? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        let deviceID = device.uniqueID
        return await withTimeout(.seconds(5)) {
            await TestClipRecording.record(deviceID: deviceID, to: outputURL)
        } ?? nil
    }

    /// Listens to the microphone for one second and reports the first
    /// buffer's format. Same off-main, bounded shape as the clip test.
    private func recordTestAudio(device: AVCaptureDevice) async -> TestAudioResult? {
        let deviceID = device.uniqueID
        return await withTimeout(.seconds(3)) {
            await TestAudioRecording.record(deviceID: deviceID)
        } ?? nil
    }

    private func gatherWebFingerprint() async -> WebFingerprintSpec {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 812), configuration: config)
        wv.customUserAgent = StyleSheetProvider.safariUserAgent
        self.webView = wv
        defer { self.webView = nil }

        let js = """
            (function(){
                var c=document.createElement('canvas');
                var gl=c.getContext('webgl')||c.getContext('experimental-webgl');
                var ri='',vi='',wv='';
                if(gl){
                    var ext=gl.getExtension('WEBGL_debug_renderer_info');
                    if(ext){
                        ri=gl.getParameter(ext.UNMASKED_RENDERER_WEBGL)||'';
                        vi=gl.getParameter(ext.UNMASKED_VENDOR_WEBGL)||'';
                    }
                    wv=gl.getParameter(gl.VERSION)||'';
                }
                return JSON.stringify({
                    userAgent:navigator.userAgent,
                    platform:navigator.platform,
                    language:navigator.language,
                    languages:Array.from(navigator.languages||[]),
                    hardwareConcurrency:navigator.hardwareConcurrency||0,
                    deviceMemory:navigator.deviceMemory||0,
                    maxTouchPoints:navigator.maxTouchPoints||0,
                    screenWidth:screen.width,
                    screenHeight:screen.height,
                    screenColorDepth:screen.colorDepth,
                    devicePixelRatio:window.devicePixelRatio||1,
                    timezoneOffset:new Date().getTimezoneOffset(),
                    timezone:Intl.DateTimeFormat().resolvedOptions().timeZone||'',
                    doNotTrack:navigator.doNotTrack||null,
                    vendor:navigator.vendor||'',
                    rendererInfo:ri,
                    vendorInfo:vi,
                    webglVersion:wv
                });
            })();
            """

        wv.loadHTMLString("<html><body></body></html>", baseURL: nil)

        // The blank page needs a moment to exist before the script can run
        // against it; this pause is part of the scan's own task, so cancelling
        // the scan cancels the wait.
        try? await Task.sleep(for: .milliseconds(500))

        // Honest fallback: if the WebView reading failed, the spec carries
        // empty values and an explicit `wasMeasured == false` instead of
        // invented numbers presented as a real scan.
        var spec = WebFingerprintSpec(
            userAgent: "", platform: "", language: "",
            languages: [], hardwareConcurrency: 0,
            deviceMemory: 0, maxTouchPoints: 0,
            screenWidth: 0, screenHeight: 0,
            screenColorDepth: 0, devicePixelRatio: 1,
            timezoneOffset: 0, timezone: "",
            doNotTrack: nil, vendor: "",
            rendererInfo: "", vendorInfo: "", webglVersion: "",
            wasMeasured: false
        )

        let result = try? await wv.evaluateJavaScript(js)
        if let jsonStr = result as? String,
           let data = jsonStr.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            spec.userAgent = dict["userAgent"] as? String ?? ""
            spec.platform = dict["platform"] as? String ?? ""
            spec.language = dict["language"] as? String ?? ""
            spec.languages = dict["languages"] as? [String] ?? []
            spec.hardwareConcurrency = dict["hardwareConcurrency"] as? Int ?? 0
            spec.deviceMemory = dict["deviceMemory"] as? Int ?? 0
            spec.maxTouchPoints = dict["maxTouchPoints"] as? Int ?? 0
            spec.screenWidth = dict["screenWidth"] as? Int ?? 0
            spec.screenHeight = dict["screenHeight"] as? Int ?? 0
            spec.screenColorDepth = dict["screenColorDepth"] as? Int ?? 0
            spec.devicePixelRatio = dict["devicePixelRatio"] as? Double ?? 1
            spec.timezoneOffset = dict["timezoneOffset"] as? Int ?? 0
            spec.timezone = dict["timezone"] as? String ?? ""
            spec.doNotTrack = dict["doNotTrack"] as? String
            spec.vendor = dict["vendor"] as? String ?? ""
            spec.rendererInfo = dict["rendererInfo"] as? String ?? ""
            spec.vendorInfo = dict["vendorInfo"] as? String ?? ""
            spec.webglVersion = dict["webglVersion"] as? String ?? ""
            spec.wasMeasured = true
        }

        return spec
    }

    private func deviceTypeLabel(_ type: AVCaptureDevice.DeviceType) -> String {
        switch type {
        case .builtInWideAngleCamera: return "Wide Angle"
        case .builtInUltraWideCamera: return "Ultra Wide"
        case .builtInTelephotoCamera: return "Telephoto"
        case .builtInDualCamera: return "Dual"
        case .builtInDualWideCamera: return "Dual Wide"
        case .builtInTripleCamera: return "Triple"
        case .builtInTrueDepthCamera: return "TrueDepth"
        case .builtInLiDARDepthCamera: return "LiDAR"
        default: return "Unknown"
        }
    }
}

// MARK: - Test clip

/// One short recording, owned entirely by the task that runs it.
///
/// The session, output and device live as locals of `record`, so nothing
/// AVFoundation owns is ever shared. The only thing that crosses a thread is
/// the finished file's URL, handed back through a stream the delegate proxy
/// feeds exactly once.
nonisolated private enum TestClipRecording {
    /// Forwards AVFoundation's recording callback into a stream and holds
    /// nothing else, so it is trivially safe to hand across threads.
    private final class Delegate: NSObject, AVCaptureFileOutputRecordingDelegate, Sendable {
        private let finished: AsyncStream<URL?>.Continuation

        init(finished: AsyncStream<URL?>.Continuation) {
            self.finished = finished
            super.init()
        }

        func fileOutput(
            _ output: AVCaptureFileOutput,
            didFinishRecordingTo outputFileURL: URL,
            from connections: [AVCaptureConnection],
            error: (any Error)?
        ) {
            // Hitting `maxRecordedDuration` is reported as an error even
            // though the file is complete, so the file decides, not the error.
            let written = FileManager.default.fileExists(atPath: outputFileURL.path)
            finished.yield(written ? outputFileURL : nil)
            finished.finish()
        }
    }

    @concurrent
    static func record(deviceID: String, to outputURL: URL) async -> SetupService.TestClipResult? {
        guard let device = AVCaptureDevice(uniqueID: deviceID),
              let input = try? AVCaptureDeviceInput(device: device) else { return nil }

        let session = AVCaptureSession()
        let movieOutput = AVCaptureMovieFileOutput()
        let (finished, continuation) = AsyncStream<URL?>.makeStream()
        let delegate = Delegate(finished: continuation)

        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        movieOutput.maxRecordedDuration = CMTime(seconds: 1.5, preferredTimescale: 600)
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        session.commitConfiguration()

        session.startRunning()
        guard session.isRunning else {
            continuation.finish()
            return nil
        }
        defer { session.stopRunning() }

        movieOutput.startRecording(to: outputURL, recordingDelegate: delegate)

        // The duration cap ends the recording by itself and the delegate is
        // called exactly once per recording, so this wait ends on its own. A
        // camera that never delivers a frame is cut off by the caller's
        // timeout: cancelling this task ends the loop early.
        var fileURL: URL?
        for await url in finished {
            fileURL = url
            break
        }
        if movieOutput.isRecording {
            // Cut off mid-recording: close the file before the session goes.
            movieOutput.stopRecording()
        }
        guard let fileURL, !Task.isCancelled else {
            // Nothing usable came back; do not leave a stub in the temp folder.
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        return await describe(fileURL)
    }

    /// Reads back what the camera actually encoded.
    private static func describe(_ url: URL) async -> SetupService.TestClipResult {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero)

        var bitrate = 0
        var codec = "h264"
        var colorPrimaries: String?
        var transferFunction: String?
        var colorMatrix: String?
        var profileLevel: String?

        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            bitrate = Int((try? await track.load(.estimatedDataRate)) ?? 0)
            let descriptions = (try? await track.load(.formatDescriptions)) ?? []
            for description in descriptions {
                switch CMFormatDescriptionGetMediaSubType(description) {
                case kCMVideoCodecType_HEVC: codec = "hevc"
                case kCMVideoCodecType_H264: codec = "h264"
                default: break
                }
                let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any]
                colorPrimaries = extensions?["ColorPrimaries"] as? String
                transferFunction = extensions?["TransferFunction"] as? String
                colorMatrix = extensions?["YCbCrMatrix"] as? String
                profileLevel = extensions?["ProfileLevel"] as? String
            }
        }

        return SetupService.TestClipResult(
            url: url,
            bitrate: bitrate,
            duration: duration,
            codec: codec,
            colorPrimaries: colorPrimaries,
            transferFunction: transferFunction,
            colorMatrix: colorMatrix,
            profileLevel: profileLevel
        )
    }
}

// MARK: - Test audio

/// One second of microphone input, reduced to the first buffer's format.
nonisolated private enum TestAudioRecording {
    /// Reports the first buffer's format into a stream and then goes quiet.
    private final class Delegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, Sendable {
        private let formats: AsyncStream<SetupService.TestAudioResult>.Continuation

        init(formats: AsyncStream<SetupService.TestAudioResult>.Continuation) {
            self.formats = formats
            super.init()
        }

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return }
            // Every later buffer is dropped by the stream's one-item buffer;
            // the first is all the scan needs.
            formats.yield(SetupService.TestAudioResult(
                sampleRate: asbd.mSampleRate,
                bitDepth: Int(asbd.mBitsPerChannel),
                channelCount: Int(asbd.mChannelsPerFrame)
            ))
            formats.finish()
        }
    }

    @concurrent
    static func record(deviceID: String) async -> SetupService.TestAudioResult? {
        guard let device = AVCaptureDevice(uniqueID: deviceID),
              let input = try? AVCaptureDeviceInput(device: device) else { return nil }

        let session = AVCaptureSession()
        let audioOutput = AVCaptureAudioDataOutput()
        let (formats, continuation) = AsyncStream<SetupService.TestAudioResult>.makeStream(
            bufferingPolicy: .bufferingOldest(1)
        )
        let delegate = Delegate(formats: continuation)
        let sampleQueue = DispatchQueue(label: "com.app.testaudio.samples")

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        audioOutput.setSampleBufferDelegate(delegate, queue: sampleQueue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
        session.commitConfiguration()

        session.startRunning()
        guard session.isRunning else {
            continuation.finish()
            return nil
        }
        defer { session.stopRunning() }

        // Silence for a whole second means the microphone never spoke up.
        return await withTimeout(.seconds(1)) {
            for await format in formats {
                return format
            }
            return nil
        } ?? nil
    }
}

extension SetupService {
    nonisolated struct TestClipResult: Sendable {
        let url: URL
        let bitrate: Int
        let duration: Double
        let codec: String
        let colorPrimaries: String?
        let transferFunction: String?
        let colorMatrix: String?
        let profileLevel: String?
    }

    nonisolated struct TestAudioResult: Sendable {
        let sampleRate: Double
        let bitDepth: Int
        let channelCount: Int
    }
}
