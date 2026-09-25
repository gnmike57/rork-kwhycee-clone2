import SwiftUI
import UIKit

/// Full-screen Frame Check: the exact preview with room to work, a target
/// frame picker so a still can be prepared before any site asks, every framing
/// action, and the AI Expand review.
struct FrameCheckEditorView: View {
    @Bindable var viewModel: BrowserViewModel
    let request: FrameCheckRequest

    @Environment(\.dismiss) private var dismiss
    @State private var slot: Int
    @State private var target: FrameTarget
    @State private var truePixels: Bool = false
    @State private var expandPhase: ExpandPhase = .idle
    @State private var review: ExpandReview?
    @State private var showCustomSize: Bool = false
    @State private var customWidth: String = ""
    @State private var customHeight: String = ""
    @State private var didAutoExpand: Bool = false
    @State private var showFacePoints: Bool = false

    private enum ExpandPhase: Equatable {
        case idle
        case running
        case failed(String)
    }

    private struct ExpandReview: Identifiable {
        let id = UUID()
        let original: UIImage
        let originalCrop: StillCrop?
        let expanded: UIImage
    }

    init(viewModel: BrowserViewModel, request: FrameCheckRequest) {
        _viewModel = Bindable(wrappedValue: viewModel)
        self.request = request
        _slot = State(initialValue: request.slot)
        // Opens on the frame really in play: what a site is asking for now,
        // else the running feed's own canvas, else this camera's default.
        _target = State(initialValue: request.target ?? viewModel.workingFrameTarget(facing: request.facing))
    }

    private var facing: BrowserViewModel.CameraFacing { request.facing }
    private var tint: Color { facing == .front ? MediaTheme.frontTint : MediaTheme.backTint }
    private var image: UIImage? { viewModel.previewImage(facing: facing, slot: slot) }
    private var isStill: Bool { viewModel.isStill(facing: facing, slot: slot) }
    private var face: FaceBox? { image.flatMap { viewModel.frameFace(for: $0) } }
    private var faceSearched: Bool { image.map { viewModel.frameCache.hasSearchedFace(for: $0) } ?? false }
    private var hasTwoStills: Bool {
        viewModel.isStill(facing: facing, slot: 0) && viewModel.isStill(facing: facing, slot: 1)
    }
    private var mediaTwoTaken: Bool { viewModel.sourceType(facing: facing, slot: 1) != nil }
    private var isExpanding: Bool { expandPhase == .running }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerRow
                    targetRow
                    if isStill {
                        FrameReadinessRow(items: viewModel.frameReadiness(facing: facing, slot: slot))
                    }
                    FrameCheckPanel(
                        viewModel: viewModel,
                        facing: facing,
                        slot: slot,
                        target: target,
                        truePixels: truePixels,
                        onExpandWithAI: { startExpand() }
                    )
                    if LivingStills.isAvailable, let preview = viewModel.livingPreview {
                        LivingStillPreview(image: preview)
                    }
                    toolsRow
                    faceStatus
                    facePointsChip
                    truePixelsRow
                    if case .failed(let text) = expandPhase {
                        failureRow(text)
                    }
                    footnote
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(MediaTheme.canvas)
            .navigationTitle("Frame Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(FrameCheckTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $review) { review in
            FrameExpandReviewView(
                original: review.original,
                originalCrop: review.originalCrop,
                expanded: review.expanded,
                target: target,
                look: viewModel.framePreviewLook,
                placements: mediaTwoTaken ? [.one, .two] : [.two],
                onUse: { chosen in load(review.expanded, into: chosen) },
                onDiscard: { self.review = nil }
            )
        }
        .alert("Custom frame", isPresented: $showCustomSize) {
            TextField("Width", text: $customWidth)
                .keyboardType(.numberPad)
            TextField("Height", text: $customHeight)
                .keyboardType(.numberPad)
            Button("Use") { applyCustomSize() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The exact pixel size a site asks for, for example 1280 by 720.")
        }
        .fullScreenCover(isPresented: $showFacePoints) {
            if let image, let rig = viewModel.frameCache.rig(for: image) {
                FacePointsEditorView(
                    image: image,
                    rig: rig,
                    faces: viewModel.frameCache.mappedFaces(for: image),
                    canCopy: viewModel.canCopyFaceCorrections(from: facing, slot: slot),
                    copyTitle: facing == .front ? "Copy to Back" : "Copy to Front",
                    onSave: { viewModel.saveFaceRig($0, for: image) },
                    onCopy: { viewModel.copyFaceCorrections($0, from: facing, slot: slot) }
                )
            }
        }
        .task {
            Haptics.prepare()
            if let image { viewModel.ensureFaceMap(for: image) }
            if request.autoExpand, !didAutoExpand, isStill {
                didAutoExpand = true
                startExpand()
            }
        }
    }

    // MARK: - Rows

