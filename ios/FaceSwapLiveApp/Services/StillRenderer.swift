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
        var uniforms = warpUniforms(drive: drive, rig: rig)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&pixelSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&dark, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WarpUniforms>.stride, index: 1)
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
            drawSmile(canvas, drive: drive, rig: rig, width: width, height: height)
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

    /// Anchors and intensities for the fragment-side smile shading and the
    /// rPPG tint. Anchors are the photo's rest positions in UV space; without
    /// them the expression shading stays off and only the pulse rides.
    private static func warpUniforms(drive: StillDrive, rig: FaceRig) -> WarpUniforms {
        var uniforms = WarpUniforms(
            smile: 0, squint: 0, pulse: drive.pulse,
            scale: Float(max(0.16, rig.rest.faceHeight)),
            mouthLeft: .zero, mouthRight: .zero, upperLip: .zero,
            leftEyeOuter: .zero, rightEyeOuter: .zero
        )
        let needed: [FaceHandle] = [.mouthLeft, .mouthRight, .upperLip, .leftEyeOuter, .rightEyeOuter]
        guard needed.allSatisfy({ rig.handleIndex[$0] != nil }) else { return uniforms }
        func uv(_ handle: FaceHandle) -> SIMD2<Float> {
            guard let index = rig.handleIndex[handle], rig.vertices.indices.contains(index) else { return .zero }
            return SIMD2(Float(rig.vertices[index].x), Float(rig.vertices[index].y))
        }
        uniforms.smile = drive.smile
        uniforms.squint = drive.squint
        uniforms.mouthLeft = uv(.mouthLeft)
        uniforms.mouthRight = uv(.mouthRight)
        uniforms.upperLip = uv(.upperLip)
        uniforms.leftEyeOuter = uv(.leftEyeOuter)
        uniforms.rightEyeOuter = uv(.rightEyeOuter)
        return uniforms
    }

    /// CPU-fallback smile shading: soft fold and crow's-feet strokes plus a
    /// flush gradient. The Metal path does this procedurally per pixel.
    private static func drawSmile(_ canvas: CGContext, drive: StillDrive, rig: FaceRig, width: Int, height: Int) {
        guard drive.smile > 0.05,
              let mouthL = point(.mouthLeft, drive: drive, rig: rig, width: width, height: height),
              let mouthR = point(.mouthRight, drive: drive, rig: rig, width: width, height: height),
              let lip = point(.upperLip, drive: drive, rig: rig, width: width, height: height),
              let eyeL = point(.leftEyeOuter, drive: drive, rig: rig, width: width, height: height),
              let eyeR = point(.rightEyeOuter, drive: drive, rig: rig, width: width, height: height)
        else { return }
        let scale = CGFloat(max(0.16, rig.rest.faceHeight)) * CGFloat(height)
        canvas.saveGState()
        canvas.setLineCap(.round)

        // Nasolabial folds: from beside the nose, curving past the mouth corner.
        for (corner, side) in [(mouthL, CGFloat(-1)), (mouthR, CGFloat(1))] {
            let wing = CGPoint(x: lip.x + (corner.x - lip.x) * 0.5, y: lip.y - scale * 0.05)
            let end = CGPoint(x: corner.x + side * scale * 0.03, y: corner.y + scale * 0.02)
            let mid = CGPoint(x: (wing.x + end.x) / 2 + side * scale * 0.015, y: (wing.y + end.y) / 2)
            let path = CGMutablePath()
            path.move(to: wing)
            path.addQuadCurve(to: end, control: mid)
            canvas.addPath(path)
            canvas.setStrokeColor(UIColor(white: 0.08, alpha: CGFloat(drive.smile) * 0.15).cgColor)
            canvas.setLineWidth(max(1, scale * 0.02))
            canvas.setShadow(offset: .zero, blur: scale * 0.02)
            canvas.strokePath()
        }

        // Crow's feet radiating from the outer eye corners.
        let squint = CGFloat(min(1, drive.squint + drive.smile * 0.45))
        if squint > 0.05 {
            for (eye, side) in [(eyeL, CGFloat(-1)), (eyeR, CGFloat(1))] {
                for spread in stride(from: CGFloat(-0.4), through: 0.4, by: 0.4) {
                    canvas.move(to: eye)
                    canvas.addLine(to: CGPoint(
                        x: eye.x + side * cos(spread) * scale * 0.055,
                        y: eye.y + (sin(spread) * 0.6 + 0.35) * scale * 0.055
                    ))
                }
                canvas.setStrokeColor(UIColor(white: 0.1, alpha: squint * 0.12).cgColor)
                canvas.setLineWidth(max(0.8, scale * 0.008))
                canvas.setShadow(offset: .zero, blur: scale * 0.012)
                canvas.strokePath()
            }
        }

        // The flush a smile brings to the cheeks.
        for (corner, eye) in [(mouthL, eyeL), (mouthR, eyeR)] {
            let cheek = CGPoint(x: (corner.x + eye.x) / 2, y: (corner.y + eye.y) / 2)
            let colors = [
                UIColor(red: 0.92, green: 0.38, blue: 0.32, alpha: CGFloat(drive.smile) * 0.05).cgColor,
                UIColor(red: 0.92, green: 0.38, blue: 0.32, alpha: 0).cgColor
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                canvas.drawRadialGradient(
                    gradient,
                    startCenter: cheek, startRadius: 0,
                    endCenter: cheek, endRadius: scale * 0.16,
                    options: []
                )
            }
        }
        canvas.restoreGState()
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
            shade: 0, mouth: 0, skin: 0
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
                    mouth: 0,
                    skin: 1
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
                mouth: mouth,
                skin: 1
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
        mouth: Float,
        skin: Float
    ) -> [WarpVertex] {
        func vertex(_ value: (Float, Float, Float, Float)) -> WarpVertex {
            WarpVertex(position: SIMD2(value.0, value.1), uv: SIMD2(value.2, value.3), shade: shade, mouth: mouth, skin: skin)
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

/// Matches the Metal vertex. 28 bytes, no padding.
struct WarpVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
    var shade: Float
    var mouth: Float
    /// 1 on the face mesh, 0 on the background — masks the shading effects.
    var skin: Float
}

/// Mirrors WarpUniforms in StillWarp.metal — keep both in step.
struct WarpUniforms {
    var smile: Float
    var squint: Float
    var pulse: Float
    var scale: Float
    var mouthLeft: SIMD2<Float>
    var mouthRight: SIMD2<Float>
    var upperLip: SIMD2<Float>
    var leftEyeOuter: SIMD2<Float>
    var rightEyeOuter: SIMD2<Float>
}
