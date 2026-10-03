import SwiftUI
import UIKit

/// The dedicated Live Link Face connection hub: everything about linking a
/// second iPhone in one place — live status, the address to stream to, port
/// settings, packet health, a listener self-test and adaptive troubleshooting.
///
/// Presented as a push from Diagnostics and from the Face Tracking sheet, so
/// it never brings its own navigation stack.
struct LiveLinkConnectionView: View {
    @Environment(FaceTrackingController.self) private var tracking

    @State private var portText = ""
    @State private var portError: String?
    @State private var chosenAddressID: String?
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusHero
                if tracking.mode == .secondPhone {
                    controlsCard
                    addressCard
                    selfTestCard
                    healthCard
                    troubleshootingCard
                } else {
                    thisPhoneCard
                }
                setupGuideCard
                settingsRow
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Live Link Face")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if portText.isEmpty { portText = String(tracking.port) }
            settleChosenAddress(tracking.addresses)
        }
        .onChange(of: tracking.addresses) { _, addresses in
            settleChosenAddress(addresses)
        }
        .onDisappear { copyResetTask?.cancel() }
    }

    // MARK: - Status

    private var statusHero: some View {
        let mood = tracking.mood
        return VStack(spacing: 12) {
            Image(systemName: heroGlyph)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(mood.tint)
                .frame(width: 76, height: 76)
                .background(mood.fill, in: .circle)
                .symbolEffect(.pulse, options: .repeating, isActive: tracking.state.isSourceActive)
            VStack(spacing: 3) {
                Text(tracking.statusLabel)
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let sender = tracking.senderName {
                    Text("Streaming from \(sender)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if tracking.state.isTracking {
                    Text("\(tracking.readingsPerSecond) readings / second")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(mood.tint)
                        .contentTransition(.numericText())
                }
            }
            modePicker
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .faceGlass(cornerRadius: 14)
    }

    private var heroGlyph: String {
        switch tracking.state {
        case .off: "antenna.radiowaves.left.and.right.slash"
        case .standby: "hourglass"
        case .starting, .listening, .lost: "antenna.radiowaves.left.and.right"
        case .searching, .live: "faceid"
        case .receiving: "dot.radiowaves.left.and.right"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    @ViewBuilder
    private var modePicker: some View {
        @Bindable var tracking = tracking
        Picker("Source", selection: $tracking.mode) {
            ForEach(FaceTrackingMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 24)
    }

    // MARK: - Connection controls

    private var controlsCard: some View {
        @Bindable var tracking = tracking

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Connection", icon: "power")

            HStack(spacing: 12) {
                Text("Port")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("11111", text: $portText)
                    .keyboardType(.numberPad)
                    .font(.subheadline.monospacedDigit())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
                    .submitLabel(.done)
                    .onSubmit(applyPort)
                if isPortEdited {
                    Button("Apply", action: applyPort)
                        .font(.caption.weight(.bold))
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                }
                Spacer()
                Toggle("Listen", isOn: $tracking.isEnabled)
                    .font(.subheadline.weight(.semibold))
                    .tint(.green)
            }
            .frame(minHeight: 44)

            if let portError {
                Text(portError)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }

            HStack {
                Button {
                    Haptics.tick()
                    portText = String(LiveLinkFacePacket.defaultPort)
                    applyPort()
                } label: {
                    Label("Reset to \(LiveLinkFacePacket.defaultPort)", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
                Spacer()
            }

            if case .unavailable = tracking.state {
                Button {
                    Haptics.tick()
                    tracking.retryConnection()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(.orange.opacity(0.14), in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            Text("Changing the port restarts the listener. It takes effect on Apply, not per keystroke.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .faceGlass(cornerRadius: 14)
    }

    private func applyPort() {
        guard let raw = Int(portText),
              let parsed = FaceTrackingController.sanitizedPort(raw) else {
            portError = "Use a number from 1 to 65535."
            return
        }
        portError = nil
        portText = String(parsed)
        guard parsed != tracking.port else { return }
        tracking.port = parsed
        Haptics.tick()
    }

    private var isPortEdited: Bool {
        guard let raw = Int(portText),
              let parsed = FaceTrackingController.sanitizedPort(raw) else { return false }
        return parsed != tracking.port
    }

    // MARK: - Address

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

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Stream to this address", icon: "number")

            if let address = chosenAddress {
                Text("\(address.address) : \(tracking.port)")
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 2)

                HStack(alignment: .top, spacing: 14) {
                    LinkQRCodeView(message: "\(address.address):\(tracking.port)")
                        .frame(width: 96, height: 96)

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
        }
        .padding(14)
        .faceGlass(cornerRadius: 14)
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

    // MARK: - Self-test

    private var selfTestCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Listener self-test", icon: "checkmark.seal")

            Button {
                Haptics.tick()
                tracking.sendSelfTest()
            } label: {
                Label(selfTestTitle, systemImage: selfTestIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selfTestTint)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(selfTestTint.opacity(0.12), in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(tracking.selfTestState == .sending || !tracking.state.isSourceActive)

            Text("Sends one test packet to this phone's own listener. A pass proves the port is open and packets decode — a silent real sender then points at the sender app or the network, not at this app.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .faceGlass(cornerRadius: 14)
    }

    private var selfTestTitle: String {
        switch tracking.selfTestState {
        case .idle: "Send test packet"
        case .sending: "Sending…"
        case .passed: "Passed — listener works"
        case .failed: "No packet came back — try again"
        }
    }

    private var selfTestIcon: String {
        switch tracking.selfTestState {
        case .idle: "paperplane.fill"
        case .sending: "hourglass"
        case .passed: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var selfTestTint: Color {
        switch tracking.selfTestState {
        case .idle: .cyan
        case .sending: .secondary
        case .passed: .green
        case .failed: .orange
        }
    }

    // MARK: - Packet health

    private var healthCard: some View {
        let health = tracking.packetHealth
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Packet health", icon: "waveform.path.ecg")

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
                Divider().padding(.leading, 96)
                healthRow("Dropped",
                          tracking.packetRejections.total == 0 ? nil : tracking.packetRejections.summary)
            }
            .background(.white.opacity(0.05), in: .rect(cornerRadius: 10))

            senderRow
        }
        .padding(14)
        .faceGlass(cornerRadius: 14)
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

    // MARK: - Troubleshooting

    @ViewBuilder
    private var troubleshootingCard: some View {
        let hints = troubleshootingHints
        if !hints.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Troubleshooting", icon: "questionmark.circle")
                ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: hint.icon)
                            .font(.caption)
                            .foregroundStyle(hint.tint)
                            .frame(width: 18)
                        Text(hint.text)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .faceGlass(cornerRadius: 14)
        }
    }

    private var troubleshootingHints: [(icon: String, tint: Color, text: String)] {
        var hints: [(icon: String, tint: Color, text: String)] = []
        switch tracking.state {
        case .unavailable(.portInUse(let port)):
            hints.append(("exclamationmark.triangle", .orange,
                          "Port \(port) didn't open — something else is using it. Change the port and press Apply, then Try again."))
        case .listening:
            hints.append(("wifi", .cyan,
                          "Both phones must be on the same Wi-Fi — or the sender joins this phone's Personal Hotspot."))
            hints.append(("number", .cyan,
                          "In Live Link Face, add a target with exactly \(chosenAddress?.address ?? "this address") and port \(tracking.port)."))
            hints.append(("person.2", .cyan,
                          "Allow Local Network for both apps: on the sender phone, and here under iPhone Settings."))
            hints.append(("video", .cyan,
                          "Set Capture Mode to ARKit on the sender, then tap LIVE."))
        case .receiving where tracking.isExpressionOnly:
            hints.append(("video", .orange,
                          "The face arrives but the head doesn't turn: turn on Stream Head Rotation in Live Link Face's settings."))
        case .receiving:
            if tracking.packetHealth.lostFraction > 0.05 {
                hints.append(("wifi.exclamationmark", .orange,
                              "About \(Int(tracking.packetHealth.lostFraction * 100))% of packets are being dropped. Keep the phones close, on the same network."))
            }
            if tracking.packetRejections[.wrongSender] > 0 {
                hints.append(("person.2.slash", .orange,
                              "Another phone tried to stream — only the first sender is accepted. Use Switch Sender to change."))
            }
        case .lost:
            hints.append(("arrow.triangle.2.circlepath", .orange,
                          "The stream went quiet. Check the sender is still LIVE and its screen is awake."))
        default:
            break
        }
        return hints
    }

    // MARK: - This iPhone mode

    private var thisPhoneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("This iPhone mode", icon: "faceid")
            Text("The front camera on this phone reads your face directly — nothing to connect. Switch the source above to Second iPhone to link Live Link Face from another phone.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .faceGlass(cornerRadius: 14)
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

    private var setupGuideCard: some View {
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

    // MARK: - Settings & privacy

    private var settingsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Label("Open iPhone Settings", systemImage: "gearshape")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.white.opacity(0.06), in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Text("If packets never arrive, check Local Network for this app and for Live Link Face on the sender phone. This app only listens — nothing is sent.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
