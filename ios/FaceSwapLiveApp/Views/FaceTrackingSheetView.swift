import SwiftUI
import UIKit

/// Stage 4's Face Tracking sheet: source, a jump to the Live Link tab and the
/// active photo's controls.
///
/// Reads only app-side state — nothing here reaches the page, adds a page
/// name, or stores a live reading. Photo values save into per-photo memory.
struct FaceTrackingSheetView: View {
    let viewModel: BrowserViewModel

    @Environment(FaceTrackingController.self) private var tracking
    @Environment(\.dismiss) private var dismiss

    @State private var showFacePoints = false
    @State private var strength: Double = PhotoMemory.defaultStrength
    @State private var loadedPhotoID: ObjectIdentifier?

    var body: some View {
        @Bindable var tracking = tracking

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    modeSection
                    liveLinkRow
                    photoSection
                    hapticsSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Face Tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .fullScreenCover(isPresented: $showFacePoints) { facePoints }
            .onAppear {
                loadPhotoControls()
            }
            .onChange(of: activeImageID) { _, _ in loadPhotoControls() }
            .onChange(of: tracking.neutralBaseline) { _, baseline in
                // A completed calibration belongs to the photo on screen.
                if let baseline, let still = activeStill {
                    viewModel.setLivingCalibration(baseline, for: still.image)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Active photo

    private var activeStill: (image: UIImage, facing: BrowserViewModel.CameraFacing, slot: Int)? {
        viewModel.activeLivingStill
    }

    private var activeImageID: ObjectIdentifier? {
        activeStill.map { ObjectIdentifier($0.image) }
    }

    private func loadPhotoControls() {
        guard let still = activeStill else {
            loadedPhotoID = nil
            return
        }
        let id = ObjectIdentifier(still.image)
        guard id != loadedPhotoID else { return }
        loadedPhotoID = id
        strength = viewModel.livingStrength(for: still.image)
        // A photo that remembers its rest pose puts it straight back.
        if tracking.neutralBaseline == nil,
           let stored = viewModel.livingCalibration(for: still.image) {
            tracking.setNeutralBaseline(stored)
        }
    }

    // MARK: - Mode

    private var modeSection: some View {
        @Bindable var tracking = tracking

        return VStack(alignment: .leading, spacing: 12) {
            Picker("Source", selection: $tracking.mode) {
                ForEach(FaceTrackingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                faceGlyph
                VStack(alignment: .leading, spacing: 2) {
                    Text(tracking.statusLabel)
                        .font(.subheadline.weight(.semibold))
                    Text(tracking.capability.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if tracking.state.isTracking {
                    Text("\(tracking.readingsPerSecond)/s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 44)

            // The front camera being taken is the one moment Second iPhone
            // is the better answer, so it says so.
            if tracking.isCameraNeededElsewhere {
                Label("The front camera is in use — Second iPhone works without it.",
                      systemImage: "exclamationmark.bubble")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }

            if tracking.mode == .thisPhone, !tracking.hasSeenGreenDotNote {
                greenDotNote
            }
        }
        .padding(14)
        .faceGlass(cornerRadius: 14)
    }

    /// Blinks and turns with you while This iPhone is tracking.
    private var faceGlyph: some View {
        let pose = tracking.outputPose
        let blink = max(pose[.eyeBlinkLeft], pose[.eyeBlinkRight])
        return Image(systemName: "faceid")
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(tracking.state.isTracking ? Color.green : Color.secondary)
            .rotationEffect(.degrees(pose.degrees(.headYaw)))
            .scaleEffect(y: CGFloat(1 - blink * 0.4))
            .animation(.linear(duration: 0.08), value: blink)
    }

    private var greenDotNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("iOS shows its green dot while This iPhone mode uses the front camera. That is normal and expected.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tick()
                tracking.markGreenDotNoteSeen()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss the green dot note")
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 10))
    }

    // MARK: - Live Link

    /// One status line; the full connection screen lives in the Live Link tab.
    private var liveLinkRow: some View {
        Button {
            Haptics.tick()
            viewModel.opensLiveLinkTab = true
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tracking.mood.tint)
                    .frame(width: 38, height: 38)
                    .background(tracking.mood.fill, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Live Link")
                        .font(.subheadline.weight(.semibold))
                    Text(tracking.capsuleLine ?? tracking.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(14)
        .faceGlass(cornerRadius: 14)
        .accessibilityHint("Address, port, self-test and setup guide")
    }

    // MARK: - Photo controls

    @ViewBuilder
    private var photoSection: some View {
        // Hidden entirely when the active photo has no mappable face.
        if let still = activeStill, let rig = viewModel.frameCache.rig(for: still.image) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("This photo", icon: "photo.fill")

                strengthSlider(for: still.image)
                calibrateButton
                clearCalibrationButton
                facePointsButton(still, rig: rig)
            }
            .padding(14)
            .faceGlass(cornerRadius: 14)
        }
    }

    private func strengthSlider(for image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Strength")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int((strength * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.cyan)
                    .contentTransition(.numericText())
            }
            Slider(value: $strength, in: 0...1)
                .tint(.cyan)
                .frame(minHeight: 44)
                .onChange(of: strength) { _, value in
                    viewModel.setLivingStrength(value, for: image)
                }
            Text("How far your live face moves the photo. Saved per photo.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var calibrateButton: some View {
        Button {
            if tracking.calibrationProgress != nil {
                tracking.cancelCalibration()
            } else {
                tracking.calibrateNeutral()
            }
        } label: {
            HStack(spacing: 12) {
                ring
                VStack(alignment: .leading, spacing: 1) {
                    Text(tracking.calibrationProgress != nil ? "Hold still…" : "Calibrate Neutral")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.cyan)
                    Text(tracking.calibrationProgress != nil
                         ? "Two seconds, facing the camera"
                         : tracking.neutralBaseline != nil
                         ? "Saved for this photo"
                         : "Your rest face, two seconds")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(10)
            .background(.cyan.opacity(0.12), in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!tracking.state.isTracking && tracking.calibrationProgress == nil)
        .simultaneousGesture(TapGesture().onEnded {
            // The press itself says something happened.
            if tracking.state.isTracking { Haptics.tick() }
        })
    }

    /// The two-second filling ring; full when a baseline is saved.
    private var ring: some View {
        let progress = tracking.calibrationProgress ?? (tracking.neutralBaseline != nil ? 1 : 0)
        return ZStack {
            Circle()
                .stroke(.white.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 26, height: 26)
        .animation(.linear(duration: 0.1), value: progress)
    }

    @ViewBuilder
    private var clearCalibrationButton: some View {
        if tracking.neutralBaseline != nil {
            Button {
                Haptics.tick()
                tracking.clearNeutralBaseline()
                if let still = activeStill {
                    viewModel.setLivingCalibration(nil, for: still.image)
                }
            } label: {
                Label("Clear calibration", systemImage: "arrow.counterclockwise")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(.white.opacity(0.06), in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private func facePointsButton(
        _ still: (image: UIImage, facing: BrowserViewModel.CameraFacing, slot: Int),
        rig: FaceRig
    ) -> some View {
        Button {
            Haptics.tick()
            showFacePoints = true
        } label: {
            Label("Adjust Face Points", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var facePoints: some View {
        if let still = activeStill, let rig = viewModel.frameCache.rig(for: still.image) {
            FacePointsEditorView(
                image: still.image,
                rig: rig,
                faces: viewModel.frameCache.mappedFaces(for: still.image),
                canCopy: viewModel.canCopyFaceCorrections(from: still.facing, slot: still.slot),
                copyTitle: still.facing == .front ? "Copy to Back" : "Copy to Front",
                onSave: { viewModel.saveFaceRig($0, for: still.image) },
                onCopy: { viewModel.copyFaceCorrections($0, from: still.facing, slot: still.slot) }
            )
        }
    }

    // MARK: - Haptics

    private var hapticsSection: some View {
        @Bindable var behavior = viewModel.behavior

        return HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("Haptics")
                    .font(.subheadline.weight(.semibold))
                Text("Found, lost and calibrated only. Silent with Reduce Motion.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $behavior.settings.faceTrackingHaptics)
                .labelsHidden()
                .tint(.green)
        }
        .frame(minHeight: 44)
        .padding(14)
        .faceGlass(cornerRadius: 14)
    }

    // MARK: - Shared bits

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.heavy))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}
