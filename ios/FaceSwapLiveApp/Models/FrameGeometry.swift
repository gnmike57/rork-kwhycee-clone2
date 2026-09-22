import CoreGraphics
import Foundation

/// A face found in a still, in the still's own coordinates, 0...1 with the
/// origin top-left — the orientation the page draws in.
nonisolated struct FaceBox: Equatable, Sendable {
    var rect: CGRect

    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    /// The face with room for hair and chin, the region a crop should keep.
    var padded: CGRect {
        rect.insetBy(dx: -rect.width * 0.30, dy: -rect.height * 0.45)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

/// How the page's feed will place one still into one frame, at rest.
///
/// Built from `FrameRigMath` alone, so every number here is the number the
/// site will see rather than an approximation of it.
nonisolated struct FrameGeometry: Equatable, Sendable {
    /// The frame the page draws into, pixels.
    let canvas: CGSize
    /// The still's pixel size, as the page's `naturalWidth/Height` report it.
    let image: CGSize
    /// The crop that is really applied: `nil` when the switch is off or the crop
    /// is identity, exactly as `stillCropFor` returns `null`.
    let crop: StillCrop?
    /// Motion strength multiplier, or `nil` when motion is off.
    let motionK: Double?

    /// Where the still sits in the frame with the drift at rest.
    let imageRect: CGRect
    /// The bake bitmap and placement with motion on, when motion is on.
    let rig: FrameRigMath.Rig?

    init(canvas: CGSize, image: CGSize, crop: StillCrop?, motionK: Double?) {
        self.canvas = canvas
        self.image = image
        self.crop = crop
        self.motionK = motionK
        if let k = motionK {
            let rig = FrameRigMath.rig(canvas: canvas, image: image, crop: crop, k: k)
            self.rig = rig
            self.imageRect = rig.steadyImageRect
        } else {
            self.rig = nil
            self.imageRect = FrameRigMath.steadyRect(canvas: canvas, image: image, crop: crop)
        }
    }

    var canvasRect: CGRect { CGRect(origin: .zero, size: canvas) }

    /// Frame pixels per still pixel. Above 1 the still is being stretched.
    var drawScale: Double {
        guard image.width > 0 else { return 1 }
        return imageRect.width / image.width
    }

    /// The region that the movement never carries out of the frame.
    var safeRect: CGRect {
        guard let k = motionK else { return canvasRect }
        return canvasRect.insetBy(
            dx: FrameRigMath.edgeInset(k: k, dimension: canvas.width),
            dy: FrameRigMath.edgeInset(k: k, dimension: canvas.height)
        )
    }

    /// Share of the still that lands inside the frame, 0...1.
    var visibleFraction: Double {
        let area = imageRect.width * imageRect.height
        guard area > 0 else { return 0 }
        let shown = imageRect.intersection(canvasRect)
        guard !shown.isNull else { return 0 }
        return min(1, (shown.width * shown.height) / area)
    }

    /// Share of the still that the frame cuts away, 0...1.
    var lostFraction: Double { max(0, 1 - visibleFraction) }

    /// Share of the frame the still covers. Below 1 the site sees empty edges.
    var coverage: Double {
        let area = canvas.width * canvas.height
        guard area > 0 else { return 1 }
        let covered = imageRect.intersection(canvasRect)
        guard !covered.isNull else { return 0 }
        return min(1, (covered.width * covered.height) / area)
    }

    var showsEmptyEdges: Bool { coverage < 0.995 }

    /// Portrait into landscape or the reverse.
    var orientationMismatch: Bool {
        let imagePortrait = image.height > image.width * 1.15
        let imageLandscape = image.width > image.height * 1.15
        let framePortrait = canvas.height > canvas.width * 1.15
        let frameLandscape = canvas.width > canvas.height * 1.15
        return (imagePortrait && frameLandscape) || (imageLandscape && framePortrait)
    }

    // MARK: - Faces

    /// The face in frame coordinates.
    func faceRect(_ face: FaceBox) -> CGRect {
        CGRect(
            x: imageRect.minX + face.rect.minX * imageRect.width,
            y: imageRect.minY + face.rect.minY * imageRect.height,
            width: face.rect.width * imageRect.width,
            height: face.rect.height * imageRect.height
        )
    }

    /// True when any part of the face is outside the frame.
    func faceIsCut(_ face: FaceBox) -> Bool {
        !canvasRect.contains(faceRect(face))
    }

    /// True when the face reaches into the band the movement trims.
    func faceTouchesEdge(_ face: FaceBox) -> Bool {
        !safeRect.contains(faceRect(face))
    }

    /// Distance of the face centre from the frame centre, as a fraction of the
    /// frame's width and height.
    func faceOffset(_ face: FaceBox) -> CGSize {
        let rect = faceRect(face)
        return CGSize(
            width: (rect.midX - canvas.width / 2) / max(canvas.width, 1),
            height: (rect.midY - canvas.height / 2) / max(canvas.height, 1)
        )
    }

    /// True when the whole face could sit inside the safe area at this zoom.
    func faceFitsAtSomePan(_ face: FaceBox) -> Bool {
        let rect = faceRect(face)
        return rect.width <= safeRect.width && rect.height <= safeRect.height
    }

    // MARK: - Crops that answer the recommendations

    /// The bitmap-or-frame box the pan slides the still through.
    private var panBox: CGRect {
        if let rig {
            return CGRect(
                x: (canvas.width - rig.bitmapSize.width) * 0.5,
                y: (canvas.height - rig.bitmapSize.height) * 0.5,
                width: rig.bitmapSize.width,
                height: rig.bitmapSize.height
            )
        }
        return canvasRect
    }

    /// Whether a pan can move the still along each axis: it overflows its
    /// box, or sits inside it with room to spare. At an exact cover-fit there
    /// is nothing to pan, so a drag should scroll the page instead.
    var canPanHorizontally: Bool { abs(panBox.width - imageRect.width) > 0.5 }
    var canPanVertically: Bool { abs(panBox.height - imageRect.height) > 0.5 }
    var canPan: Bool { canPanHorizontally || canPanVertically }

    /// Pan values that put `point` (still coordinates, 0...1) at the frame
    /// centre, clamped to what the overflow allows.
    func pan(centering point: CGPoint) -> (x: Double, y: Double) {
        let box = panBox
        let dw = imageRect.width
        let dh = imageRect.height
        var px = 0.5
        var py = 0.5
        if abs(box.width - dw) > 0.5 {
            px = (canvas.width / 2 - box.minX - point.x * dw) / (box.width - dw)
        }
        if abs(box.height - dh) > 0.5 {
            py = (canvas.height / 2 - box.minY - point.y * dh) / (box.height - dh)
        }
        return (min(1, max(0, px)), min(1, max(0, py)))
    }

    /// The crop that centres the face at the current zoom.
    func cropCentering(on face: FaceBox, keeping current: StillCrop) -> StillCrop {
        let pan = pan(centering: face.center)
        return StillCrop(zoom: current.zoom, panX: pan.x, panY: pan.y)
    }

    /// Smallest zoom, never above cover-fit, that keeps the padded face inside
    /// the safe area, then centred on the face. Without a face this is the
    /// plain cover-fit, centred.
    func cropAutoFitting(_ face: FaceBox?) -> StillCrop {
        guard let face else { return .identity }
        // Zoom scales the still about its own pan point, so the face's size in
        // frame pixels is proportional to zoom.
        let unit = FrameGeometry(canvas: canvas, image: image, crop: nil, motionK: motionK)
        let padded = face.padded
        let faceW = padded.width * unit.imageRect.width
        let faceH = padded.height * unit.imageRect.height
        guard faceW > 0, faceH > 0 else { return .identity }
        let zMax = min(unit.safeRect.width / faceW, unit.safeRect.height / faceH)
        let zoom = min(1.0, max(0.5, zMax))
        let zoomed = FrameGeometry(
            canvas: canvas,
            image: image,
            crop: StillCrop(zoom: zoom, panX: 0.5, panY: 0.5),
            motionK: motionK
        )
        let pan = zoomed.pan(centering: face.center)
        return StillCrop(zoom: zoom, panX: pan.x, panY: pan.y)
    }

    /// Change in pan for a drag of `translation` frame pixels, so the still
    /// follows the finger one-for-one whichever way the overflow runs.
    func panDelta(forDrag translation: CGSize) -> (dx: Double, dy: Double) {
        let box = panBox
        let dw = imageRect.width
        let dh = imageRect.height
        var dx = 0.0
        var dy = 0.0
        if abs(box.width - dw) > 0.5 {
            dx = translation.width / (box.width - dw)
        }
        if abs(box.height - dh) > 0.5 {
            dy = translation.height / (box.height - dh)
        }
        return (dx, dy)
    }
}