    private var headerRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(facing == .front ? "Front camera" : "Back camera")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if hasTwoStills {
                Picker("Media", selection: $slot) {
                    Text("Media 1").tag(0)
                    Text("Media 2").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            } else {
                Text("Media \(slot + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var targetRow: some View {
        Menu {
            ForEach(viewModel.frameTargetChoices(facing: facing), id: \.self) { choice in
                Button {
                    Haptics.tick()
                    target = choice
                } label: {
                    if choice.width == target.width && choice.height == target.height {
                        Label(choice.menuText, systemImage: "checkmark")
                    } else {
                        Text(choice.menuText)
                    }
                }
            }
            Divider()
            Button {
                customWidth = "\(target.width)"
                customHeight = "\(target.height)"
                showCustomSize = true
            } label: {
                Label("Custom size…", systemImage: "square.dashed")
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FrameCheckTheme.accent)
                    .frame(width: 26, height: 26)
                    .background(FrameCheckTheme.accent.opacity(0.16), in: .rect(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    // Framing is kept per shape, so the shape is named where
                    // the frame is chosen — it is what the framing belongs to.
                    Text("Frame · \(target.shape.title) framing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(target.menuText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(MediaTheme.card, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(MediaTheme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var toolsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                toolChip(.recentre, enabled: isStill)
                toolChip(.centreOnFace, enabled: isStill && face != nil)
                toolChip(.autoFit, enabled: isStill)
                expandChip
                if isStill, isFramed {
                    undoChip
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// True once this frame's shape carries a framing of its own.
    private var isFramed: Bool {
        !viewModel.stillCrop(facing: facing, slot: slot, shape: target.shape).isIdentity
    }

    /// One tap back to the untouched fit for this shape. Every automatic
    /// framing is undone from here, and no other shape is disturbed.
    private var undoChip: some View {
        Button {
            Haptics.firm()
            viewModel.resetStillCrop(facing: facing, slot: slot, shape: target.shape)
        } label: {
            Label("Undo framing", systemImage: "arrow.uturn.backward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private func toolChip(_ action: FrameVerdict.Action, enabled: Bool) -> some View {
        Button {
            Haptics.tick()
            viewModel.performFrameAction(action, facing: facing, slot: slot, target: target)
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.92 : 0.35))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var expandChip: some View {
        Button {
            startExpand()
        } label: {
            HStack(spacing: 6) {
                if isExpanding {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.black)
                } else {
                    Image(systemName: "wand.and.sparkles")
                }
                Text(isExpanding ? "Expanding…" : "Expand with AI")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().fill(FrameCheckTheme.expand.opacity(isStill && !isExpanding ? 0.95 : 0.45)))
        }
        .buttonStyle(.plain)
        .disabled(!isStill || isExpanding)
    }

    @ViewBuilder
    private var faceStatus: some View {
        if isStill {
            Text(faceStatusText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var facePointsChip: some View {
        if LivingStills.isAvailable, isStill, let image {
            if let rig = viewModel.frameCache.rig(for: image) {
                Button {
                    Haptics.tick()
                    showFacePoints = true
                } label: {
                    Label("Face points", systemImage: "face.smiling")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .background(Capsule().fill(FrameCheckTheme.accent.opacity(0.92)))
                .accessibilityIdentifier("face-points")
                .disabled(rig.handleIndex.isEmpty)
            } else if viewModel.frameCache.hasSearchedMap(for: image) {
                Text(viewModel.frameCache.mapNote(for: image) ?? FaceMapNote.couldntMap)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                Text("Looking for a face…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var faceStatusText: String {
        if face != nil {
            return "Face found. Centre on face and Auto-fit work from it."
        }
        if faceSearched {
            return "No face found in this photo. Centring uses the frame centre."
        }
        return "Looking for a face…"
    }

    private var truePixelsRow: some View {
        Toggle(isOn: $truePixels) {
            VStack(alignment: .leading, spacing: 2) {
                Text("True pixels")
                    .font(.subheadline.weight(.medium))
                Text("One frame pixel per screen pixel, so a small photo looks as soft as the site will see it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(FrameCheckTheme.accent)
        .padding(12)
        .background(MediaTheme.card, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(MediaTheme.stroke, lineWidth: 1)
        )
    }

    private func failureRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(FrameCheckTheme.warning)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Retry") { startExpand() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FrameCheckTheme.accent)
        }
        .padding(12)
        .background(FrameCheckTheme.warning.opacity(0.10), in: .rect(cornerRadius: 12))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var footnote: some View {
        Text("Framing is kept separately for each frame shape, so a photo set up for widescreen stays right when a 4:3 size is asked for. Live feed only — file uploads, the photo chooser and the native camera are never changed. Expand with AI uses Rork AI and only runs when you tap it.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - AI Expand

    private func startExpand() {
        guard isStill, !isExpanding else { return }
        guard let source = viewModel.frameExpandSource(facing: facing, slot: slot) else { return }
        let shownNow = image ?? source
        let originalCrop = viewModel.effectiveCrop(facing: facing, slot: slot)
        let facing = facing
        let slot = slot
        let target = target
        expandPhase = .running
        Haptics.firm()
        Task {
            do {
                let expanded = try await viewModel.expandFrame(facing: facing, slot: slot, target: target)
                expandPhase = .idle
                review = ExpandReview(original: shownNow, originalCrop: originalCrop, expanded: expanded)
                Haptics.success()
            } catch {
                expandPhase = .failed(error.localizedDescription)
                Haptics.warning()
            }
        }
    }

    private func load(_ expanded: UIImage, into destination: BrowserViewModel.SequenceSlot) {
        review = nil
        viewModel.useExpandedFrame(expanded, facing: facing, slot: destination)
        viewModel.setQueueIndex(destination.rawValue, facing: facing)
        slot = destination.rawValue
        Haptics.success()
    }

    private func applyCustomSize() {
        guard let width = Int(customWidth.trimmingCharacters(in: .whitespaces)),
              let height = Int(customHeight.trimmingCharacters(in: .whitespaces)),
              (16...8192).contains(width), (16...8192).contains(height) else {
            Haptics.warning()
            return
        }
        target = .custom(width: width, height: height)
        Haptics.tick()
    }
}
