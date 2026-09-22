import SwiftUI
import WebKit

struct BrowserWebContainer: UIViewRepresentable {
    let viewModel: BrowserViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        config.setURLSchemeHandler(viewModel.schemeHandler, forURLScheme: "fslvideo")
        config.setURLSchemeHandler(viewModel.imageSchemeHandler, forURLScheme: "fslimage")

        // Device-matched media bridge. The page resolves with defaults on its own
        // if either handler is missing, so nothing depends on them being present.
        config.userContentController.add(context.coordinator, name: "fslPrompt")
        config.userContentController.add(context.coordinator, name: "fslStatus")

        let styleScript = WKUserScript(
            source: StyleSheetProvider.patchScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(styleScript)

        let constraintScript = WKUserScript(
            source: StyleSheetProvider.constraintLoggingScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(constraintScript)

        let behaviorScript = WKUserScript(
            source: viewModel.behaviorScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(behaviorScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = StyleSheetProvider.safariUserAgent(for: viewModel.behavior.audit)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = true
        context.coordinator.webView = webView
        viewModel.webView = webView

        // Each observation captures the coordinator weakly and rebinds it to a
        // strong `let` before hopping, so no mutable capture crosses into the task.
        let coordinator = context.coordinator
        coordinator.progressObservation = webView.observe(\.estimatedProgress) { [weak coordinator] view, _ in
            guard let coordinator else { return }
            Task { @MainActor in
                coordinator.viewModel?.estimatedProgress = view.estimatedProgress
            }
        }
        coordinator.titleObservation = webView.observe(\.title) { [weak coordinator] view, _ in
            guard let coordinator else { return }
            Task { @MainActor in
                coordinator.viewModel?.pageTitle = view.title ?? ""
            }
        }
        coordinator.urlObservation = webView.observe(\.url) { [weak coordinator] view, _ in
            guard let coordinator else { return }
            Task { @MainActor in
                if let url = view.url, let vm = coordinator.viewModel {
                    vm.urlText = url.absoluteString
                    vm.currentURL = url
                }
            }
        }
        coordinator.loadingObservation = webView.observe(\.isLoading) { [weak coordinator] view, _ in
            guard let coordinator else { return }
            Task { @MainActor in
                coordinator.viewModel?.isLoading = view.isLoading
            }
        }
        coordinator.canGoBackObservation = webView.observe(\.canGoBack) { [weak coordinator] view, _ in
            guard let coordinator else { return }
            Task { @MainActor in
                coordinator.viewModel?.canGoBack = view.canGoBack
            }
        }
        coordinator.canGoForwardObservation = webView.observe(\.canGoForward) { [weak coordinator] view, _ in
            guard let coordinator else { return }
            Task { @MainActor in
                coordinator.viewModel?.canGoForward = view.canGoForward
            }
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let url = viewModel.pendingNavigationURL {
            viewModel.pendingNavigationURL = nil
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // Break the bridge's hold on the browser: the message handlers are the
        // web view's only strong route back to the coordinator, so they are
        // removed explicitly and the observations released.
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "fslPrompt")
        controller.removeScriptMessageHandler(forName: "fslStatus")
        coordinator.progressObservation = nil
        coordinator.titleObservation = nil
        coordinator.urlObservation = nil
        coordinator.loadingObservation = nil
        coordinator.canGoBackObservation = nil
        coordinator.canGoForwardObservation = nil
        coordinator.webView = nil
    }

    /// Every WebKit delegate protocol here is main-actor bound, so the delegate
    /// methods stay on the main actor and touch the view model directly. The
    /// navigation lifecycle hooks still defer their view-model work by one turn,
    /// which is the ordering the rest of the browser was built against.
    class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, WKDownloadDelegate {
        /// Held weakly so the bridge and the browser never keep each other alive
        /// in a loop. The view model is owned by the screen that hosts this web
        /// view; the bridge is owned by the web view's configuration.
        weak var viewModel: BrowserViewModel?
        weak var webView: WKWebView?
        let downloadSources = DownloadSourceRegistry()
        var progressObservation: NSKeyValueObservation?
        var titleObservation: NSKeyValueObservation?
        var urlObservation: NSKeyValueObservation?
        var loadingObservation: NSKeyValueObservation?
        var canGoBackObservation: NSKeyValueObservation?
        var canGoForwardObservation: NSKeyValueObservation?

        init(viewModel: BrowserViewModel) {
            self.viewModel = viewModel
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
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
        ) {
            // Anything the web view cannot render (a ZIP, a document) becomes a
            // real download instead of a silently dead tap.
            if navigationResponse.canShowMIMEType == false {
                decisionHandler(.download)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            download.delegate = self
            downloadSources.setSource(ObjectIdentifier(download), url: navigationAction.request.url)
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            download.delegate = self
            downloadSources.setSource(ObjectIdentifier(download), url: navigationResponse.response.url)
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping @MainActor (URL?) -> Void
        ) {
            let source = downloadSources.source(ObjectIdentifier(download))
            guard let vm = viewModel else {
                completionHandler(nil)
                return
            }
            let destination = vm.downloadService.makeDestination(
                download: download,
                response: response,
                suggestedFilename: suggestedFilename,
                sourceURL: source
            )
            completionHandler(destination)
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            viewModel?.downloadService.handleFailure(download, error: error, resumeData: resumeData)
        }

        func downloadDidFinish(_ download: WKDownload) {
            viewModel?.downloadService.handleFinish(download)
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            let vm = viewModel
            Task { @MainActor in
                // The page a waiting card belonged to is going away, so the card must
                // go with it. The old page is never left hanging: it proceeds on its
                // own defaults as soon as the hold runs out.
                vm?.discardPendingPrompt()
                vm?.activeStreamFacing = nil
                vm?.isLiveStreamActive = false
                vm?.motionEasedLevel = 0
                vm?.resetInjectSessionForNewDocument()
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            let vm = viewModel
            Task { @MainActor in
                // Earliest point the new document really exists. Anything that
                // belongs to one site has to land here rather than in the shared
                // document-start script, which is built before the app knows
                // where it is going.
                vm?.applySiteState()
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let vm = viewModel
            Task { @MainActor in
                vm?.syncMediaToPage()
                vm?.fetchConstraintLogs()
                // A fresh document means no feed is running yet.
                vm?.discardPendingPrompt()
                vm?.activeStreamFacing = nil
                vm?.isLiveStreamActive = false
                vm?.motionEasedLevel = 0
                vm?.resetInjectSessionForNewDocument()
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let payload = message.body as? [String: Any] else { return }
            let name = message.name
            let vm = viewModel
            Task { @MainActor in
                switch name {
                case "fslPrompt":
                    vm?.handlePromptMessage(payload)
                case "fslStatus":
                    vm?.handleStatusMessage(payload)
                default:
                    break
                }
            }
        }
    }
}
