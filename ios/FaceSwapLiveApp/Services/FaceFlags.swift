import CoreGraphics
import Foundation

/// Glasses and teeth, read from the upright picture. Teeth are only flagged
/// when the photo already shows them.
nonisolated enum FaceFlags {
    /// A dark frame that crosses the nose, with a top bar and a bottom bar.
    /// Brows and lashes do not cross the bridge, so they do not count.
    static func wearsGlasses(luma: [UInt8], width: Int, height: Int, eyeBand: CGRect) -> Bool {
        guard width > 8, height > 8, luma.count >= width * height else { return false }
        let band = pixelRect(eyeBand, width: width, height: height)
        let minX = Int(band.minX)
        let maxX = min(width, Int(band.maxX))
        let minY = max(1, Int(band.minY))
        let maxY = min(height - 1, Int(band.maxY))
        let span = maxX - minX
        guard span > 8, maxY > minY else { return false }

        let midStart = minX + span / 3
        let midEnd = minX + (span * 2) / 3
        var frameRows: [Int] = []
        for y in minY..<maxY {
            var darkEdges = 0
            var midDark = 0
            var midCount = 0
            for x in minX..<maxX {
                let here = Int(luma[y * width + x])
                let above = Int(luma[(y - 1) * width + x])
                let below = y + 1 < height ? Int(luma[(y + 1) * width + x]) : here
                if here < 90 && (above - here > 28 || below - here > 28) {
                    darkEdges += 1
                }
                if x >= midStart && x < midEnd {
                    midCount += 1
                    if here < 90 { midDark += 1 }
                }
            }
            let wide = Double(darkEdges) / Double(span) > 0.45
            let bridge = midCount > 0 && Double(midDark) / Double(midCount) > 0.4
            if wide && bridge { frameRows.append(y) }
        }
        guard let first = frameRows.first, let last = frameRows.last else { return false }
        return last - first >= 2
    }

    /// Bright pixels inside an already-open mouth. A dark open mouth is not teeth.
    static func teethVisible(
        luma: [UInt8],
        width: Int,
        height: Int,
        mouth: CGRect,
        opening: CGFloat,
        faceHeight: CGFloat
    ) -> Bool {
        guard faceHeight > 0, opening / faceHeight > 0.035 else { return false }
        guard width > 4, height > 4, luma.count >= width * height else { return false }
        let rect = pixelRect(mouth, width: width, height: height)
        guard rect.width > 2, rect.height > 2 else { return false }
        var total = 0
        var bright = 0
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let value = Int(luma[y * width + x])
                total += value
                if value > 190 { bright += 1 }
                count += 1
            }
        }
        guard count > 0 else { return false }
        return Double(total) / Double(count) > 150 && Double(bright) / Double(count) > 0.22
    }

    static func luma(of pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
        guard pixels.count >= width * height * 4 else { return [] }
        var grey = [UInt8](repeating: 0, count: width * height)
        for index in 0..<width * height {
            let offset = index * 4
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            grey[index] = UInt8((red * 3 + green * 6 + blue) / 10)
        }
        return grey
    }

    private static func pixelRect(_ unit: CGRect, width: Int, height: Int) -> CGRect {
        let rect = CGRect(
            x: unit.minX * CGFloat(width),
            y: unit.minY * CGFloat(height),
            width: unit.width * CGFloat(width),
            height: unit.height * CGFloat(height)
        ).integral
        return rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }
}
