import SwiftUI

/// Device profiles and every diagnostics tool in one tab. Live Link has its
/// own tab, so nothing here repeats connection controls.
struct SettingsView: View {
    let profileManager: DeviceProfileManager
    let browserViewModel: BrowserViewModel

    private static let profilesAnchor = "settings.profiles"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        activeDeviceCard {
                            Haptics.tick()
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                proxy.scrollTo(Self.profilesAnchor, anchor: .top)
                            }
                        }

                        ProfileListSection(profileManager: profileManager)
                            .id(Self.profilesAnchor)

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Diagnostics")
                                .font(.title3.weight(.bold))
                            DiagnosticsView(viewModel: browserViewModel)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Settings")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Active device

    @ViewBuilder
    private func activeDeviceCard(onSwitch: @escaping () -> Void) -> some View {
        if let profile = profileManager.activeProfile {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.cyan)
                        .frame(width: 52, height: 52)
                        .background(
                            LinearGradient(colors: [.cyan.opacity(0.28), .blue.opacity(0.12)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: .rect(cornerRadius: 14)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ACTIVE DEVICE")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(.cyan)
                        Text(profile.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(profile.deviceHardware.modelName) · \(profile.deviceHardware.systemName) \(profile.deviceHardware.systemVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    cameraChip("Front", profile.frontCamera)
                    cameraChip("Back", profile.cameras.first { $0.position == "back" })
                }

                Button(action: onSwitch) {
                    Label("Switch profile", systemImage: "arrow.left.arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(profileManager.profiles.count < 2)
                .opacity(profileManager.profiles.count < 2 ? 0.5 : 1)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.cyan.opacity(0.22), lineWidth: 1)
            }
        }
    }

    private func cameraChip(_ title: String, _ camera: CameraDeviceSpec?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(camera.map { "\($0.maxWidth)×\($0.maxHeight) · \(Int($0.maxFrameRate)) fps" } ?? "—")
                .font(.caption.weight(.medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 10))
    }
}
