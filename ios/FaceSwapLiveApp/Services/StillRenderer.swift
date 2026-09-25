import CoreGraphics
import Foundation
import Metal
import MetalKit
import UIKit

/// One native renderer for the living still.
///
/// The page and Frame Check both read this picture. Strength 0 leaves the
/// photo untouched. Detail drops if a frame runs past the budget; the page
/// clock does not.
enum StillRenderer {
    private static var longSideCap = StillRetarget.maxLongSide
    private static var pipeline: (any MTLRenderPipelineState)?
    private static var device: (any MTLDevice)?
    private static var queue: (any MTLCommandQueue)?
    private static var didTryMetal = false

    /// The warped picture, or the photo itself when the drive would not move it.
    static func picture(image: UIImage, drive: StillDrive, rig: FaceRig) -> UIImage? {
        let rest = rig.deformedVertices()
        let size = StillRetarget.workingSize(for: image.size, longSide: longSideCap)
        if StillRetarget.isIdentity(drive, rest: rest) {
            return scaled(image, to: size)
        }
        let started = Date()
        let rendered = metalPicture(image: image, drive: drive, rig: rig, size: size)
            ?? cpuPicture(image: image, drive: drive, rig: rig, size: size)
        let milliseconds = Date().timeIntervalSince(started) * 1000
        if milliseconds > StillRetarget.maxFrameMilliseconds {
            longSideCap = max(256, Int(Double(longSideCap) * 0.75))
        }
        return rendered
    }

    /// JPEG for the page. Face numbers are not in it — only pixels.
    static func jpeg(image: UIImage, drive: StillDrive, rig: FaceRig, quality: CGFloat = 0.72) -> Data? {
        picture(image: image, drive: drive, rig: rig)?.jpegData(compressionQuality: quality)
    }

    // MARK: - Metal

    private static func metalPicture(image: UIImage, drive: StillDrive, rig: FaceRig, size: CGSize) -> UIImage? {
        guard prepareMetal(),
              let device,
              let queue,
              let pipeline,
              let cgImage = image.cgImage
        else { return nil }
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.topLeft
        ]
        guard let texture = try? MTKTextureLoader(device: device).newTexture(cgImage: cgImage, options: options) else {
            return nil
        }

