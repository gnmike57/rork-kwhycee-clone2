import SwiftUI
import UIKit

/// Stage 4's Face Tracking sheet: source, the second-iPhone link, the
/// active photo's controls and the Live Link Face setup guide.
///
/// Reads only app-side state — nothing here reaches the page, adds a page
/// name, or stores a live reading. Photo values save into per-photo memory.
struct FaceTrackingSheetView: View {
    let viewModel: BrowserViewModel

    @Environment(FaceTrackingController.self) private var tracking
    @Environment(\.dismiss) private var dismiss

    @State private var chosenAddressID: String?
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var showFacePoints = false
    @State private var strength: Double = PhotoMemory.defaultStrength
    @State private var loadedPhotoID: ObjectIdentifier?

    private let privacyNote = "This app only listens for face data. It may ask to find devices on the local network so those packets can arrive. Nothing is sent. If no packets arrive, on the other iPhone open Settings → Privacy & Security → Local Network and allow Live Link Face."

    var body: some View {
        @Bindable var tracking = tracking

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    modeSection
                    if tracking.mode == .secondPhone {
                        linkSection
                        setupGuide
                    }
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
            .onAppear { loadPhotoControls() }
            .onChange(of: activeImageID) { _, _ in loadPhotoControls() }
            .onChange(of: tracking.addresses) { _, addresses in
                settleChosenAddress(addresses)
            }
            .onChange(of: tracking.neutralBaseline) { _, baseline in
                // A completed calibration belongs to the photo on screen.
                if let baseline, let still = activeStill {
                    viewModel.setLivingCalibration(baseline, for: still.image)
                }
            }
            .onDisappear { copyResetTask?.cancel() }
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

    // MARK: - Second iPhone

    private var chosenAddress: LocalAddress? {
        if let chosenAddressID, let match = tracking.addresses.first(where: { $0.id == chosenAddressID }) {
            return match
        }
        return tracking.addresses.first
    }

    private func settleChosenAddress(_ addresses: [LocalAddress]) {
        guard !addresses.isEmpty else { return }
        if let chosenAddressID, addresses.contains(where: { $0.id == chosenAddressID }) { return }
        chosenAddressID = addresses.first?.id
    }

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Second iPhone", icon: "iphone.radiowaves.left.and.right")

            if let address = chosenAddress {
                Text("\(address.address) : \(tracking.port)")
                    .font(.system(size: 21, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 2)

                HStack(alignment: .top, spacing: 14) {
                    QRCodeView(message: "\(address.address):\(tracking.port)")
                        .frame(width: 92, height: 92)

                    VStack(alignment: .leading, spacing: 8) {
                        if tracking.addresses.count > 1 {
                            networkPicker
                        }
                        copyButton(address)
                        Text("\(address.label) · \(address.interface)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("Not on Wi-Fi or a hotspot. An IPv6-only network isn't supported.",
                      systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            listenRow
            packetHealthRows
            senderRow

            Text(privacyNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .faceGlass(cornerRadius: 14)
        .onAppear { settleChosenAddress(tracking.addresses) }
    }

    @ViewBuilder
    private var networkPicker: some View {
        Picker("Network", selection: $chosenAddressID) {
            ForEach(tracking.addresses) { address in
                Text(address.label).tag(Optional(address.id))
            }
        }
        .font(.caption)
    }

    private func copyButton(_ address: LocalAddress) -> some View {
        Button {
            Haptics.tick()
            UIPasteboard.general.string = "\(address.address):\(tracking.port)"
            copied = true
            copyResetTask?.cancel()
            copyResetTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy address",
                  systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var listenRow: some View {
        @Bindable var tracking = tracking

        return HStack(spacing: 12) {
            Text("Port")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("Port", value: $tracking.port, format: .number)
                .keyboardType(.numberPad)
                .font(.subheadline.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .frame(width: 88)

            Spacer()

            Toggle("Listen", isOn: $tracking.isEnabled)
                .font(.subheadline.weight(.semibold))
                .tint(.green)
        }
        .frame(minHeight: 44)
    }

    /// Live packet health: rate, estimated loss, jitter and last-seen age.
    @ViewBuilder
    private var packetHealthRows: some View {
        let health = tracking.packetHealth
        VStack(spacing: 0) {
            healthRow("Rate",
                      health.packetCount == 0 ? nil : String(format: "%.0f/s", health.ratePerSecond))
            Divider().padding(.leading, 96)
            healthRow("Loss",
                      health.packetCount == 0 ? nil : String(format: "%.0f%%", health.lostFraction * 100))
            Divider().padding(.leading, 96)
            healthRow("Jitter",
                      health.packetCount == 0 ? nil : "\(Int(health.jitterSeconds * 1000)) ms")
            Divider().padding(.leading, 96)
            healthRow("Last seen",
                      health.packetCount == 0 ? nil : String(format: "%.1f s ago", health.secondsSinceLastPacket))
        }
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 10))
    }

    private func healthRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value ?? "—")
                .font(.caption.monospacedDigit())
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
    }

    @ViewBuilder
    private var senderRow: some View {
        if let sender = tracking.senderName {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Locked to \(sender)")
                        .font(.caption.weight(.semibold))
                    Text("Only this phone can drive the still")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Switch Sender") {
                    Haptics.tick()
                    tracking.releaseSenderLock()
                }
                .font(.caption.weight(.semibold))
            }
            .frame(minHeight: 44)
        }
    }

    // MARK: - Setup guide

    private let setupSteps: [String] = [
        "Install Live Link Face (iPhone 12 or newer).",
        "Join the same Wi-Fi — or this phone's Personal Hotspot.",
        "Add a target with this address and port.",
        "Set Capture Mode: ARKit.",
        "Turn on Stream Head Rotation.",
        "Allow Local Network on that phone.",
        "Tap LIVE.",
    ]

    private var setupGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Setup guide", icon: "list.number")

            ForEach(Array(setupSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.cyan)
                        .frame(width: 20, height: 20)
                        .background(.cyan.opacity(0.14), in: .circle)
                    Text(step)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Live Link Face has no scan-to-add, so the QR only shows what to copy.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .faceGlass(cornerRadius: 14)
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

/// A QR code of the address to copy. Live Link Face has no scan-to-add, so
/// this is a readable version of the string, not a way to add a target.
private struct QRCodeView: View {
    let message: String

    var body: some View {
        if let image = Self.image(for: message) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(6)
                .background(.white, in: .rect(cornerRadius: 8))
        } else {
            Color.white.opacity(0.06)
                .aspectRatio(1, contentMode: .fit)
        }
    }

    nonisolated static func image(for message: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
