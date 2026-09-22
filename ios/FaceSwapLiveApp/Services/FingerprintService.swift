import Foundation
import WebKit
import UIKit

@Observable
@MainActor
final class FingerprintService {

    // MARK: - Public Properties

    var baseline: FingerprintBaselineSpec?
    var consistencyResults: [FingerprintConsistencyResult] = []
    var isCapturing: Bool = false
    var isTesting: Bool = false
    var testPassed: Bool?
    /// Iterations the most recent test actually ran with — the banner must
    /// never report a slider position that no test has used.
    var lastRunIterations: Int?

    // MARK: - Private Properties

    private var webView: WKWebView?
    private var navDelegate: NavigationDelegate?

    // MARK: - JavaScript Helpers

    private static let djb2Function = """
        function djb2(s){var h=5381;for(var i=0;i<s.length;i++){h=((h<<5)+h)+s.charCodeAt(i);h=h&h;}return(h>>>0).toString(16);}
        """

    private static let fingerprintScript: String = """
        (async function() {
            \(djb2Function)

            // Hardware concurrency
            var hardwareConcurrency = navigator.hardwareConcurrency || 0;

            // Screen dimensions
            var screenWidth = screen.width || 0;
            var screenHeight = screen.height || 0;

            // Screen frame
            var screenFrameTop = window.screenY || window.screenTop || 0;
            var screenFrameBottom = (typeof screen.availTop === 'number' && typeof screen.availHeight === 'number')
                ? (screen.availTop + screen.availHeight)
                : 0;

            // Audio fingerprint
            var audioFingerprint = 0;
            try {
                var actx = new OfflineAudioContext(1, 44100, 44100);
                var osc = actx.createOscillator();
                osc.type = 'triangle';
                osc.frequency.setValueAtTime(10000, actx.currentTime);
                var comp = actx.createDynamicsCompressor();
                comp.threshold.setValueAtTime(-50, actx.currentTime);
                comp.knee.setValueAtTime(40, actx.currentTime);
                comp.ratio.setValueAtTime(12, actx.currentTime);
                comp.attack.setValueAtTime(0, actx.currentTime);
                comp.release.setValueAtTime(0.25, actx.currentTime);
                osc.connect(comp);
                comp.connect(actx.destination);
                osc.start(0);
                var buf = await actx.startRendering();
                var d = buf.getChannelData(0);
                var sum = 0;
                for(var i=4500;i<5000;i++) sum += Math.abs(d[i]);
                audioFingerprint = sum;
            } catch(e) {}

            // Canvas fingerprint
            var canvasHash = '';
            try {
                var canvas = document.createElement('canvas');
                canvas.width = 240;
                canvas.height = 60;
                var ctx = canvas.getContext('2d');
                ctx.fillStyle = '#f60';
                ctx.fillRect(0, 0, 240, 60);
                ctx.fillStyle = '#069';
                ctx.font = '14px Arial';
                ctx.fillText('FingerprintJS', 2, 15);
                ctx.fillStyle = 'rgba(102,204,0,0.7)';
                ctx.font = '18px Times New Roman';
                ctx.fillText('FingerprintJS', 4, 45);
                canvasHash = djb2(canvas.toDataURL());
            } catch(e) {}

            // WebGL fingerprint
            var webglHash = '';
            try {
                var glCanvas = document.createElement('canvas');
                var gl = glCanvas.getContext('webgl');
                if (gl) {
                    var debugExt = gl.getExtension('WEBGL_debug_renderer_info');
                    var renderer = debugExt ? gl.getParameter(debugExt.UNMASKED_RENDERER_WEBGL) : '';
                    var vendor = debugExt ? gl.getParameter(debugExt.UNMASKED_VENDOR_WEBGL) : '';
                    var version = gl.getParameter(gl.VERSION) || '';
                    var extensions = gl.getSupportedExtensions() || [];
                    extensions = extensions.slice().sort();
                    var webglStr = renderer + '~' + vendor + '~' + version + '~' + extensions.join(',');
                    webglHash = djb2(webglStr);
                }
            } catch(e) {}

            return JSON.stringify({
                hardwareConcurrency: hardwareConcurrency,
                screenWidth: screenWidth,
                screenHeight: screenHeight,
                screenFrameTop: screenFrameTop,
                screenFrameBottom: screenFrameBottom,
                audioFingerprint: audioFingerprint,
                canvasHash: canvasHash,
                webglHash: webglHash
            });
        })();
        """

