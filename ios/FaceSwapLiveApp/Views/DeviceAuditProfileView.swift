import SwiftUI

/// Read-only view of the audit reference sheet, plus a check of whether the
/// currently loaded media lines up with it.
struct DeviceAuditProfileView: View {
    let store: MediaBehaviorStore
    let viewModel: BrowserViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var expandedCameraID: String?

    private var audit: DeviceAuditProfile { store.audit }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                crossCheckSection
                alignmentSection
                camerasSection
                microphoneSection
                browserSection
                probesSection
            }
            .navigationTitle("Device Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(audit.deviceName)
                    .font(.headline)
                Text(audit.capturedNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: store.settings.useAuditProfile ? "checkmark.seal.fill" : "pause.circle.fill")
                        .foregroundStyle(store.settings.useAuditProfile ? .green : .orange)
                    Text(store.settings.useAuditProfile
                         ? "In use — sites see this list"
                         : "Loaded but not in use")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Cross-check

    /// Every pair of values that has to agree, checked against its partner.
    ///
    /// A single wrong value is rarely what gets a device noticed. Two values that
    /// contradict each other is, so this is the check that matters most.
    private var crossCheckSection: some View {
        let results = audit.crossCheck()
        let failures = results.filter { !$0.passed }
        return Section {
            ForEach(results) { result in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: result.passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(result.passed ? Color.green : Color.orange)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name)
                            .font(.subheadline.weight(.medium))
                        Text(result.detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 1)
            }
        } header: {
            Text("Cross-check — \(results.count - failures.count) of \(results.count) agree")
        } footer: {
            Text(failures.isEmpty
                 ? "Every pair agrees with its partner. No single value gets a device noticed — two values that contradict each other do."
                 : "\(failures.count) pair(s) disagree. Each one is a contradiction a site could find.")
        }
    }

    // MARK: - Alignment

    private var alignmentChecks: [(label: String, detail: String, ok: Bool)] {
        var checks: [(String, String, Bool)] = []

        let frontLoaded = viewModel.hasFrontSource
        let backLoaded = viewModel.hasBackSource
        checks.append((
            "Front queue",
            frontLoaded ? "\(viewModel.frontSlotCount) item(s) loaded" : "Empty — front requests fall back",
            frontLoaded
        ))
        checks.append((
            "Back queue",
            backLoaded ? "\(viewModel.backSlotCount) item(s) loaded" : "Empty — back requests fall back",
            backLoaded
        ))

        if let front = viewModel.frontImage {
            let width = Int(front.size.width * front.scale)
            let height = Int(front.size.height * front.scale)
            let limit = audit.limits
            let ok = width <= limit.maxWidth && height <= limit.maxHeight
            checks.append((
                "Front photo size",
                ok ? "\(width)×\(height) — within hardware limits"
                   : "\(width)×\(height) exceeds \(limit.maxWidth)×\(limit.maxHeight), will be pulled back",
                ok
            ))
        }

        if let back = viewModel.backImage {
            let width = Int(back.size.width * back.scale)
            let height = Int(back.size.height * back.scale)
            let expected = audit.primaryBack
            let ok = expected.map { width <= $0.maxWidth && height <= $0.maxHeight } ?? true
            checks.append((
                "Back photo size",
                ok ? "\(width)×\(height) — matches Back Camera"
                   : "\(width)×\(height) is larger than the Back Camera reports",
                ok
            ))
        }

        return checks
    }

    private var alignmentSection: some View {
        Section {
            ForEach(alignmentChecks, id: \.label) { check in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: check.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(check.ok ? Color.green : Color.orange)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.label)
                            .font(.subheadline.weight(.medium))
                        Text(check.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 1)
            }
        } header: {
            Text("Current media vs. hardware")
        } footer: {
            Text("Anything flagged here is pulled back to the nearest genuine value before it is sent.")
        }
    }

    // MARK: - Cameras

    private var camerasSection: some View {
        Section {
            ForEach(audit.cameras.sorted { $0.order < $1.order }) { camera in
                cameraRow(camera)
            }
        } header: {
            Text("Cameras (\(audit.cameras.count)) — reported in this order")
        } footer: {
            Text("Identifiers stay the same on every launch so a site cannot spot a device that changes id.")
        }
    }

    private func cameraRow(_ camera: AuditCamera) -> some View {
        Button {
            withAnimation(.spring(duration: 0.28)) {
                expandedCameraID = expandedCameraID == camera.id ? nil : camera.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: camera.isFront ? "person.crop.square" : "camera.aperture")
                        .font(.system(size: 15))
                        .foregroundStyle(camera.isFront ? Color.cyan : Color.green)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(camera.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("\(camera.resolutionSummary) · up to \(Int(camera.maxFrameRate)) fps · \(camera.facingMode)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expandedCameraID == camera.id ? 180 : 0))
                }

                if expandedCameraID == camera.id {
                    VStack(alignment: .leading, spacing: 5) {
                        detailRow("Identifier", camera.deviceIdPrefix + "…")
                        detailRow("Aspect ratio", String(format: "%.3f", camera.aspectRatio))
                        detailRow("Size range", "\(camera.minWidth)×\(camera.minHeight) – \(camera.maxWidth)×\(camera.maxHeight)")
                        detailRow("Frame rate", "\(Int(camera.minFrameRate)) – \(Int(camera.maxFrameRate)) fps")
                        detailRow("Granted at", "\(camera.grantedWidth)×\(camera.grantedHeight) · \(Int(camera.grantedFrameRate)) fps")
                        detailRow("Measured", "\(Int(camera.measuredFrameRate)) fps")
                        detailRow("Zoom", "\(Int(camera.minZoom))× – \(Int(camera.maxZoom))×")
                        detailRow("White balance", camera.whiteBalanceModes.joined(separator: ", "))
                    }
                    .padding(.leading, 34)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Microphone

    private var microphoneSection: some View {
        Section("Microphone") {
            detailRow("Label", audit.microphone.label)
            detailRow("Identifier", audit.microphone.deviceIdPrefix + "…")
            detailRow("Sample rate", "\(audit.microphone.sampleRate) Hz")
            detailRow("Sample size", "\(audit.microphone.sampleSize)-bit")
            detailRow("Channels", "\(audit.microphone.channelCount)")
            detailRow("Processing", processingSummary)
        }
    }

    private var processingSummary: String {
        var on: [String] = []
        if audit.microphone.echoCancellation { on.append("echo cancel") }
        if audit.microphone.autoGainControl { on.append("auto gain") }
        if audit.microphone.noiseSuppression { on.append("noise suppress") }
        return on.isEmpty ? "none" : on.joined(separator: ", ")
    }

    // MARK: - Browser environment

    private var browserSection: some View {
        Section {
            detailRow("Screen", "\(audit.web.screenWidth)×\(audit.web.screenHeight) pt")
            detailRow("Pixel ratio", String(format: "%.0f×", audit.web.devicePixelRatio))
            detailRow("Colour depth", "\(audit.web.colorDepth)-bit")
            detailRow("Processors", "\(audit.web.hardwareConcurrency)")
            detailRow("Device memory", audit.web.deviceMemory.map { "\($0) GB" } ?? "not reported")
            detailRow("Touch points", "\(audit.web.maxTouchPoints)")
            detailRow("Graphics", audit.web.glRenderer)
            detailRow("GPU vendor", audit.web.glUnmaskedVendor)
            detailRow("Shader lang", audit.web.glShadingLanguageVersion)
            detailRow("Camera perm", audit.web.cameraPermission)
            detailRow("Mic perm", audit.web.microphonePermission)

            VStack(alignment: .leading, spacing: 4) {
                Text("Recording formats")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(audit.web.supportedRecordingTypes, id: \.self) { type in
                    Text(type)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("User agent")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(audit.web.userAgent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        } header: {
            Text("Browser environment")
        }
    }

    // MARK: - Probes

    private var probesSection: some View {
        Section {
            ForEach(audit.probes) { probe in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: probe.wasGranted ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(probe.wasGranted ? Color.green : Color.red)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(probe.name)
                            .font(.subheadline.weight(.medium))
                        Text(probe.resultSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let errorName = probe.errorName {
                            Text("\(errorName): \(probe.errorMessage ?? "")")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.red.opacity(0.85))
                        }
                    }

                    Spacer(minLength: 0)

                    if let ms = probe.elapsedMilliseconds {
                        Text("\(Int(ms)) ms")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 1)
            }
        } header: {
            Text("What the real hardware answered")
        } footer: {
            Text("With capability checking on, only these same requests are refused — everything the phone granted stays granted.")
        }
    }
}
