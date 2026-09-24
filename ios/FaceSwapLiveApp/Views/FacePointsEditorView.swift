import SwiftUI
import UIKit

/// Full-screen face points. Handles steer the mesh; swipe down discards.
struct FacePointsEditorView: View {
    let image: UIImage
    let faces: [MappedFace]
    let canCopy: Bool
    let copyTitle: String
    let onSave: (FaceRig) -> Void
    let onCopy: (FaceRig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rig: FaceRig
    @State private var undo: [[FaceHandle: FaceNudge]] = []
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var drag: HandleDrag?
    @State private var comparing = false
    @State private var canvasSize: CGSize = .zero

    private struct HandleDrag {
        var handle: FaceHandle
        var start: FaceNudge
    }

    init(
        image: UIImage,
        rig: FaceRig,
        faces: [MappedFace],
        canCopy: Bool,
        copyTitle: String,
        onSave: @escaping (FaceRig) -> Void,
        onCopy: @escaping (FaceRig) -> Void
    ) {
        self.image = image
        self.faces = faces
        self.canCopy = canCopy
        self.copyTitle = copyTitle
        self.onSave = onSave
        self.onCopy = onCopy
        _rig = State(initialValue: rig)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let frame = fittedFrame(in: proxy.size)
                ZStack {
                    Color.black.ignoresSafeArea()
                    photo(in: frame)
                        .scaleEffect(zoom)
                        .offset(pan)
                        .gesture(magnify)
                        .simultaneousGesture(backgroundPan)
                    if let drag, let point = screenPoint(drag.handle, in: frame) {
                        loupe(at: point)
                            .position(x: min(proxy.size.width - 70, point.x + 78), y: max(70, point.y - 78))
                    }
                }
                .overlay(alignment: .bottom) { toolbar }
                .overlay(alignment: .top) { captions }
                .onAppear { canvasSize = proxy.size }
                .onChange(of: proxy.size) { _, size in canvasSize = size }
            }
            .navigationTitle("Face points")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { reset() }
                        .disabled(rig.nudges.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Haptics.success()
                        onSave(rig)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { Haptics.prepare() }
    }

    private var captions: some View {
        VStack(spacing: 6) {
            if faces.count > 1 {
                Menu {
                    ForEach(faces) { face in
                        Button("Face \(face.id + 1)") { switchFace(face) }
                    }
                } label: {
                    Text("Switch face")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            if rig.wearsGlasses {
                Text("Glasses stay put")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if rig.teethVisible {
                Text("Teeth will show")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private func photo(in frame: CGRect) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: frame.width, height: frame.height)
            meshOutline(in: frame)
            ForEach(FaceHandle.allCases, id: \.self) { handle in
                if let point = unitPoint(handle) {
                    handleDot(handle, at: CGPoint(x: frame.minX + point.x * frame.width, y: frame.minY + point.y * frame.height))
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    private func meshOutline(in frame: CGRect) -> some View {
        let vertices = comparing ? rig.vertices : rig.deformedVertices()
        return Canvas { context, _ in
            for triangle in rig.triangles where triangle.layer != .edge {
                guard vertices.indices.contains(triangle.a),
                      vertices.indices.contains(triangle.b),
                      vertices.indices.contains(triangle.c) else { continue }
                var path = Path()
                path.move(to: placed(vertices[triangle.a], in: frame))
                path.addLine(to: placed(vertices[triangle.b], in: frame))
                path.addLine(to: placed(vertices[triangle.c], in: frame))
                path.closeSubpath()
                context.stroke(path, with: .color(.white.opacity(0.16)), lineWidth: 0.6)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .allowsHitTesting(false)
    }

    private func handleDot(_ handle: FaceHandle, at point: CGPoint) -> some View {
        let amber = rig.isLowConfidence(handle)
        let named = drag?.handle == handle
        return Circle()
            .fill(amber ? Color(red: 1, green: 0.72, blue: 0.28) : Color.white)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 1))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(point)
            .overlay(alignment: .center) {
                if named {
                    Text(handle.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .offset(y: -28)
                }
            }
            .gesture(dragGesture(handle))
            .accessibilityLabel(handle.title)
            .accessibilityValue(positionText(handle))
    }

    private func loupe(at point: CGPoint) -> some View {
        let frame = fittedFrame(in: canvasSize)
        return Image(uiImage: image)
            .resizable()
            .frame(width: frame.width * 2, height: frame.height * 2)
            .offset(x: 55 - (point.x - frame.minX) * 2, y: 55 - (point.y - frame.minY) * 2)
            .frame(width: 110, height: 110)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            tool("arrow.uturn.backward", "Undo", enabled: !undo.isEmpty) { undoLast() }
            tool("arrow.left.and.right", "Symmetry", enabled: true) { symmetrize() }
            tool("square.on.square", copyTitle, enabled: canCopy) { onCopy(rig) }
            HoldTool(title: "Compare", systemImage: "eye") { comparing = $0 }
            tool("arrow.counterclockwise", "Reset", enabled: !rig.nudges.isEmpty) { reset() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 18)
    }

    private func tool(_ symbol: String, _ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .disabled(!enabled)
        .accessibilityLabel(title)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(4, max(1, value.magnification))
            }
    }

    private var backgroundPan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard drag == nil else { return }
                pan = value.translation
            }
            .onEnded { value in
                let downward = value.translation.height > 160
                    && value.translation.height > abs(value.translation.width) * 1.6
                guard drag == nil, zoom < 1.15, downward else { return }
                pan = .zero
                dismiss()
            }
    }

    private func dragGesture(_ handle: FaceHandle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag?.handle != handle {
                    undo.append(rig.nudges)
                    drag = HandleDrag(handle: handle, start: rig.nudges[handle] ?? .zero)
                    Haptics.tick()
                }
                guard let start = drag?.start else { return }
                let frame = fittedFrame(in: canvasSize)
                let dx = value.translation.width / max(1, frame.width * zoom)
                let dy = value.translation.height / max(1, frame.height * zoom)
                rig.nudges[handle] = FaceNudge(dx: start.dx + Double(dx), dy: start.dy + Double(dy))
            }
            .onEnded { _ in
                drag = nil
                Haptics.snap()
            }
    }

    private func undoLast() {
        guard let previous = undo.popLast() else { return }
        rig.nudges = previous
        Haptics.tick()
    }

    private func symmetrize() {
        undo.append(rig.nudges)
        rig = rig.snappedToSymmetry()
        Haptics.tick()
    }

    private func reset() {
        undo.append(rig.nudges)
        rig.nudges = [:]
        Haptics.tick()
    }

    private func switchFace(_ face: MappedFace) {
        guard let rebuilt = FaceRigBuilder.build(from: face, wearsGlasses: rig.wearsGlasses, teethVisible: rig.teethVisible) else { return }
        undo.append(rig.nudges)
        rig = rebuilt
    }

    private func unitPoint(_ handle: FaceHandle) -> CGPoint? {
        comparing ? rig.detectedPosition(of: handle) : rig.position(of: handle)
    }

    private func screenPoint(_ handle: FaceHandle, in frame: CGRect) -> CGPoint? {
        guard let point = unitPoint(handle) else { return nil }
        return CGPoint(x: frame.minX + point.x * frame.width, y: frame.minY + point.y * frame.height)
    }

    private func placed(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: point.x * frame.width, y: point.y * frame.height)
    }

    private func fittedFrame(in size: CGSize) -> CGRect {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func positionText(_ handle: FaceHandle) -> String {
        guard let point = rig.position(of: handle) else { return "Not placed" }
        return "\(Int((point.x * 100).rounded())) percent across, \(Int((point.y * 100).rounded())) percent down"
    }
}

private struct HoldTool: View {
    let title: String
    let systemImage: String
    let onHold: (Bool) -> Void

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onHold(true) }
                    .onEnded { _ in onHold(false) }
            )
            .accessibilityLabel(title)
    }
}
