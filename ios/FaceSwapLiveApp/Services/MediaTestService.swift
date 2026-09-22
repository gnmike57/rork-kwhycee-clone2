import WebKit
import AVFoundation

@Observable
@MainActor
final class MediaTestService {
    var phase: MediaTestPhase = .idle
    var progress: Double = 0

    private var webView: WKWebView?
    private var coordinator: MediaTestCoordinator?

    nonisolated enum MediaTestPhase: Sendable {
        case idle
        case loadingReal
        case capturingRealDescriptors
        case loadingProcessed
        case capturingProcessedDescriptors
        case comparing
        case complete
        case failed(String)

        var label: String {
            switch self {
            case .idle: "Ready"
            case .loadingReal: "Loading Loom media test (real)\u{2026}"
            case .capturingRealDescriptors: "Capturing real descriptors\u{2026}"
            case .loadingProcessed: "Loading Loom media test (processed)\u{2026}"
            case .capturingProcessedDescriptors: "Capturing processed descriptors\u{2026}"
            case .comparing: "Comparing original vs processed\u{2026}"
            case .complete: "Media test complete"
            case .failed(let msg): "Failed: \(msg)"
            }
        }
    }

    private static let captureJS: String = """
    (async function(){
        var result = {};
        var md = navigator.mediaDevices;
        if(!md) return JSON.stringify({error:'No mediaDevices'});

        var sc = md.getSupportedConstraints ? md.getSupportedConstraints() : {};
        result.supportedConstraints = Object.keys(sc).filter(function(k){return sc[k];});

        var devs = await md.enumerateDevices();
        result.devices = devs.map(function(d){
            return {deviceId:d.deviceId||'',groupId:d.groupId||'',kind:d.kind||'',label:d.label||''};
        });

        try {
            var stream = await md.getUserMedia({video:true, audio:false});
            var vt = stream.getVideoTracks()[0];
            if(vt){
                result.trackLabel = vt.label || '';
                result.trackReadyState = vt.readyState || '';
                result.trackContentHint = vt.contentHint || '';
                result.trackMuted = vt.muted || false;
                result.trackEnabled = vt.enabled;
                result.mediaStreamId = stream.id || '';
                result.mediaStreamActive = stream.active || false;

                if(vt.getSettings){
                    var s = vt.getSettings();
                    result.trackSettings = {
                        deviceId: s.deviceId || '',
                        groupId: s.groupId || '',
                        width: s.width || 0,
                        height: s.height || 0,
                        frameRate: s.frameRate || 0,
                        facingMode: s.facingMode || '',
                        aspectRatio: s.aspectRatio || 0,
                        resizeMode: s.resizeMode || ''
                    };
                }

                if(vt.getCapabilities){
                    try{
                        var c = vt.getCapabilities();
                        result.trackCapabilities = {
                            deviceId: c.deviceId || '',
                            groupId: c.groupId || '',
                            widthMin: c.width ? (c.width.min || 0) : 0,
                            widthMax: c.width ? (c.width.max || 0) : 0,
                            heightMin: c.height ? (c.height.min || 0) : 0,
                            heightMax: c.height ? (c.height.max || 0) : 0,
                            frameRateMin: c.frameRate ? (c.frameRate.min || 0) : 0,
                            frameRateMax: c.frameRate ? (c.frameRate.max || 0) : 0,
                            facingModes: c.facingMode || [],
                            resizeModes: c.resizeMode || []
                        };
                    }catch(e){}
                }

                stream.getTracks().forEach(function(t){t.stop();});
            }
        } catch(e) {
            result.error = e.toString();
        }

        return JSON.stringify(result);
    })()
    """

