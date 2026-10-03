import SwiftUI
import UIKit

/// The Live Link tab: everything about face tracking and linking a second
/// iPhone in one place — live status, a live meter, the address to stream to,
/// port settings, packet health, a listener self-test, state-aware help and a
/// setup guide that ticks itself off.
///
/// The tab root owns the navigation stack, so this view never brings its own.
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
                if !LivingStills.isAvailable {
                    unavailableCard
                }
                hintCard
                controlsCard
                if tracking.state.isSourceActive {
                    LiveFaceMeterCard()
                }
                if tracking.mode == .secondPhone {
                    addressCard
                    selfTestCard
                    healthCard
                    troubleshootingCard
                    setupGuideCard
                } else {
                    thisPhoneCard
                }
                FaceTrackingEngineerCard()
                settingsRow
            }
            .padding(16)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: tracking.state)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: tracking.mode)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Live Link")
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
        let isLink = tracking.mode == .secondPhone

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(isLink ? "Connection" : "Tracking", icon: "power")

            Toggle(isOn: Binding(
                get: { tracking.isEnabled },
                set: { isOn in
                    Haptics.tick()
                    tracking.isEnabled = isOn
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isLink ? "Listen for Live Link Face" : "Track my face")
                        .font(.subheadline.weight(.semibold))
                    Text(isLink
                         ? "Runs while a still is on a live feed."
                         : "Uses this phone's front camera while a still is on a live feed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.green)
            .disabled(!LivingStills.isAvailable)
            .frame(minHeight: 44)

            if isLink {
                Divider()
                portRow
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

        }
        .padding(14)
        .faceGlass(cornerRadius: 14)
    }

    private var portRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Port")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("11111", text: $portText)
                    .keyboardType(.numberPad)
                    .font(.subheadline.monospacedDigit())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 92)
                    .submitLabel(.done)
                    .onSubmit(applyPort)
                if isPortEdited {
                    Button("Apply", action: applyPort)
                        .font(.caption.weight(.bold))
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                if tracking.port != LiveLinkFacePacket.defaultPort {
                    Button {
                        Haptics.tick()
                        portText = String(LiveLinkFacePacket.defaultPort)
                        applyPort()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.cyan)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset port to \(LiveLinkFacePacket.defaultPort)")
                }
            }
            .frame(minHeight: 44)
            .animation(.snappy, value: isPortEdited)

            if let portError {
                Text(portError)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }

            Text("Changing the port restarts the listener, so it applies on Apply, not per keystroke.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - State-aware hint

    private struct Hint {
        let icon: String
        let tint: Color
        let title: String
        let text: String
    }

    private var hint: Hint? {
        let isLink = tracking.mode == .secondPhone
        switch tracking.state {
        case .off:
            return Hint(icon: "power", tint: .secondary, title: "Tracking is off",
                        text: isLink
                        ? "Switch on Listen below. The listener starts once a still is on a live feed."
                        : "Switch on Track my face below. The camera starts once a still is on a live feed.")
        case .standby:
            if tracking.isCameraNeededElsewhere {
                return Hint(icon: "camera", tint: .orange, title: "The Preview tab has the camera",
                            text: "Leave the Preview tab and tracking picks up again. Second iPhone mode needs no camera here.")
            }
            if !tracking.isForeground {
                return Hint(icon: "moon", tint: .secondary, title: "Paused in the background",
                            text: "Tracking resumes when the app is back on screen.")
            }
            return Hint(icon: "photo.on.rectangle", tint: .orange, title: "Waiting for a still on a live feed",
                        text: "In My Media, put a photo on a slot, then open a site in Browser that uses the camera. Tracking starts on its own.")
        case .starting:
            return Hint(icon: "hourglass", tint: .cyan, title: "Starting", text: "Just a moment.")
        case .listening:
            return Hint(icon: "antenna.radiowaves.left.and.right", tint: .orange, title: "Listening, no packets yet",
                        text: "On the other iPhone, add the address below as a target in Live Link Face and tap LIVE.")
        case .searching:
            return Hint(icon: "faceid", tint: .orange, title: "Looking for your face",
                        text: "Face the front camera in good light.")
        case .receiving where !tracking.hasLiveFace:
            return Hint(icon: "face.dashed", tint: .orange, title: "Packets arriving, no face",
                        text: "Live Link Face is streaming but can't see a face. Point its front camera at a face.")
        case .receiving where tracking.isExpressionOnly:
            return Hint(icon: "rotate.3d", tint: .orange, title: "Head turns are missing",
                        text: "Turn on Stream Head Rotation in Live Link Face's settings.")
        case .live, .receiving:
            return nil
        case .lost:
            return Hint(icon: "arrow.triangle.2.circlepath", tint: .orange, title: "Lost, idling",
                        text: isLink
                        ? "The stream went quiet. Check the sender is still LIVE and its screen is awake."
                        : "Your face left the frame. The still idles until it's back.")
        case .unavailable(.cameraDenied):
            return Hint(icon: "camera.badge.ellipsis", tint: .red, title: "Camera access is off",
                        text: "Allow the camera in iPhone Settings, or use Second iPhone mode.")
        case .unavailable(.notSupported):
            return Hint(icon: "iphone.slash", tint: .red, title: "Not supported here",
                        text: "This iPhone can't track faces itself. Use Second iPhone mode with Live Link Face.")
        case .unavailable(.portInUse(let port)):
            return Hint(icon: "exclamationmark.triangle", tint: .red, title: "Port \(port) is busy",
                        text: "Pick another port below, tap Apply, then Try again.")
        case .unavailable(.failed(let reason)):
            return Hint(icon: "exclamationmark.triangle", tint: .red, title: "Couldn't start", text: reason)
        }
    }

    @ViewBuilder
    private var hintCard: some View {
        if let hint {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: hint.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(hint.tint)
                    .frame(width: 34, height: 34)
                    .background(hint.tint.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(hint.title)
                        .font(.subheadline.weight(.semibold))
                    Text(hint.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .faceGlass(cornerRadius: 14)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var unavailableCard: some View {
        Label("Living stills are turned off in this build, so tracking can't be switched on.",
              systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private struct SetupStep {
        let text: String
        /// True once the app can see this step is done; nil when it can't tell.
        let isDone: Bool?
    }

    private var setupSteps: [SetupStep] {
        let packetsArrived = tracking.packetHealth.packetCount > 0 || tracking.state == .receiving
        let faceArrived = packetsArrived && tracking.hasLiveFace
        return [
            SetupStep(text: "Install Live Link Face (iPhone 12 or newer).", isDone: packetsArrived ? true : nil),
            SetupStep(text: "Join the same Wi-Fi, or this phone's Personal Hotspot.",
                      isDone: tracking.addresses.isEmpty ? false : true),
            SetupStep(text: "Switch on Listen above.", isDone: tracking.isEnabled),
            SetupStep(text: "In Live Link Face, add a target with this address and port.", isDone: packetsArrived ? true : nil),
            SetupStep(text: "Allow Local Network on that phone, set Capture Mode to ARKit and tap LIVE.",
                      isDone: packetsArrived),
            SetupStep(text: "Point its front camera at a face.", isDone: faceArrived),
            SetupStep(text: "Turn on Stream Head Rotation.", isDone: faceArrived ? !tracking.isExpressionOnly : nil),
        ]
    }

    private var setupGuideCard: some View {
        let steps = setupSteps
        let doneCount = steps.filter { $0.isDone == true }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Setup guide", icon: "list.number")
                Spacer()
                Text("\(doneCount) of \(steps.count)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(doneCount == steps.count ? .green : .secondary)
                    .contentTransition(.numericText())
            }
            ProgressView(value: Double(doneCount), total: Double(steps.count))
                .tint(doneCount == steps.count ? .green : .cyan)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: doneCount)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        if step.isDone == true {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.black)
                                .frame(width: 20, height: 20)
                                .background(.green, in: .circle)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(step.isDone == false ? .orange : .cyan)
                                .frame(width: 20, height: 20)
                                .background((step.isDone == false ? Color.orange : Color.cyan).opacity(0.14), in: .circle)
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: step.isDone)
                    Text(step.text)
                        .font(.caption)
                        .foregroundStyle(step.isDone == true ? .secondary : .primary)
                        .strikethrough(step.isDone == true, color: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Live Link Face has no scan-to-add, so the QR only shows what to copy.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .faceGlass(cornerRadius: 14)
        .sensoryFeedback(.success, trigger: doneCount == steps.count) { _, isComplete in isComplete }
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