        let width = Int(size.width)
        let height = Int(size.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor),
              let buffer = queue.makeCommandBuffer()
        else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        let vertices = meshVertices(drive: drive, rig: rig, size: size)
        guard !vertices.isEmpty,
              let vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: MemoryLayout<WarpVertex>.stride * vertices.count,
                options: .storageModeShared
              )
        else {
            encoder.endEncoding()
            return nil
        }
        var pixelSize = SIMD2<Float>(Float(width), Float(height))
        var dark = bakedDark(image: cgImage, rig: rig)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&pixelSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&dark, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        return picture(from: target)
    }

    private static func prepareMetal() -> Bool {
        if didTryMetal { return pipeline != nil }
        didTryMetal = true
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "stillWarpVertex"),
              let fragment = library.makeFunction(name: "stillWarpFragment")
        else { return false }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return false }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        return true
    }

    // MARK: - CPU fallback

    private static func cpuPicture(image: UIImage, drive: StillDrive, rig: FaceRig, size: CGSize) -> UIImage? {
        guard let base = scaled(image, to: size), let cgImage = base.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            base.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            let canvas = context.cgContext
            drawMouth(canvas, image: cgImage, drive: drive, rig: rig, width: width, height: height)
            drawLids(canvas, drive: drive, rig: rig, width: width, height: height)
        }
        return rendered
    }

    private static func drawMouth(_ canvas: CGContext, image: CGImage, drive: StillDrive, rig: FaceRig, width: Int, height: Int) {
        guard drive.jawOpen > 0.02,
              let left = point(.mouthLeft, drive: drive, rig: rig, width: width, height: height),
              let right = point(.mouthRight, drive: drive, rig: rig, width: width, height: height),
              let upper = point(.upperLip, drive: drive, rig: rig, width: width, height: height),
              let lower = point(.lowerLip, drive: drive, rig: rig, width: width, height: height)
        else { return }
        canvas.saveGState()
        canvas.move(to: left)
        canvas.addLine(to: upper)
        canvas.addLine(to: right)
        canvas.addLine(to: lower)
        canvas.closePath()
        canvas.clip()
        if drive.showTeeth {
            canvas.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            canvas.setFillColor(UIColor(white: 0, alpha: 0.28).cgColor)
            canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
        } else {
            let dark = bakedDark(image: image, rig: rig)
            canvas.setFillColor(UIColor(red: CGFloat(dark.x), green: CGFloat(dark.y), blue: CGFloat(dark.z), alpha: 1).cgColor)
            canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        canvas.restoreGState()
    }

    private static func drawLids(_ canvas: CGContext, drive: StillDrive, rig: FaceRig, width: Int, height: Int) {
        shade(canvas, lid: drive.leftLid, center: .leftEyeCenter, outer: .leftEyeOuter, inner: .leftEyeInner, drive: drive, rig: rig, width: width, height: height)
        shade(canvas, lid: drive.rightLid, center: .rightEyeCenter, outer: .rightEyeOuter, inner: .rightEyeInner, drive: drive, rig: rig, width: width, height: height)
    }

    private static func shade(
        _ canvas: CGContext,
        lid: Float,
        center: FaceHandle,
        outer: FaceHandle,
        inner: FaceHandle,
        drive: StillDrive,
        rig: FaceRig,
        width: Int,
        height: Int
    ) {
        guard lid > 0.04,
              let eye = point(center, drive: drive, rig: rig, width: width, height: height),
              let left = point(outer, drive: drive, rig: rig, width: width, height: height),
              let right = point(inner, drive: drive, rig: rig, width: width, height: height)
        else { return }
        let span = max(8, abs(left.x - right.x))
        let rect = CGRect(x: eye.x - span * 0.55, y: eye.y - span * 0.42, width: span * 1.1, height: span * 0.5 * CGFloat(lid))
        canvas.setFillColor(UIColor(white: 0.05, alpha: CGFloat(lid) * 0.72).cgColor)
        canvas.fillEllipse(in: rect)
    }

    // MARK: - Mesh

    private static func meshVertices(drive: StillDrive, rig: FaceRig, size: CGSize) -> [WarpVertex] {
        let rest = rig.deformedVertices()
        guard drive.vertices.count == rest.count, rest.count > 2 else { return [] }
        let width = Float(size.width)
        let height = Float(size.height)
        var vertices: [WarpVertex] = []
        vertices.append(contentsOf: quad(
            (0, 0, 0, 0), (width, 0, 1, 0), (0, height, 0, 1), (width, height, 1, 1),
            shade: 0, mouth: 0
        ))
        if drive.jawOpen > 0.02,
           let mouth = mouthQuad(drive: drive, rig: rig, rest: rest, width: width, height: height) {
            vertices.append(contentsOf: mouth)
        }
        let shades = lidShade(drive: drive, rig: rig, rest: rest)
        for triangle in rig.triangles {
            let indices = [triangle.a, triangle.b, triangle.c]
            guard indices.allSatisfy({ rest.indices.contains($0) && drive.vertices.indices.contains($0) }) else { continue }
            for index in indices {
                let position = drive.vertices[index]
                let sample = rest[index]
                vertices.append(WarpVertex(
                    position: SIMD2(Float(position.x) * width, Float(position.y) * height),
                    uv: SIMD2(Float(sample.x), Float(sample.y)),
                    shade: shades[index],
                    mouth: 0
                ))
            }
        }
        return vertices
    }

    private static func mouthQuad(drive: StillDrive, rig: FaceRig, rest: [CGPoint], width: Float, height: Float) -> [WarpVertex]? {
        let handles: [FaceHandle] = [.mouthLeft, .upperLip, .mouthRight, .lowerLip]
        let indices = handles.compactMap { rig.handleIndex[$0] }
        guard indices.count == 4, indices.allSatisfy({ drive.vertices.indices.contains($0) && rest.indices.contains($0) }) else { return nil }
        let mouth: Float = drive.showTeeth ? 0.28 : 1
        func vertex(_ index: Int) -> WarpVertex {
            let position = drive.vertices[index]
            let sample = rest[index]
            return WarpVertex(
                position: SIMD2(Float(position.x) * width, Float(position.y) * height),
                uv: SIMD2(Float(sample.x), Float(sample.y)),
                shade: 0,
                mouth: mouth
            )
        }
        let left = vertex(indices[0])
        let upper = vertex(indices[1])
        let right = vertex(indices[2])
        let lower = vertex(indices[3])
        return [left, upper, right, left, right, lower]
    }

    private static func lidShade(drive: StillDrive, rig: FaceRig, rest: [CGPoint]) -> [Float] {
        var shades = Array(repeating: Float(0), count: rest.count)
        paint(&shades, lid: drive.leftLid, center: .leftEyeCenter, rig: rig, rest: rest)
        paint(&shades, lid: drive.rightLid, center: .rightEyeCenter, rig: rig, rest: rest)
        return shades
    }

    private static func paint(_ shades: inout [Float], lid: Float, center: FaceHandle, rig: FaceRig, rest: [CGPoint]) {
        guard lid > 0.04, let eye = rig.position(of: center) else { return }
        let reach = CGFloat(max(0.02, rig.rest.faceHeight * 0.08))
        for index in rest.indices where rest[index].y <= eye.y && hypot(rest[index].x - eye.x, rest[index].y - eye.y) < reach {
            shades[index] = max(shades[index], lid)
        }
    }

    private static func quad(
        _ a: (Float, Float, Float, Float),
        _ b: (Float, Float, Float, Float),
        _ c: (Float, Float, Float, Float),
        _ d: (Float, Float, Float, Float),
        shade: Float,
        mouth: Float
    ) -> [WarpVertex] {
        func vertex(_ value: (Float, Float, Float, Float)) -> WarpVertex {
            WarpVertex(position: SIMD2(value.0, value.1), uv: SIMD2(value.2, value.3), shade: shade, mouth: mouth)
        }
        return [vertex(a), vertex(b), vertex(c), vertex(b), vertex(d), vertex(c)]
    }

    private static func point(_ handle: FaceHandle, drive: StillDrive, rig: FaceRig, width: Int, height: Int) -> CGPoint? {
        guard let index = rig.handleIndex[handle], drive.vertices.indices.contains(index) else { return nil }
        let vertex = drive.vertices[index]
        return CGPoint(x: vertex.x * CGFloat(width), y: vertex.y * CGFloat(height))
    }

    /// A dark mouth, unless the photo already shows teeth.
    static func bakedDark(image: CGImage, rig: FaceRig) -> SIMD3<Float> {
        let fallback = SIMD3<Float>(0.09, 0.05, 0.04)
        guard let mouth = rig.position(of: .upperLip) ?? rig.position(of: .lowerLip) else { return fallback }
        let x = min(image.width - 1, max(0, Int(mouth.x * CGFloat(image.width))))
        let y = min(image.height - 1, max(0, Int(mouth.y * CGFloat(image.height))))
        guard let pixel = pixel(image, x: x, y: y) else { return fallback }
        let luma = pixel.x * 0.3 + pixel.y * 0.6 + pixel.z * 0.1
        if rig.teethVisible { return pixel }
        return luma > 0.62 ? fallback : pixel
    }

    private static func pixel(_ image: CGImage, x: Int, y: Int) -> SIMD3<Float>? {
        var data = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &data,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        return SIMD3(Float(data[0]) / 255, Float(data[1]) / 255, Float(data[2]) / 255)
    }

    private static func scaled(_ image: UIImage, to size: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func picture(from texture: any MTLTexture) -> UIImage? {
        let width = texture.width
        let height = texture.height
        let row = width * 4
        var bytes = [UInt8](repeating: 0, count: row * height)
        texture.getBytes(&bytes, bytesPerRow: row, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: row,
                space: space,
                bitmapInfo: info,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Matches the Metal vertex. 24 bytes, no padding.
struct WarpVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
    var shade: Float
    var mouth: Float
}
