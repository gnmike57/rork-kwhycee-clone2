import SwiftUI

/// Smile, blink, jaw, brow and head-turn readings that move with the face, so
/// the link can be checked without opening a site.
struct LiveFaceMeterCard: View {
    @Environment(FaceTrackingController.self) private var tracking

    private struct Meter: Identifiable {
        let id: String
        let value: Double
    }

    var body: some View {
        let pose = tracking.outputPose
        let meters: [Meter] = [
            Meter(id: "Smile", value: Double(max(pose[.mouthSmileLeft], pose[.mouthSmileRight]))),
            Meter(id: "Blink", value: Double(max(pose[.eyeBlinkLeft], pose[.eyeBlinkRight]))),
            Meter(id: "Jaw", value: Double(pose[.jawOpen])),
            Meter(id: "Brows", value: Double(pose[.browInnerUp])),
        ]

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live face", systemImage: "face.smiling")
                    .font(.caption.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(tracking.outputCaption)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tracking.state.isTracking ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((tracking.state.isTracking ? Color.green : Color.white).opacity(0.12), in: .capsule)
            }

            ForEach(meters) { meter in
                HStack(spacing: 10) {
                    Text(meter.id)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: [.cyan, .green], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, proxy.size.width * CGFloat(min(max(meter.value, 0), 1))))
                        }
                    }
                    .frame(height: 8)
                    .animation(.linear(duration: 1 / FaceTrackingController.drawRate), value: meter.value)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(meter.id)
                .accessibilityValue("\(Int(meter.value * 100)) percent")
            }

            HStack(spacing: 8) {
                angle("Turn", pose.degrees(.headYaw))
                angle("Nod", pose.degrees(.headPitch))
                angle("Tilt", pose.degrees(.headRoll))
            }
            .padding(.top, 2)
        }
        .padding(14)
        .faceGlass(cornerRadius: 14)
    }

    private func angle(_ label: String, _ degrees: Double) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%+.0f°", degrees))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText(value: degrees))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 10))
    }
}
