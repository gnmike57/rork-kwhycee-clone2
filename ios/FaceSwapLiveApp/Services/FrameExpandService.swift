import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Why an expansion could not be used. Every case has a one-line user message.
nonisolated enum FrameExpandError: LocalizedError, Equatable {
    case notConfigured
    case imageTooLarge
    case imageUnreadable
    case network(String)
    case unauthorised
    case noCredit
    case rateLimited
    case server(Int)
    case noImage
    case wrongShape(expected: String, got: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "AI expand isn’t available in this build."
        case .imageTooLarge: "The photo is too large to send. Try a smaller photo."
        case .imageUnreadable: "The photo couldn’t be prepared."
        case .network(let text): "No connection: \(text)"
        case .unauthorised: "AI expand isn’t authorised right now. Restart the app and try again."
        case .noCredit: "AI credit has run out."
        case .rateLimited: "Too many requests. Wait a moment and try again."
        case .server(let code): "The AI service failed (\(code)). Try again."
        case .noImage: "The AI returned no picture. Try again."
        case .wrongShape(let expected, let got): "The AI returned the wrong shape (\(got), needed \(expected)). Try again."
        }
    }
}

/// Continues a still's surroundings outward to an exact frame with Rork AI.
///
/// The still is placed whole inside a canvas of the target shape with neutral
/// grey where new picture is needed, and Gemini is asked to paint only that
/// grey. The answer is checked for shape and resized to the exact target pixels
/// before anyone can use it. Nothing here touches the loaded media; the caller
/// decides what to do with the result.
nonisolated final class FrameExpandService: Sendable {

    static let modelID = "google/gemini-3.1-flash-image"

    /// Vercel's request-body ceiling is 4.5 MB; base64 adds a third.
    private static let uploadBudget = 3_000_000

    /// Longest side sent up. Gemini answers at about this scale anyway.
    private static let composeLongSide: CGFloat = 1280

    private let toolkitURL: String
    private let secretKey: String

    /// The build's toolkit settings live on the main actor; they are read
    /// once here and kept as plain values the background work can use.
    @MainActor
    init() {
        toolkitURL = Config.EXPO_PUBLIC_TOOLKIT_URL
        secretKey = Config.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY
    }

    private var isConfigured: Bool {
        !toolkitURL.isEmpty && !secretKey.isEmpty
    }

    /// The expanded still at exactly `target.width × target.height` pixels.
    func expand(_ image: UIImage, to target: FrameTarget) async throws -> UIImage {
        guard isConfigured else { throw FrameExpandError.notConfigured }

        // Composing and finishing are heavy image work; both run on the
        // concurrent pool inside the caller's own task, so cancelling the
        // expand cancels them too.
        let payload = try await Self.prepareUpload(image, target: target)
        let data = try await send(payload.jpeg, prompt: payload.prompt)
        return try await Self.finish(data, target: target)
    }

    // MARK: - Prepare

    private struct Upload: Sendable {
        let jpeg: Data
        let prompt: String
    }

    @concurrent
    private static func prepareUpload(_ image: UIImage, target: FrameTarget) async throws -> Upload {
        let composed = compose(image, aspect: target.aspect)
        guard let composed else { throw FrameExpandError.imageUnreadable }

        let ladder: [(size: CGFloat, quality: CGFloat)] = [
            (composeLongSide, 0.82), (1024, 0.78), (832, 0.74), (640, 0.70), (512, 0.65)
        ]
        var jpeg: Data?
        for step in ladder {
            guard let scaled = scaled(composed, longSide: step.size),
                  let data = scaled.jpegData(compressionQuality: step.quality) else { continue }
            if data.count <= uploadBudget {
                jpeg = data
                break
            }
        }
        guard let jpeg else { throw FrameExpandError.imageTooLarge }

        let orientation = target.isPortrait ? "portrait" : "landscape"
        let bands = bandsDescription(image: image.size, aspect: target.aspect)
        let prompt = """
        This photo has been placed on a \(orientation) canvas with an aspect ratio of \
        \(target.width):\(target.height). The flat grey areas \(bands) are empty. \
        Fill only the grey areas by continuing the existing scene and background outward \
        naturally — same lighting, colours, focus, perspective and camera grain. \
        Keep every existing pixel of the photo exactly as it is: do not move, resize, \
        crop, retouch or change the person or any object. Do not add people, text, \
        logos or borders. Return one image with exactly the same \(target.width):\(target.height) \
        aspect ratio as the canvas.
        """
        return Upload(jpeg: jpeg, prompt: prompt)
    }

    /// The whole still, fitted inside a target-shaped canvas, grey where the AI
    /// must paint.
    private static func compose(_ image: UIImage, aspect: Double) -> UIImage? {
        let source = image.size
        guard source.width > 0, source.height > 0, aspect > 0 else { return nil }
        let sourceAspect = source.width / source.height
        var canvas = source
        if sourceAspect < aspect {
            canvas.width = source.height * aspect
        } else {
            canvas.height = source.width / aspect
        }
        let longest = max(canvas.width, canvas.height)
        let scale = min(1, composeLongSide / longest)
        let outSize = CGSize(
            width: max(16, (canvas.width * scale).rounded()),
            height: max(16, (canvas.height * scale).rounded())
        )
        let drawSize = CGSize(width: source.width * scale, height: source.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outSize, format: format)
        return renderer.image { ctx in
            UIColor(white: 0.5, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: outSize))
            image.draw(in: CGRect(
                x: ((outSize.width - drawSize.width) * 0.5).rounded(),
                y: ((outSize.height - drawSize.height) * 0.5).rounded(),
                width: drawSize.width,
                height: drawSize.height
            ))
        }
    }

    private static func bandsDescription(image: CGSize, aspect: Double) -> String {
        guard image.height > 0 else { return "around the photo" }
        return (image.width / image.height) < aspect ? "on the left and right" : "at the top and bottom"
    }

    private static func scaled(_ image: UIImage, longSide: CGFloat) -> UIImage? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, longSide / longest)
        if scale >= 1 { return image }
        let out = CGSize(
            width: max(1, (size.width * scale).rounded()),
            height: max(1, (size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: out, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: out))
        }
    }

    // MARK: - Send

    private struct ChatImageResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let images: [ImageEntry]?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    /// Providers answer with either a bare data URI or an `image_url` object.
    private enum ImageEntry: Decodable {
        case uri(String)
        case object(String)

        var dataURI: String {
            switch self {
            case .uri(let value), .object(let value): value
            }
        }

        private struct Wrapper: Decodable {
            struct URLBox: Decodable { let url: String }
            let image_url: URLBox?
            let url: String?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .uri(text)
                return
            }
            let wrapper = try container.decode(Wrapper.self)
            if let url = wrapper.image_url?.url ?? wrapper.url {
                self = .object(url)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "No image URL")
            }
        }
    }

    private func send(_ jpeg: Data, prompt: String) async throws -> Data {
        guard let url = URL(string: "\(toolkitURL)/v2/vercel/v1/chat/completions") else {
            throw FrameExpandError.notConfigured
        }
        let body: [String: Any] = [
            "model": Self.modelID,
            "modalities": ["text", "image"],
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]],
                        ["type": "text", "text": prompt]
                    ]
                ]
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(secretKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FrameExpandError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw FrameExpandError.server(0) }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw FrameExpandError.unauthorised
        case 402: throw FrameExpandError.noCredit
        case 413: throw FrameExpandError.imageTooLarge
        case 429: throw FrameExpandError.rateLimited
        default: throw FrameExpandError.server(http.statusCode)
        }

        let decoded: ChatImageResponse
        do {
            decoded = try JSONDecoder().decode(ChatImageResponse.self, from: data)
        } catch {
            throw FrameExpandError.noImage
        }
        guard let entry = decoded.choices.first?.message.images?.first else {
            throw FrameExpandError.noImage
        }
        let uri = entry.dataURI
        let raw: Substring
        if let comma = uri.firstIndex(of: ",") , uri.hasPrefix("data:") {
            raw = uri[uri.index(after: comma)...]
        } else {
            raw = Substring(uri)
        }
        guard let imageData = Data(base64Encoded: String(raw), options: [.ignoreUnknownCharacters]) else {
            throw FrameExpandError.noImage
        }
        return imageData
    }

    // MARK: - Check and finish

    /// The answer must be the target's shape. A small drift is corrected by a
    /// centred cover-fit; anything larger is refused rather than used silently.
    @concurrent
    private static func finish(_ data: Data, target: FrameTarget) async throws -> UIImage {
        guard let result = UIImage(data: data), result.size.width > 0, result.size.height > 0 else {
            throw FrameExpandError.noImage
        }
        let gotAspect = result.size.width / result.size.height
        let want = target.aspect
        let drift = max(gotAspect / want, want / gotAspect) - 1
        if drift > 0.12 {
            let got = "\(Int(result.size.width))×\(Int(result.size.height))"
            throw FrameExpandError.wrongShape(expected: target.sizeText, got: got)
        }
        let out = CGSize(width: target.width, height: target.height)
        let scale = max(out.width / result.size.width, out.height / result.size.height)
        let drawSize = CGSize(width: result.size.width * scale, height: result.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: out, format: format)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: out))
            result.draw(in: CGRect(
                x: (out.width - drawSize.width) * 0.5,
                y: (out.height - drawSize.height) * 0.5,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
    }
}
