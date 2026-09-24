import CoreGraphics
import CryptoKit
import Foundation
import UIKit

/// How a still is recognised. File names are never used.
///
/// An exact pixel match is tried first. Then a 256-bit perceptual hash and a
/// 64-bit difference hash, both from a 32×32 grey copy. A match on either
/// signature counts, but only when the picture is the same size — a crop,
/// expansion or different picture is a new photo.
nonisolated struct PhotoFingerprint: Codable, Sendable, Equatable {
    var exact: Data
    var perceptual: Data
    var difference: UInt64
    var luma: [UInt8]
    var width: Int
    var height: Int

    static let perceptualDistance = 18
    static let differenceDistance = 8
    static let lumaDistance = 18.0

    func matches(_ other: PhotoFingerprint) -> Bool {
        if exact == other.exact { return true }
        guard Self.sameFrame(self, other) else { return false }
        let perceptualClose = Self.hamming(perceptual, other.perceptual) <= Self.perceptualDistance
        let differenceClose = (difference ^ other.difference).nonzeroBitCount <= Self.differenceDistance
        let lumaClose = Self.meanAbsoluteDifference(luma, other.luma) <= Self.lumaDistance
        return (perceptualClose || differenceClose) && lumaClose
    }

    static func make(from image: UIImage) -> PhotoFingerprint? {
        guard let pixels = rgbaPixels(of: image) else { return nil }
        return make(pixels: pixels.bytes, width: pixels.width, height: pixels.height)
    }

    static func make(pixels: [UInt8], width: Int, height: Int) -> PhotoFingerprint? {
        guard width > 1, height > 1, pixels.count >= width * height * 4 else { return nil }
        let digest = SHA256.hash(data: Data(pixels))
        let grey = lumaGrid(pixels: pixels, width: width, height: height, side: 32)
        return PhotoFingerprint(
            exact: Data(digest),
            perceptual: perceptualHash(grey),
            difference: differenceHash(grey),
            luma: grey,
            width: width,
            height: height
        )
    }

    private static func sameFrame(_ a: PhotoFingerprint, _ b: PhotoFingerprint) -> Bool {
        let widthGap = abs(a.width - b.width)
        let heightGap = abs(a.height - b.height)
        let widthLimit = max(2, a.width / 25)
        let heightLimit = max(2, a.height / 25)
        guard widthGap <= widthLimit, heightGap <= heightLimit else { return false }
        let aspectA = Double(a.width) / Double(max(1, a.height))
        let aspectB = Double(b.width) / Double(max(1, b.height))
        return abs(aspectA - aspectB) / max(aspectA, aspectB) < 0.04
    }

    static func hamming(_ a: Data, _ b: Data) -> Int {
        zip(a, b).reduce(0) { $0 + ($1.0 ^ $1.1).nonzeroBitCount }
    }

    static func meanAbsoluteDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 255 }
        let total = zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(a.count)
    }

    /// Draws the still upright so orientation metadata cannot change the hash.
    static func rgbaPixels(of image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let width = max(1, Int((size.width * image.scale).rounded()))
        let height = max(1, Int((size.height * image.scale).rounded()))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let wrote = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            UIGraphicsPopContext()
            return true
        }
        guard wrote else { return nil }
        return (bytes, width, height)
    }

    private static func lumaGrid(pixels: [UInt8], width: Int, height: Int, side: Int) -> [UInt8] {
        var grid = [UInt8](repeating: 0, count: side * side)
        for y in 0..<side {
            for x in 0..<side {
                let sx = min(width - 1, x * width / side)
                let sy = min(height - 1, y * height / side)
                let offset = (sy * width + sx) * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                grid[y * side + x] = UInt8((red * 3 + green * 6 + blue) / 10)
            }
        }
        return grid
    }

    /// 16×16 low-frequency DCT coefficients, each bit set when above the median.
    private static func perceptualHash(_ grey: [UInt8]) -> Data {
        let n = 32
        let values = grey.map { Double($0) }
        var freq = [Double](repeating: 0, count: 16 * 16)
        let step = Double.pi / Double(n)
        for v in 0..<16 {
            for u in 0..<16 {
                var sum = 0.0
                for y in 0..<n {
                    let cy = cos((Double(y) + 0.5) * Double(v) * step)
                    for x in 0..<n {
                        sum += values[y * n + x] * cos((Double(x) + 0.5) * Double(u) * step) * cy
                    }
                }
                freq[v * 16 + u] = sum
            }
        }
        _ = values
        let sorted = freq.sorted()
        let median = sorted[sorted.count / 2]
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in freq.indices where freq[index] > median {
            bytes[index / 8] |= 1 << (7 - (index % 8))
        }
        return Data(bytes)
    }

    /// 64-bit difference hash sampled from the 32×32 grey copy.
    private static func differenceHash(_ grey: [UInt8]) -> UInt64 {
        let columns = [0, 4, 8, 12, 16, 20, 24, 28, 31]
        let rows = [2, 6, 10, 14, 18, 22, 26, 30]
        var bits: UInt64 = 0
        var shift = 0
        for row in rows {
            for column in 0..<8 {
                let left = grey[row * 32 + columns[column]]
                let right = grey[row * 32 + columns[column + 1]]
                if left > right { bits |= 1 << shift }
                shift += 1
            }
        }
        return bits
    }
}
