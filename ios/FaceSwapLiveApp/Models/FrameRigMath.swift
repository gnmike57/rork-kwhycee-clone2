import CoreGraphics
import Foundation

/// The injected page's still-feed draw maths, constant for constant.
///
/// Every function here mirrors a function in the page script
/// (`StyleSheetProvider.swift`: `motionCoverZoom`, `makeMotionRig`,
/// `drawMotionFrame`, `exposureAt`, `imageStream`). The preview is only honest
/// while the two agree, so a change on either side must land on both.
nonisolated enum FrameRigMath {

    // MARK: - Constants shared with the page

    /// `motionTravel(k)`: furthest the drift can carry the picture, as a
    /// fraction of the frame dimension.
    static func travel(k: Double) -> Double { 0.0160 * k }

    /// `motionCoverZoom(k)`: the bake zoom that keeps the frame covered through
    /// travel on both sides, the shrink half of the breath and a tilt allowance.
    static func coverZoom(k: Double) -> Double { 1 + (2 * 0.0160 + 0.008 + 0.004) * k }

    /// Band inside the frame edge whose content comes and goes as the picture
    /// moves. Half the cover margin: exactly what the bake was sized for.
    static func edgeInset(k: Double, dimension: Double) -> Double {
        (coverZoom(k: k) - 1) * 0.5 * dimension
    }

    /// `0.05+0.035*k`: the grain overlay's alpha.
    static func grainAlpha(k: Double) -> Double { 0.05 + 0.035 * k }

    // MARK: - Steady placement

    /// Where the page lands the still with motion off.
    ///
    /// `imageStream`: `scale=max(cw/iw,ch/ih)`, then with a crop
    /// `dw*=z; ox=(cw-dw)*px-(cw-dw)*0.5`, drawn at `(cw-dw)/2+ox`, which is
    /// `(cw-dw)*px` — and `(cw-dw)/2` when there is no crop.
    static func steadyRect(canvas: CGSize, image: CGSize, crop: StillCrop?) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = max(canvas.width / image.width, canvas.height / image.height)
        let z = crop?.zoom ?? 1
        let px = crop?.panX ?? 0.5
        let py = crop?.panY ?? 0.5
        let dw = image.width * scale * z
        let dh = image.height * scale * z
        return CGRect(
            x: (canvas.width - dw) * px,
            y: (canvas.height - dh) * py,
            width: dw,
            height: dh
        )
    }

    /// The bake bitmap and where the still sits inside it, with motion on.
    ///
    /// `makeMotionRig`: `bw=round(cw*zoom)`, `sc=max(bw/iw,bh/ih)`,
    /// `dw=iw*sc*z`, `x=(bw-dw)*px` (or centred without a crop). The bitmap is
    /// then blitted centred on the frame, so in frame coordinates the still
    /// sits at `x+(cw-bw)/2`.
    struct Rig: Equatable {
        var bitmapSize: CGSize
        /// The still's rect inside the bitmap.
        var imageInBitmap: CGRect
        /// The still's rect in frame coordinates when the drift is at rest.
        var steadyImageRect: CGRect
    }

    static func rig(canvas: CGSize, image: CGSize, crop: StillCrop?, k: Double) -> Rig {
        let zoom = coverZoom(k: k)
        let bw = max(2, (canvas.width * zoom).rounded())
        let bh = max(2, (canvas.height * zoom).rounded())
        guard image.width > 0, image.height > 0 else {
            return Rig(bitmapSize: CGSize(width: bw, height: bh), imageInBitmap: .zero, steadyImageRect: .zero)
        }
        let sc = max(bw / image.width, bh / image.height)
        let z = crop?.zoom ?? 1
        let px = crop?.panX ?? 0.5
        let py = crop?.panY ?? 0.5
        let dw = image.width * sc * z
        let dh = image.height * sc * z
        let inBitmap = CGRect(x: (bw - dw) * px, y: (bh - dh) * py, width: dw, height: dh)
        let steady = inBitmap.offsetBy(dx: (canvas.width - bw) * 0.5, dy: (canvas.height - bh) * 0.5)
        return Rig(bitmapSize: CGSize(width: bw, height: bh), imageInBitmap: inBitmap, steadyImageRect: steady)
    }

    // MARK: - Per-frame movement

    /// One frame of the hand-held rig, `drawMotionFrame` step for step.
    struct Motion: Equatable {
        /// Drift plus re-grip, frame pixels.
        var dx: Double
        var dy: Double
        /// Even scale applied about the frame centre.
        var breathe: Double
        /// Radians.
        var tilt: Double
    }

    /// `t` is milliseconds since the rig was made.
    ///
    /// The page draws its re-grips from `Math.random()`; the preview replays a
    /// seeded sequence with the same spacing so a redraw never jumps.
    static func motion(t: Double, canvas: CGSize, k: Double, seed: UInt64) -> Motion {
        guard k > 0 else { return Motion(dx: 0, dy: 0, breathe: 1, tilt: 0) }
        let cw = canvas.width
        let ch = canvas.height
        let dx = (sin(t * 0.00037) * 0.6 + sin(t * 0.00091 + 1.7) * 0.3 + sin(t * 0.0021 + 0.4) * 0.1) * cw * 0.010 * k
        let dy = (cos(t * 0.00043 + 0.9) * 0.6 + cos(t * 0.00107 + 2.3) * 0.3 + sin(t * 0.0019 + 1.1) * 0.1) * ch * 0.010 * k
        let breathe = 1 + 0.008 * k * sin(t * 0.00052 + 0.6)
        let tilt = 0.0016 * k * sin(t * 0.00061 + 2.1)

        // `jNext=2400+rnd*3600` at make time, then `jNext=t+2200+rnd*4200` on
        // every re-grip; each one settles over 540 ms with the same smoothstep.
        var generator = SeededGenerator(seed: seed)
        var next = 2400 + generator.unit() * 3600
        var jx = 0.0
        var jy = 0.0
        var jAt = -99_999.0
        while t > next {
            jx = (generator.unit() * 2 - 1) * cw * 0.0060 * k
            jy = (generator.unit() * 2 - 1) * ch * 0.0060 * k
            jAt = next
            next = next + 2200 + generator.unit() * 4200
        }
        let jp = max(0, 1 - (t - jAt) / 540)
        let je = jp * jp * (3 - 2 * jp)

        return Motion(dx: dx + jx * je, dy: dy + jy * je, breathe: breathe, tilt: tilt)
    }

    /// `exposureAt(t,rig)` with the rig fresh (`reAt=0`), so the settle runs
    /// once at the start exactly as it does when a feed opens.
    struct Exposure: Equatable {
        /// Signed brightness amount; the blit's opacity becomes `1-|lift|`.
        var lift: Double
        /// The wipe colour, 0...1 components as the page's `rgb(r|0,g|0,b|0)`.
        var red: Double
        var green: Double
        var blue: Double
    }

    static func exposure(t: Double) -> Exposure {
        let b = sin(t * 0.000181) * 0.6 + sin(t * 0.000437 + 2.1) * 0.4
        let w = sin(t * 0.000149 + 1.3) * 0.6 + sin(t * 0.000353 + 0.7) * 0.4
        var hunt = 0.0
        let p = max(0, t / 900)
        if p < 1 {
            hunt = sin(p * Double.pi * 1.5) * (1 - p) * (1 - p)
        }
        let lift = b * 0.018 + hunt * 0.05
        let warm = w * 0.013
        var r: Double
        let g: Double
        var bl: Double
        if lift >= 0 {
            r = 255; g = 249; bl = 240
        } else {
            r = 9; g = 11; bl = 17
        }
        r = min(255, max(0, r + warm * 90))
        bl = min(255, max(0, bl - warm * 90))
        return Exposure(
            lift: lift,
            red: Double(Int(r)) / 255,
            green: Double(Int(g)) / 255,
            blue: Double(Int(bl)) / 255
        )
    }

    /// Splitmix-style generator so a redraw at the same `t` gives the same frame.
    struct SeededGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678
        }

        mutating func unit() -> Double {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            return Double(z >> 11) / Double(UInt64(1) << 53)
        }
    }
}
