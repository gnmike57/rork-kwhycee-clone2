import WebKit
import UIKit

/// Serves the app's prepared media to the page over the `fslvideo` and
/// `fslimage` schemes.
///
/// WebKit calls scheme handlers on the main actor, and every writer of this
/// state (the browser view model) is main-actor too, so the state needs no
/// lock. Only the expensive photo stamping leaves the main actor, and its
/// result comes back here before anything is sent to the page.
final class LocalResourceHandler: NSObject, WKURLSchemeHandler {
    var frontVideoFileURL: URL?
    var backVideoFileURL: URL?
    var frontVideoFileURL2: URL?
    var backVideoFileURL2: URL?
    var frontImageData: Data?
    var backImageData: Data? {
        didSet { invalidateBackTemplate() }
    }

    /// Source images for on-demand EXIF stamping (especially back native template).
    /// Index 0 = sequence media 1, index 1 = sequence media 2.
    private var frontSourceImages: [UIImage?] = [nil, nil]
    private var backSourceImages: [UIImage?] = [nil, nil]
    var stampBackOnDemand: Bool = true {
        didSet { invalidateBackTemplate() }
    }
    private var activeTasks: Set<ObjectIdentifier> = []
    private var backTemplateCache: [Int: BackTemplateCache] = [:]
    private var backTemplateGeneration: Int = 0
    private let exifService = EXIFMetadataService()

    /// Cached native back-camera template JPEG for one sequence slot.
    /// Invalidated by bumping `backTemplateGeneration` whenever back source state changes.
    private struct BackTemplateCache {
        let generation: Int
        let data: Data
    }

    /// Upper bound for a single ranged read so a large video never loads fully into memory.
    private static let maxRangeChunkBytes: UInt64 = 4 * 1024 * 1024

    var videoFileURL: URL? {
        get { frontVideoFileURL ?? backVideoFileURL }
        set {
            frontVideoFileURL = newValue
            backVideoFileURL = newValue
        }
    }

    var frontSourceImage: UIImage? {
        get { frontSourceImages[0] }
        set { frontSourceImages[0] = newValue }
    }

    var backSourceImage: UIImage? {
        get { backSourceImages[0] }
        set {
            backSourceImages[0] = newValue
            invalidateBackTemplate()
        }
    }

    func setFrontSourceImage(_ image: UIImage?, slot: Int) {
        frontSourceImages[max(0, min(1, slot))] = image
    }

    func setBackSourceImage(_ image: UIImage?, slot: Int) {
        backSourceImages[max(0, min(1, slot))] = image
        invalidateBackTemplate()
    }

    func clearAllSourceImages() {
        frontSourceImages = [nil, nil]
        backSourceImages = [nil, nil]
        frontImageData = nil
        backImageData = nil
        invalidateBackTemplate()
    }

    private func invalidateBackTemplate() {
        backTemplateCache.removeAll()
        backTemplateGeneration &+= 1
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        markStarted(urlSchemeTask)

        let method = urlSchemeTask.request.httpMethod?.uppercased() ?? "GET"
        guard let requestURL = urlSchemeTask.request.url else {
            fail(urlSchemeTask, URLError(.badURL))
            return
        }
        let scheme = requestURL.scheme ?? ""

        if scheme == "fslimage" {
            handleImageRequest(urlSchemeTask: urlSchemeTask, requestURL: requestURL, method: method)
            return
        }

        if method == "OPTIONS" {
            guard let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 204,
                httpVersion: "HTTP/1.1",
                headerFields: corsHeaders()
            ) else {
                fail(urlSchemeTask, URLError(.unknown))
                return
            }
            complete(urlSchemeTask, response: response, data: Data())
            return
        }

