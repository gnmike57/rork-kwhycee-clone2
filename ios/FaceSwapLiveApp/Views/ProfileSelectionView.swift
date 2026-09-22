import SwiftUI

struct ProfileSelectionView: View {
    let profileManager: DeviceProfileManager
    let onProfileSelected: () -> Void
    @State private var showCreateProfile: Bool = false
    @State private var profileToDelete: DeviceProfile?
    @State private var showDeleteConfirm: Bool = false
    @State private var expandedProfileID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    
                    if !profileManager.profiles.isEmpty {
                        existingProfilesSection
                    }

                    createNewButton
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Device Profiles")
            .sheet(isPresented: $showCreateProfile) {
                ProfileCreationView(profileManager: profileManager) {
                    onProfileSelected()
                }
            }
            .alert("Delete Profile?", isPresented: $showDeleteConfirm, presenting: profileToDelete) { profile in
                Button("Delete", role: .destructive) {
                    withAnimation(.spring(duration: 0.3)) {
                        profileManager.deleteProfile(profile)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { profile in
                Text("This will permanently remove \"\(profile.name)\" and all its device data.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .cyan.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.cyan)
                    .symbolEffect(.variableColor.iterative, options: .repeating.speed(0.5))
            }
            .padding(.top, 20)

            VStack(spacing: 6) {
                Text("Device Profiles")
                    .font(.title2.bold())

                Text("Scan your device to capture device specs,\nresolution, bitrate, and web fingerprint data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var existingProfilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved Profiles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(profileManager.profiles) { profile in
                profileCard(profile)
            }
        }
    }

    private func profileCard(_ profile: DeviceProfile) -> some View {
        let isActive = profileManager.activeProfileID == profile.id
        let isExpanded = expandedProfileID == profile.id

        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    if isExpanded {
                        expandedProfileID = nil
                    } else {
                        expandedProfileID = profile.id
                    }
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isActive ? Color.cyan.opacity(0.15) : Color(.tertiarySystemFill))
                            .frame(width: 48, height: 48)

                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 20))
                            .foregroundStyle(isActive ? .cyan : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(profile.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if isActive {
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.cyan)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.cyan.opacity(0.15), in: Capsule())
                            }
                        }

                        HStack(spacing: 8) {
                            Label("\(profile.cameras.count)", systemImage: "camera.fill")
                            Text("•")
                            Text(profile.deviceHardware.systemVersion)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(14)
            }

            if isExpanded {
                expandedDetails(profile, isActive: isActive)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private func expandedDetails(_ profile: DeviceProfile, isActive: Bool) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 10) {
                specRow("Device", profile.deviceHardware.modelIdentifier)
                specRow("OS", "\(profile.deviceHardware.systemName) \(profile.deviceHardware.systemVersion)")
                specRow("Screen", profile.deviceHardware.screenNativeBounds)

                if let front = profile.frontCamera {
                    specRow("Front Cam", "\(front.activeWidth)×\(front.activeHeight) @ \(Int(front.activeFrameRate))fps")
                }
                if let back = profile.backCamera {
                    specRow("Back Cam", "\(back.activeWidth)×\(back.activeHeight) @ \(Int(back.activeFrameRate))fps")
                }

                if let front = profile.frontCamera, let bitrate = front.testClipBitrate {
                    specRow("Bitrate", "\(bitrate / 1000)kbps (\(front.testClipCodec ?? "h264"))")
                }

                if !profile.microphones.isEmpty {
                    let mic = profile.microphones[0]
                    specRow("Microphone", "\(mic.label) (\(Int(mic.sampleRate))Hz)")
                }

                if let test = profile.mediaTestResult {
                    specRow("Loom Media", String(format: "%.0f%% match (%d/%d fields)", test.matchPercentage, test.comparisons.filter { $0.matches }.count, test.comparisons.count))
                }

                if profile.webFingerprint.wasMeasured == false {
                    specRow("Fingerprint", "not measured")
                } else {
                    let ua = profile.webFingerprint.userAgent
                    let shown = ua.count > 60 ? String(ua.prefix(60)) + "…" : ua
                    specRow("User Agent", ua.isEmpty ? "not measured" : shown)
                }

                HStack(spacing: 10) {
                    if !isActive {
                        Button {
                            withAnimation(.spring(duration: 0.3)) {
                                profileManager.selectProfile(profile)
                                onProfileSelected()
                            }
                        } label: {
                            Label("Use Profile", systemImage: "checkmark.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.cyan, in: .rect(cornerRadius: 10))
                                .foregroundStyle(.black)
                        }
                    } else {
                        Button {
                            onProfileSelected()
                        } label: {
                            Label("Continue", systemImage: "arrow.right.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.cyan, in: .rect(cornerRadius: 10))
                                .foregroundStyle(.black)
                        }
                    }

                    Button(role: .destructive) {
                        profileToDelete = profile
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .frame(width: 40, height: 38)
                            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
                    }
                }
                .padding(.top, 4)
            }
            .padding(14)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func specRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }

    private var createNewButton: some View {
        Button {
            showCreateProfile = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(.cyan.opacity(0.5))
                        .frame(width: 48, height: 48)

                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.cyan)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Create New Profile")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Scan this device's specs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
        }
    }
}
