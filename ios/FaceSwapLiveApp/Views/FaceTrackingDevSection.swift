import SwiftUI

/// Stage 1's verification surface in Diagnostics: pick a source, switch
/// tracking on, and watch the meter move. The real Face Tracking sheet lands
/// in Stage 4; this stays as the engineer's view.
struct FaceTrackingDevSection: View {
    @Environment(FaceTrackingController.self) private var tracking

    private static let meterChannels: [FaceChannel] = [
        .jawOpen, .eyeBlinkLeft, .eyeBlinkRight, .browInnerUp, .mouthSmileLeft, .mouthSmileRight,
    ]

    var body: some View {
        @Bindable var tracking = tracking

        VStack(alignment: .leading, spacing: 12) {
            Picker("Source", selection: $tracking.mode) {
                ForEach(FaceTrackingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle(isOn: $tracking.isEnabled) {
                Text("Track my face")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.green)

            statusRows

            if tracking.mode == .secondPhone {
                listenerRows
            }

            if tracking.state.isSourceActive {
                meter
                calibrationControls
            }
        }
    }

    // MARK: - Status

    private var statusRows: some View {
        VStack(spacing: 6) {
            row("State", tracking.state.label, tint: stateTint)
            row("Readings/s", "\(tracking.readingsPerSecond)")
            row("Output", tracking.isIdling ? "Idle" : "Tracked")
            row("Baseline", tracking.neutralBaseline == nil ? "Not calibrated" : "Calibrated")
            row("Gate", gateSummary)
        }
    }

    private var gateSummary: String {
        var parts: [String] = []
        parts.append(tracking.stillOnActiveFeed ? "still on feed" : "no still on feed")
        if !tracking.isForeground { parts.append("background") }
        if tracking.isCameraNeededElsewhere { parts.append("Preview tab") }
        return parts.joined(separator: " · ")
    }

    private var stateTint: Color {
        switch tracking.state {
        case .live, .receiving: .green
        case .searching, .listening, .starting: .orange
        case .lost, .unavailable: .red
        case .off, .standby: .secondary
        }
    }

    // MARK: - Second iPhone

    private var listenerRows: some View {
        @Bindable var tracking = tracking

        return VStack(alignment: .leading, spacing: 8) {
            if tracking.addresses.isEmpty {
                row("Address", "Not on Wi-Fi or a hotspot")
            } else {
                ForEach(tracking.addresses) { address in
                    row(address.label, "\(address.address) : \(tracking.port)")
                }
            }
            if let sender = tracking.senderName {
                row("Sender", sender)
            }
            HStack {
                Text("Port")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                TextField("Port", value: $tracking.port, format: .number)
                    .keyboardType(.numberPad)
                    .font(.caption.monospacedDigit())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Spacer()
            }
        }
    }

    // MARK: - Meter

    private var meter: some View {
        let pose = tracking.outputPose
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.meterChannels, id: \.self) { channel in
                HStack(spacing: 8) {
                    Text(channel.liveLinkName)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule()
                                .fill(.cyan)
                                .frame(width: proxy.size.width * CGFloat(min(max(pose[channel], 0), 1)))
                        }
                    }
                    .frame(height: 8)
                    Text(String(format: "%.2f", pose[channel]))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            HStack(spacing: 14) {
                angle("Yaw", pose.degrees(.headYaw))
                angle("Pitch", pose.degrees(.headPitch))
                angle("Roll", pose.degrees(.headRoll))
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    private func angle(_ label: String, _ degrees: Double) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%+.1f°", degrees))
                .font(.caption2.monospacedDigit())
        }
    }

    // MARK: - Calibration

    private var calibrationControls: some View {
        HStack(spacing: 10) {
            Button {
                if tracking.calibrationProgress == nil {
                    tracking.calibrateNeutral()
                } else {
                    tracking.cancelCalibration()
                }
            } label: {
                Label(
                    tracking.calibrationProgress == nil
                        ? "Calibrate Neutral"
                        : String(format: "Hold still… %d%%", Int((tracking.calibrationProgress ?? 0) * 100)),
                    systemImage: "face.dashed"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.cyan.opacity(0.15), in: .rect(cornerRadius: 10))
                .foregroundStyle(.cyan)
            }
            .disabled(!tracking.state.isTracking && tracking.calibrationProgress == nil)

            if tracking.neutralBaseline != nil {
                Button {
                    tracking.clearNeutralBaseline()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 40)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Clear calibration")
            }
        }
    }

    // MARK: - Row

    private func row(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(tint)
            Spacer()
        }
    }
}
