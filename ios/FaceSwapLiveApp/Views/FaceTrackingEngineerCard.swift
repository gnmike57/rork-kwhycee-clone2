import SwiftUI

/// The engineer's view of face tracking, collapsed by default: raw gate and
/// output state plus neutral calibration. Lives at the bottom of the Live Link
/// tab; the connection controls above it are the only place the port changes.
struct FaceTrackingEngineerCard: View {
    @Environment(FaceTrackingController.self) private var tracking
    @AppStorage("liveLink.engineerExpanded") private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Haptics.tick()
                withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Label("Engineer details", systemImage: "wrench.and.screwdriver")
                        .font(.caption.weight(.heavy))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(minHeight: 32)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 6) {
                    row("State", tracking.statusLabel)
                    row("This iPhone", tracking.capability.title)
                    row("Readings/s", "\(tracking.readingsPerSecond)")
                    row("Output", tracking.outputCaption)
                    row("Baseline", tracking.neutralBaseline == nil ? "Not calibrated" : "Calibrated")
                    row("Gate", gateSummary)
                    if tracking.mode == .secondPhone {
                        row("Head", tracking.isExpressionOnly ? "Expression only" : "Included when sent")
                        row("Rejected", tracking.packetRejections.summary)
                    }
                }
                .transition(.opacity)

                calibrationControls
            }
        }
        .padding(14)
        .faceGlass(cornerRadius: 14)
    }

    private var gateSummary: String {
        var parts: [String] = []
        parts.append(tracking.isEnabled ? "switched on" : "switched off")
        parts.append(tracking.stillOnActiveFeed ? "still on feed" : "no still on feed")
        if !tracking.isForeground { parts.append("background") }
        if tracking.isCameraNeededElsewhere { parts.append("Preview tab") }
        return parts.joined(separator: " · ")
    }

    private var calibrationControls: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tick()
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
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.cyan.opacity(0.15), in: .rect(cornerRadius: 10))
                .foregroundStyle(.cyan)
            }
            .buttonStyle(.plain)
            .disabled(!tracking.state.isTracking && tracking.calibrationProgress == nil)

            if tracking.neutralBaseline != nil {
                Button {
                    Haptics.tick()
                    tracking.clearNeutralBaseline()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear calibration")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.caption)
            Spacer()
        }
    }
}