    func runMediaTest(profile: DeviceProfile) async -> MediaTestResult? {
        progress = 0

        phase = .loadingReal
        progress = 0.05
        let realSnapshot = await captureFromLoom(processed: false, profile: nil)
        guard let realSnapshot else {
            phase = .failed("Failed to capture real descriptors")
            return nil
        }
        progress = 0.4

        phase = .loadingProcessed
        progress = 0.45
        let processedSnapshot = await captureFromLoom(processed: true, profile: profile)
        guard let processedSnapshot else {
            // A capture that produced nothing is a failure, not a 0% match.
            phase = .failed("Failed to capture processed descriptors")
            return nil
        }
        progress = 0.8

        phase = .comparing
        progress = 0.85
        let comparisons = buildComparisons(real: realSnapshot, processed: processedSnapshot)
        let matchCount = comparisons.filter { $0.matches }.count
        let matchPct = comparisons.isEmpty ? 0 : (Double(matchCount) / Double(comparisons.count)) * 100

        progress = 1.0
        phase = .complete

        return MediaTestResult(
            realSnapshot: realSnapshot,
            processedSnapshot: processedSnapshot,
            comparisons: comparisons,
            matchPercentage: matchPct
        )
    }

    private func captureFromLoom(processed: Bool, profile: DeviceProfile?) async -> MediaSnapshot? {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        if processed, let profile {
            let styleScript = WKUserScript(
                source: StyleSheetProvider.patchScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(styleScript)

            let profileJS = StyleSheetProvider.profileApplyScript(from: profile)
            config.userContentController.addUserScript(WKUserScript(
                source: profileJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))

            let activateJS = """
            (function(){
            var s=\(StyleSheetProvider.fslStateAccessorJS);
            if(!s)return;
            s.a=true;
            s.ra=true;
            s.is='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
            s.vs=null;
            try{navigator.mediaDevices.dispatchEvent(new Event('devicechange'));}catch(e){}
            })();
            """
            config.userContentController.addUserScript(WKUserScript(
                source: activateJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        wv.customUserAgent = StyleSheetProvider.safariUserAgent
        self.webView = wv

        let didLoad = await loadPage(in: wv, url: URL(string: "https://www.loom.com/webcam-mic-test")!)

        guard didLoad else {
            self.webView = nil
            self.coordinator = nil
            return nil
        }

        if processed {
            self.phase = .capturingProcessedDescriptors
        } else {
            self.phase = .capturingRealDescriptors
        }

        try? await Task.sleep(for: .seconds(3))

        let snapshot = await executeCapture(in: wv)
        self.webView = nil
        self.coordinator = nil
        return snapshot
    }

    /// Loads the page and waits for navigation to settle, giving up after
    /// twenty seconds. A failed load still counts as settled — the capture
    /// script decides what it can read — only a hang is a miss.
    private func loadPage(in webView: WKWebView, url: URL) async -> Bool {
        let (settled, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let coord = MediaTestCoordinator(onSettled: continuation)
        coordinator = coord
        webView.navigationDelegate = coord
        webView.load(URLRequest(url: url))

        // The coordinator stays attached for the page's whole life, so the
        // redirects and permission asks that follow the first load still
        // land on it; it is released together with the web view.
        return await withTimeout(.seconds(20)) {
            for await _ in settled { return true }
            return false
        } ?? false
    }

    private func executeCapture(in webView: WKWebView) async -> MediaSnapshot? {
        do {
            let result = try await webView.callAsyncJavaScript(
                Self.captureJS,
                arguments: [:],
                contentWorld: .page
            )

            guard let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            return parseSnapshot(dict)
        } catch {
            return nil
        }
    }

    private func parseSnapshot(_ dict: [String: Any]) -> MediaSnapshot {
        var devices: [MediaDeviceEntry] = []
        if let devArray = dict["devices"] as? [[String: Any]] {
            for d in devArray {
                devices.append(MediaDeviceEntry(
                    deviceId: d["deviceId"] as? String ?? "",
                    groupId: d["groupId"] as? String ?? "",
                    kind: d["kind"] as? String ?? "",
                    label: d["label"] as? String ?? ""
                ))
            }
        }

        var trackSettings: MediaTrackSettings?
        if let s = dict["trackSettings"] as? [String: Any] {
            trackSettings = MediaTrackSettings(
                deviceId: s["deviceId"] as? String ?? "",
                groupId: s["groupId"] as? String ?? "",
                width: s["width"] as? Int ?? 0,
                height: s["height"] as? Int ?? 0,
                frameRate: s["frameRate"] as? Double ?? 0,
                facingMode: s["facingMode"] as? String ?? "",
                aspectRatio: s["aspectRatio"] as? Double ?? 0,
                resizeMode: s["resizeMode"] as? String ?? ""
            )
        }

        var trackCaps: MediaTrackCapabilities?
        if let c = dict["trackCapabilities"] as? [String: Any] {
            trackCaps = MediaTrackCapabilities(
                deviceId: c["deviceId"] as? String ?? "",
                groupId: c["groupId"] as? String ?? "",
                widthMin: c["widthMin"] as? Int ?? 0,
                widthMax: c["widthMax"] as? Int ?? 0,
                heightMin: c["heightMin"] as? Int ?? 0,
                heightMax: c["heightMax"] as? Int ?? 0,
                frameRateMin: c["frameRateMin"] as? Double ?? 0,
                frameRateMax: c["frameRateMax"] as? Double ?? 0,
                facingModes: c["facingModes"] as? [String] ?? [],
                resizeModes: c["resizeModes"] as? [String] ?? []
            )
        }

        return MediaSnapshot(
            devices: devices,
            trackSettings: trackSettings,
            trackCapabilities: trackCaps,
            trackLabel: dict["trackLabel"] as? String ?? "",
            trackReadyState: dict["trackReadyState"] as? String ?? "",
            trackContentHint: dict["trackContentHint"] as? String ?? "",
            trackMuted: dict["trackMuted"] as? Bool ?? false,
            trackEnabled: dict["trackEnabled"] as? Bool ?? true,
            supportedConstraints: dict["supportedConstraints"] as? [String] ?? [],
            mediaStreamId: dict["mediaStreamId"] as? String ?? "",
            mediaStreamActive: dict["mediaStreamActive"] as? Bool ?? false
        )
    }

    private func buildComparisons(real: MediaSnapshot, processed: MediaSnapshot?) -> [MediaComparisonResult] {
        guard let processed else { return [] }
        var results: [MediaComparisonResult] = []

        let realVideoDevices = real.devices.filter { $0.kind == "videoinput" }
        let procVideoDevices = processed.devices.filter { $0.kind == "videoinput" }

        results.append(MediaComparisonResult(
            field: "Video Device Count",
            realValue: "\(realVideoDevices.count)",
            processedValue: "\(procVideoDevices.count)",
            matches: realVideoDevices.count == procVideoDevices.count
        ))

        if let realFirst = realVideoDevices.first, let procFirst = procVideoDevices.first {
            results.append(MediaComparisonResult(
                field: "Device ID",
                realValue: String(realFirst.deviceId.prefix(24)),
                processedValue: String(procFirst.deviceId.prefix(24)),
                matches: realFirst.deviceId == procFirst.deviceId
            ))
            results.append(MediaComparisonResult(
                field: "Group ID",
                realValue: String(realFirst.groupId.prefix(24)),
                processedValue: String(procFirst.groupId.prefix(24)),
                matches: realFirst.groupId == procFirst.groupId
            ))
            results.append(MediaComparisonResult(
                field: "Device Label",
                realValue: realFirst.label,
                processedValue: procFirst.label,
                matches: realFirst.label == procFirst.label
            ))
        }

        results.append(MediaComparisonResult(
            field: "Track Label",
            realValue: real.trackLabel,
            processedValue: processed.trackLabel,
            matches: real.trackLabel == processed.trackLabel
        ))

        results.append(MediaComparisonResult(
            field: "Track Ready State",
            realValue: real.trackReadyState,
            processedValue: processed.trackReadyState,
            matches: real.trackReadyState == processed.trackReadyState
        ))

        if let rs = real.trackSettings, let ps = processed.trackSettings {
            results.append(MediaComparisonResult(
                field: "Settings: Width",
                realValue: "\(rs.width)",
                processedValue: "\(ps.width)",
                matches: rs.width == ps.width
            ))
            results.append(MediaComparisonResult(
                field: "Settings: Height",
                realValue: "\(rs.height)",
                processedValue: "\(ps.height)",
                matches: rs.height == ps.height
            ))
            results.append(MediaComparisonResult(
                field: "Settings: Frame Rate",
                realValue: String(format: "%.1f", rs.frameRate),
                processedValue: String(format: "%.1f", ps.frameRate),
                matches: abs(rs.frameRate - ps.frameRate) < 1.0
            ))
            results.append(MediaComparisonResult(
                field: "Settings: Facing Mode",
                realValue: rs.facingMode,
                processedValue: ps.facingMode,
                matches: rs.facingMode == ps.facingMode
            ))
            results.append(MediaComparisonResult(
                field: "Settings: Aspect Ratio",
                realValue: String(format: "%.4f", rs.aspectRatio),
                processedValue: String(format: "%.4f", ps.aspectRatio),
                matches: abs(rs.aspectRatio - ps.aspectRatio) < 0.01
            ))
            results.append(MediaComparisonResult(
                field: "Settings: Device ID",
                realValue: String(rs.deviceId.prefix(24)),
                processedValue: String(ps.deviceId.prefix(24)),
                matches: rs.deviceId == ps.deviceId
            ))
            results.append(MediaComparisonResult(
                field: "Settings: Group ID",
                realValue: String(rs.groupId.prefix(24)),
                processedValue: String(ps.groupId.prefix(24)),
                matches: rs.groupId == ps.groupId
            ))
            results.append(MediaComparisonResult(
                field: "Settings: Resize Mode",
                realValue: rs.resizeMode,
                processedValue: ps.resizeMode,
                matches: rs.resizeMode == ps.resizeMode
            ))
        }

        if let rc = real.trackCapabilities, let pc = processed.trackCapabilities {
            results.append(MediaComparisonResult(
                field: "Caps: Width Range",
                realValue: "\(rc.widthMin)-\(rc.widthMax)",
                processedValue: "\(pc.widthMin)-\(pc.widthMax)",
                matches: rc.widthMin == pc.widthMin && rc.widthMax == pc.widthMax
            ))
            results.append(MediaComparisonResult(
                field: "Caps: Height Range",
                realValue: "\(rc.heightMin)-\(rc.heightMax)",
                processedValue: "\(pc.heightMin)-\(pc.heightMax)",
                matches: rc.heightMin == pc.heightMin && rc.heightMax == pc.heightMax
            ))
            results.append(MediaComparisonResult(
                field: "Caps: FPS Range",
                realValue: String(format: "%.0f-%.0f", rc.frameRateMin, rc.frameRateMax),
                processedValue: String(format: "%.0f-%.0f", pc.frameRateMin, pc.frameRateMax),
                matches: abs(rc.frameRateMin - pc.frameRateMin) < 1 && abs(rc.frameRateMax - pc.frameRateMax) < 1
            ))
            results.append(MediaComparisonResult(
                field: "Caps: Facing Modes",
                realValue: rc.facingModes.joined(separator: ","),
                processedValue: pc.facingModes.joined(separator: ","),
                matches: rc.facingModes == pc.facingModes
            ))
        }

        results.append(MediaComparisonResult(
            field: "Supported Constraints",
            realValue: "\(real.supportedConstraints.count)",
            processedValue: "\(processed.supportedConstraints.count)",
            matches: real.supportedConstraints.count == processed.supportedConstraints.count
        ))

        return results
    }
}

/// Reports the moment the page's navigation settles — finished or failed —
/// into a stream the loader is waiting on, and grants the media permissions
/// the test page needs.
private final class MediaTestCoordinator: NSObject, WKNavigationDelegate {
    private let onSettled: AsyncStream<Void>.Continuation

    init(onSettled: AsyncStream<Void>.Continuation) {
        self.onSettled = onSettled
        super.init()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onSettled.yield()
        onSettled.finish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        onSettled.yield()
        onSettled.finish()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        onSettled.yield()
        onSettled.finish()
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
}