    // MARK: - Navigation Delegate Helper

    /// Reports the moment the blank page has settled — loaded or failed —
    /// into a stream the capture is waiting on. The stream keeps the one
    /// event, so a page that settles before anyone listens is not missed.
    private final class NavigationDelegate: NSObject, WKNavigationDelegate {
        private let onSettled: AsyncStream<Void>.Continuation

        init(onSettled: AsyncStream<Void>.Continuation) {
            self.onSettled = onSettled
            super.init()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onSettled.yield()
            onSettled.finish()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onSettled.yield()
            onSettled.finish()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onSettled.yield()
            onSettled.finish()
        }
    }

    // MARK: - Capture Baseline

    func captureBaseline() async -> FingerprintBaselineSpec? {
        isCapturing = true
        defer { isCapturing = false }

        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 240), configuration: configuration)
        webView = wv
        defer {
            webView = nil
            navDelegate = nil
        }

        let (settled, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let delegate = NavigationDelegate(onSettled: continuation)
        navDelegate = delegate
        wv.navigationDelegate = delegate

        wv.loadHTMLString("<html><body></body></html>", baseURL: nil)

        // A blank page settles in milliseconds; ten seconds without a word
        // means the web process is not coming back, and a missing baseline
        // beats a scan that never ends.
        let didSettle = await withTimeout(.seconds(10)) {
            for await _ in settled { return true }
            return false
        } ?? false
        guard didSettle else { return nil }

        guard let jsonString = try? await wv.evaluateJavaScript(Self.fingerprintScript) as? String,
              let data = jsonString.data(using: .utf8) else {
            return nil
        }

        struct RawFingerprint: Decodable {
            let hardwareConcurrency: Int
            let screenWidth: Int
            let screenHeight: Int
            let screenFrameTop: Int
            let screenFrameBottom: Int
            let audioFingerprint: Double
            let canvasHash: String
            let webglHash: String
        }

        guard let raw = try? JSONDecoder().decode(RawFingerprint.self, from: data) else {
            return nil
        }

        let spec = FingerprintBaselineSpec(
            audioFingerprint: raw.audioFingerprint,
            canvasHash: raw.canvasHash,
            webglHash: raw.webglHash,
            screenWidth: raw.screenWidth,
            screenHeight: raw.screenHeight,
            screenFrameTop: raw.screenFrameTop,
            screenFrameBottom: raw.screenFrameBottom,
            hardwareConcurrency: raw.hardwareConcurrency,
            capturedAt: Date()
        )

        baseline = spec
        return spec
    }

    // MARK: - Consistency Test

    func runConsistencyTest(iterations: Int = 5) async {
        isTesting = true
        lastRunIterations = iterations
        consistencyResults = []

        var captures: [FingerprintBaselineSpec] = []
        for _ in 0..<iterations {
            if let result = await captureBaseline() {
                captures.append(result)
            }
        }

        guard captures.count == iterations else {
            consistencyResults = []
            testPassed = false
            isTesting = false
            return
        }

        let fields: [(String, (FingerprintBaselineSpec) -> String)] = [
            ("hardwareConcurrency", { String($0.hardwareConcurrency) }),
            ("screenWidth", { String($0.screenWidth) }),
            ("screenHeight", { String($0.screenHeight) }),
            ("audioFingerprint", { String($0.audioFingerprint ?? 0) }),
            ("canvasHash", { $0.canvasHash ?? "" }),
            ("webglHash", { $0.webglHash ?? "" })
        ]

        var results: [FingerprintConsistencyResult] = []
        for (name, extractor) in fields {
            let values = captures.map { extractor($0) }
            let allSame = Set(values).count <= 1
            results.append(FingerprintConsistencyResult(
                field: name,
                values: values,
                isConsistent: allSame
            ))
        }

        consistencyResults = results
        testPassed = results.allSatisfy { $0.isConsistent }
        isTesting = false
    }
}
