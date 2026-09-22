import SwiftUI
import MetalKit
import CoreImage

/// Shows the latest camera frame, drawn straight to the GPU, and reports how
/// the interface is turned so the frames can be stood upright to match.
struct MediaPreviewView: UIViewRepresentable {
    let frame: CIImage?
    var onRotationChange: ((DisplayRotation) -> Void)? = nil

    func makeUIView(context: Context) -> MetalPreviewView {
        let view = MetalPreviewView()
        view.onRotationChange = onRotationChange
        return view
    }

    func updateUIView(_ uiView: MetalPreviewView, context: Context) {
        uiView.onRotationChange = onRotationChange
        uiView.display(frame)
    }
}

/// An `MTKView` that aspect-fills one `CIImage` per redraw.
///
/// Frames arrive as `CIImage`s wrapping the camera's own pixel buffers, so
/// nothing is copied through CPU memory on the way to the screen: Core Image
/// renders into the drawable and the frame is done with.
final class MetalPreviewView: MTKView {
    var onRotationChange: ((DisplayRotation) -> Void)?

    private let commandQueue: MTLCommandQueue?
    private let context: CIContext?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private var image: CIImage?
    private var lastRotation: DisplayRotation?

    init() {
        let device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        context = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
        super.init(frame: .zero, device: device)
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = true
        colorPixelFormat = .bgra8Unorm
        isOpaque = true
        backgroundColor = .black
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func display(_ frame: CIImage?) {
        image = frame
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportRotation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportRotation()
    }

    /// The window scene is the one source of truth for how the UI is turned;
    /// device orientation can disagree with it (face up, rotation lock).
    private func reportRotation() {
        guard let interface = window?.windowScene?.interfaceOrientation else { return }
        let rotation = DisplayRotation(interface)
        guard rotation != lastRotation else { return }
        lastRotation = rotation
        onRotationChange?(rotation)
    }

    override func draw(_ rect: CGRect) {
        guard let image, let context, let commandQueue,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let target = CGRect(origin: .zero, size: drawableSize)
        let source = image.extent
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else { return }

        // Aspect-fill, centred: the same framing the old preview layer used.
        let scale = max(target.width / source.width, target.height / source.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let placed = scaled.transformed(by: CGAffineTransform(
            translationX: target.midX - scaled.extent.midX,
            y: target.midY - scaled.extent.midY
        ))

        context.render(
            placed,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: target,
            colorSpace: colorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
