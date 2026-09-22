import CoreGraphics
import Foundation

/// The four frame shapes a site can ask for.
///
/// A still framed for a widescreen ask is framed wrongly for a 4:3 one, so
/// framing is remembered per shape rather than per photo. The injected page
/// classifies its own canvas with the same boundaries (`frameShapeKey` in
/// `StyleSheetProvider.swift`), so both sides always pick the same framing — a
/// change to these numbers must land there as well.
nonisolated enum FrameShape: String, Codable, Sendable, CaseIterable, Hashable {
    case widescreen
    case fourThree
    case square
    case portrait

    /// From 16:9 (1.778) down to just under 3:2, everything reads as widescreen.
    static let widescreenFrom = 1.55
    /// 4:3 is 1.333; anything from here up to widescreen belongs with it.
    static let fourThreeFrom = 1.15
    /// Above this and below 4:3 the frame is near enough square.
    static let squareFrom = 0.87

    static func of(width: Int, height: Int) -> FrameShape {
        guard width > 0, height > 0 else { return .widescreen }
        return of(aspect: Double(width) / Double(height))
    }

    static func of(_ size: CGSize) -> FrameShape {
        guard size.width > 0, size.height > 0 else { return .widescreen }
        return of(aspect: Double(size.width / size.height))
    }

    static func of(aspect: Double) -> FrameShape {
        if aspect >= widescreenFrom { return .widescreen }
        if aspect >= fourThreeFrom { return .fourThree }
        if aspect > squareFrom { return .square }
        return .portrait
    }

    init(_ target: FrameTarget) {
        self = Self.of(width: target.width, height: target.height)
    }

    /// The one-letter key the page's crop map is keyed by.
    var jsKey: String {
        switch self {
        case .widescreen: "w"
        case .fourThree: "f"
        case .square: "s"
        case .portrait: "p"
        }
    }

    var title: String {
        switch self {
        case .widescreen: "Widescreen"
        case .fourThree: "4:3"
        case .square: "Square"
        case .portrait: "Portrait"
        }
    }

    /// A representative size, used when a shape needs a frame of its own.
    var exampleSize: (width: Int, height: Int) {
        switch self {
        case .widescreen: (1920, 1080)
        case .fourThree: (640, 480)
        case .square: (640, 640)
        case .portrait: (480, 640)
        }
    }
}

/// One still's framing, kept apart for each frame shape.
///
/// Every shape starts at the untouched cover-fit, so a slot nobody has framed
/// behaves exactly as a single identity crop always did.
nonisolated struct ShapeCrops: Codable, Equatable, Sendable {
    private var values: [String: StillCrop]

    init() { values = [:] }

    static let identity = ShapeCrops()

    subscript(shape: FrameShape) -> StillCrop {
        get { values[shape.rawValue] ?? .identity }
        set {
            if newValue.isIdentity {
                values.removeValue(forKey: shape.rawValue)
            } else {
                values[shape.rawValue] = newValue
            }
        }
    }

    /// True when no shape has been framed at all.
    var isIdentityEverywhere: Bool { values.isEmpty }

    /// Shapes the user (or auto-prep) has actually framed.
    var framedShapes: [FrameShape] {
        FrameShape.allCases.filter { values[$0.rawValue] != nil }
    }

    mutating func reset() { values.removeAll() }

    mutating func reset(_ shape: FrameShape) {
        values.removeValue(forKey: shape.rawValue)
    }
}

/// The frame sizes sites really ask for.
///
/// The audit ladder grants far more than these, but in practice a live request
/// names one of three landscape sizes. They are treated as first-class
/// everywhere so media is prepared for them before a site ever asks.
nonisolated enum CommonFrames {
    /// Largest first, which is also the order the picker shows them in.
    static let sizes: [(width: Int, height: Int)] = [
        (1920, 1080), (1280, 720), (640, 480)
    ]

    static var targets: [FrameTarget] {
        sizes.map { FrameTarget(width: $0.width, height: $0.height, origin: .commonRequest) }
    }

    /// The widest common frame, which is what an import is sized to fill.
    static let widest = (width: 1920, height: 1080)

    static func isCommon(width: Int, height: Int) -> Bool {
        sizes.contains { $0.width == width && $0.height == height }
    }
}