        let path = (requestURL.host ?? requestURL.path).lowercased()
        let fileURL: URL?
        if path.contains("front2") || path.contains("front-2") {
            fileURL = frontVideoFileURL2 ?? frontVideoFileURL ?? backVideoFileURL
        } else if path.contains("back2") || path.contains("back-2") {
            fileURL = backVideoFileURL2 ?? backVideoFileURL ?? frontVideoFileURL
        } else if path.contains("front") {
            fileURL = frontVideoFileURL ?? backVideoFileURL
        } else if path.contains("back") {
            fileURL = backVideoFileURL ?? frontVideoFileURL
        } else {
            fileURL = frontVideoFileURL ?? backVideoFileURL
        }

        guard let fileURL else {
            fail(urlSchemeTask, URLError(.fileDoesNotExist))
            return
        }

        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        } catch {
            fail(urlSchemeTask, URLError(.cannotOpenFile))
            return
        }

        let fileSize = (attrs[.size] as? UInt64) ?? 0
        let mime = mimeType(for: fileURL)
        let rangeHeader = urlSchemeTask.request.value(forHTTPHeaderField: "Range")

        if method == "HEAD" {
            var headers = corsHeaders()
            headers["Content-Type"] = mime
            headers["Content-Length"] = "\(fileSize)"
            headers["Accept-Ranges"] = "bytes"
            guard let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                fail(urlSchemeTask, URLError(.unknown))
                return
            }
            complete(urlSchemeTask, response: response, data: Data())
            return
        }

        // A zero-byte file (for example a conversion that produced nothing) can satisfy no read.
        // Answer before any unsigned range arithmetic, which would trap on `fileSize - 1`.
        guard fileSize > 0 else {
            if rangeHeader != nil {
                sendUnsatisfiableRange(urlSchemeTask, requestURL: requestURL, fileSize: 0)
            } else {
                var headers = corsHeaders()
                headers["Content-Type"] = mime
                headers["Content-Length"] = "0"
                headers["Accept-Ranges"] = "bytes"
                guard let response = HTTPURLResponse(
                    url: requestURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                ) else {
                    fail(urlSchemeTask, URLError(.zeroByteResource))
                    return
                }
                complete(urlSchemeTask, response: response, data: Data())
            }
            return
        }

        let lastIndex = fileSize - 1

        if let rangeHeader, rangeHeader.hasPrefix("bytes=") {
            let spec = String(rangeHeader.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let startText = parts.isEmpty ? "" : String(parts[0]).trimmingCharacters(in: .whitespaces)
            let endText = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

            var start: UInt64 = 0
            var end: UInt64 = lastIndex
            var isValid = true

            if startText.isEmpty {
                // Suffix form "bytes=-N" asks for the trailing N bytes.
                if let suffix = UInt64(endText), suffix > 0 {
                    start = fileSize - min(suffix, fileSize)
                    end = lastIndex
                } else {
                    isValid = false
                }
            } else if let parsedStart = UInt64(startText) {
                start = parsedStart
                end = UInt64(endText).map { min($0, lastIndex) } ?? lastIndex
            } else {
                isValid = false
            }

            guard isValid, start <= lastIndex, end >= start else {
                sendUnsatisfiableRange(urlSchemeTask, requestURL: requestURL, fileSize: fileSize)
                return
            }

            // Serve at most one chunk per response so an open-ended range on a large
            // video never pulls the whole file into memory.
            var length = end - start + 1
            if length > Self.maxRangeChunkBytes {
                length = Self.maxRangeChunkBytes
                end = start + length - 1
            }

            let data: Data
            do {
                let handle = try FileHandle(forReadingFrom: fileURL)
                defer { try? handle.close() }
                try handle.seek(toOffset: start)
                data = try autoreleasepool { try handle.read(upToCount: Int(length)) ?? Data() }
            } catch {
                fail(urlSchemeTask, URLError(.cannotOpenFile))
                return
            }

            var headers = corsHeaders()
            headers["Content-Type"] = mime
            headers["Content-Length"] = "\(data.count)"
            headers["Content-Range"] = "bytes \(start)-\(end)/\(fileSize)"
            headers["Accept-Ranges"] = "bytes"

            guard let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 206,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                fail(urlSchemeTask, URLError(.unknown))
                return
            }
            complete(urlSchemeTask, response: response, data: data)
            return
        }

        var headers = corsHeaders()
        headers["Content-Type"] = mime
        headers["Content-Length"] = "\(fileSize)"
        headers["Accept-Ranges"] = "bytes"

        guard let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            fail(urlSchemeTask, URLError(.unknown))
            return
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            fail(urlSchemeTask, URLError(.cannotOpenFile))
            return
        }
        defer { try? handle.close() }

        guard send(urlSchemeTask, response: response) else { return }

        // Stream in bounded chunks and bail out the moment the page stops the task.
        var remaining = fileSize
        while remaining > 0 {
            let chunkSize = Int(min(remaining, Self.maxRangeChunkBytes))
            guard let chunk = try? autoreleasepool(invoking: { try handle.read(upToCount: chunkSize) }),
                  !chunk.isEmpty else { break }
            guard send(urlSchemeTask, data: chunk) else { return }
            remaining -= UInt64(chunk.count)
        }
        finish(urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        _ = claimCompletion(urlSchemeTask)
    }

    // MARK: - Task lifecycle
    //
    // WKWebView raises an unrecoverable exception when a scheme task receives callbacks
    // after it was stopped, so every reply is gated on the task still being live.

    private func markStarted(_ task: any WKURLSchemeTask) {
        activeTasks.insert(ObjectIdentifier(task as AnyObject))
    }

    private func isRunning(_ task: any WKURLSchemeTask) -> Bool {
        activeTasks.contains(ObjectIdentifier(task as AnyObject))
    }

    /// Retires the task. Returns `false` when it was already stopped or completed.
    private func claimCompletion(_ task: any WKURLSchemeTask) -> Bool {
        activeTasks.remove(ObjectIdentifier(task as AnyObject)) != nil
    }

    @discardableResult
    private func send(_ task: any WKURLSchemeTask, response: HTTPURLResponse) -> Bool {
        guard isRunning(task) else { return false }
        task.didReceive(response)
        return true
    }

    @discardableResult
    private func send(_ task: any WKURLSchemeTask, data: Data) -> Bool {
        guard isRunning(task) else { return false }
        task.didReceive(data)
        return true
    }

    private func finish(_ task: any WKURLSchemeTask) {
        guard claimCompletion(task) else { return }
        task.didFinish()
    }

    private func fail(_ task: any WKURLSchemeTask, _ error: Error) {
        guard claimCompletion(task) else { return }
        task.didFailWithError(error)
    }

    private func complete(_ task: any WKURLSchemeTask, response: HTTPURLResponse, data: Data) {
        guard send(task, response: response) else { return }
        guard send(task, data: data) else { return }
        finish(task)
    }

    private func sendUnsatisfiableRange(_ task: any WKURLSchemeTask, requestURL: URL, fileSize: UInt64) {
        var headers = corsHeaders()
        headers["Content-Range"] = "bytes */\(fileSize)"
        guard let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 416,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            fail(task, URLError(.unknown))
            return
        }
        complete(task, response: response, data: Data())
    }

    // MARK: - Images

    private func handleImageRequest(urlSchemeTask: any WKURLSchemeTask, requestURL: URL, method: String) {
        if method == "OPTIONS" {
            guard let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 204,
                httpVersion: "HTTP/1.1",
                headerFields: corsHeaders()
            ) else {
                fail(urlSchemeTask, URLError(.unknown))
                return
            }
            complete(urlSchemeTask, response: response, data: Data())
            return
        }

        let path = (requestURL.host ?? requestURL.path).lowercased()
        let isBack = path.contains("back")
        let isFront = path.contains("front")
        let slot = slotIndex(from: requestURL)

        // Stamping a native-size photo is real work, so it happens off the main
        // actor and the reply waits for it. The task may be stopped meanwhile;
        // the lifecycle guards below make that harmless.
        Task {
            var data: Data?
            if isBack || (!isFront && hasBackSource(slot: slot)) {
                data = await buildBackImageDataOnDemand(slot: slot)
                if data == nil { data = backImageData ?? frontImageData }
            } else if isFront {
                data = frontImageData
                if data == nil { data = await buildFrontImageDataFallback(slot: slot) }
                if data == nil { data = backImageData }
            } else {
                data = frontImageData ?? backImageData
                if data == nil { data = await buildBackImageDataOnDemand(slot: slot) }
            }

            guard isRunning(urlSchemeTask) else { return }
            guard let data else {
                fail(urlSchemeTask, URLError(.fileDoesNotExist))
                return
            }

            var headers = corsHeaders()
            headers["Content-Type"] = "image/jpeg"
            headers["Content-Length"] = "\(data.count)"
            headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
            headers["Pragma"] = "no-cache"

            guard let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                fail(urlSchemeTask, URLError(.unknown))
                return
            }
            complete(urlSchemeTask, response: response, data: data)
        }
    }

    private func slotIndex(from url: URL) -> Int {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return 0 }
        if let raw = items.first(where: { $0.name == "i" || $0.name == "slot" })?.value,
           let value = Int(raw) {
            return max(0, min(1, value))
        }
        return 0
    }

    private func hasBackSource(slot: Int) -> Bool {
        backSourceImages[slot] != nil || backSourceImages[0] != nil || backImageData != nil
    }

    /// Serves the back-camera JPEG with capture timestamps taken at the request moment.
    ///
    /// The native sensor-size template is rendered once per source image and cached; later
    /// requests only rewrite the timestamp tags, which keeps each capture cheap in memory.
    private func buildBackImageDataOnDemand(slot: Int) async -> Data? {
        let idx = max(0, min(1, slot))
        let source = backSourceImages[idx] ?? backSourceImages[0] ?? backImageData.flatMap { UIImage(data: $0) }
        guard let source else { return nil }
        guard stampBackOnDemand else { return backImageData }

        let generation = backTemplateGeneration
        let exif = exifService

        if let cached = backTemplateCache[idx], cached.generation == generation {
            let template = cached.data
            return await Self.restampTimestamps(in: template, exif: exif) ?? template
        }

        guard let built = await Self.renderBackTemplate(from: source, exif: exif) else { return nil }
        if backTemplateGeneration == generation {
            backTemplateCache[idx] = BackTemplateCache(generation: generation, data: built)
        }
        return built
    }

    private func buildFrontImageDataFallback(slot: Int) async -> Data? {
        guard let source = frontSourceImages[slot] ?? frontSourceImages[0] else { return nil }
        return await Self.stampFront(source, exif: exifService)
    }

    @concurrent
    nonisolated private static func renderBackTemplate(from source: UIImage, exif: EXIFMetadataService) async -> Data? {
        autoreleasepool { exif.nativeBackCameraJPEG(from: source, capturedAt: Date()) }
    }

    @concurrent
    nonisolated private static func restampTimestamps(in template: Data, exif: EXIFMetadataService) async -> Data? {
        autoreleasepool { exif.restampCaptureTimestamps(in: template, capturedAt: Date()) }
    }

    @concurrent
    nonisolated private static func stampFront(_ source: UIImage, exif: EXIFMetadataService) async -> Data? {
        autoreleasepool { exif.jpegDataWithEXIF(image: source, camera: nil, hardware: nil, capturedAt: Date()) }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        default: return "video/mp4"
        }
    }

    private func corsHeaders() -> [String: String] {
        [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
            "Access-Control-Allow-Headers": "*",
            "Access-Control-Max-Age": "86400"
        ]
    }
}
