import Foundation

/// Holds every switch added by the device-matched media work, plus the pill's
/// parked position and the per-site prompt memory.
///
/// Nothing here reaches into the existing media delivery path. Callers read the
/// values and decide for themselves whether to act on them.
@Observable
@MainActor
final class MediaBehaviorStore {
    var settings: MediaBehaviorSettings {
        didSet {
            guard settings != oldValue else { return }
            persistSettings()
        }
    }

    var pillPlacement: PillPlacement {
        didSet {
            guard pillPlacement != oldValue else { return }
            persistPlacement()
        }
    }

    /// Hosts the user chose to stop asking about.
    private(set) var silencedHosts: Set<String> = []

    /// Hosts where the user asked for the picture to be held still.
    private(set) var frozenHosts: Set<String> = []

    /// Hosts that have already been granted a camera.
    ///
    /// A real phone remembers this per site: once granted, a reload shows the
    /// full named device list straight away, and a site that has never asked
    /// still sees the short nameless one.
    private(set) var grantedHosts: Set<String> = []

    /// Hosts that have been granted the microphone. Sound is a separate grant
    /// from the camera — a video-only request never opens it, and revoking one
    /// must not silently carry the other.
    private(set) var micGrantedHosts: Set<String> = []

    /// The measured reference sheet, with the user's version choice applied.
    ///
    /// Reading it through here means the user agent and the photo stamp are
    /// always built from the same version and cannot drift apart.
    var audit: DeviceAuditProfile {
        DeviceAuditProfile.iPhone.withSafariVersion(settings.safariVersionOverride)
    }

    private let settingsKey = "media_behavior_settings_v1"
    private let placementKey = "media_pill_placement_v1"
    private let silencedKey = "media_prompt_silenced_hosts_v1"
    private let frozenKey = "media_motion_frozen_hosts_v1"
    private let grantedKey = "media_camera_granted_hosts_v1"
    private let micGrantedKey = "media_mic_granted_hosts_v1"
    private let identityKey = "media_identity_secret_v1"

    /// Stable for the life of this install.
    ///
    /// The page combines it with the site's own name, so every site gets its own
    /// device identifiers, the same site sees the same ones forever, and no two
    /// sites ever see a value in common.
    private(set) var identitySecret: String = ""

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(MediaBehaviorSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }

        if let data = defaults.data(forKey: placementKey),
           let decoded = try? JSONDecoder().decode(PillPlacement.self, from: data) {
            pillPlacement = decoded
        } else {
            pillPlacement = .default
        }

        if let hosts = defaults.stringArray(forKey: silencedKey) {
            silencedHosts = Set(hosts)
        }

        if let hosts = defaults.stringArray(forKey: frozenKey) {
            frozenHosts = Set(hosts)
        }

        if let hosts = defaults.stringArray(forKey: grantedKey) {
            grantedHosts = Set(hosts)
        }

        if let hosts = defaults.stringArray(forKey: micGrantedKey) {
            micGrantedHosts = Set(hosts)
        }

        if let secret = defaults.string(forKey: identityKey), secret.count >= 32 {
            identitySecret = secret
        } else {
            let generated = (0..<16)
                .map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }
                .joined()
            identitySecret = generated
            defaults.set(generated, forKey: identityKey)
        }
    }

    // MARK: - Camera permission memory

    /// True when this site has already been granted a camera.
    func isCameraGranted(host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        return grantedHosts.contains(host)
    }

    func markCameraGranted(host: String?) {
        guard let host, !host.isEmpty else { return }
        guard !grantedHosts.contains(host) else { return }
        grantedHosts.insert(host)
        persistGranted()
    }

    /// True when this site has already been granted the microphone.
    func isMicrophoneGranted(host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        return micGrantedHosts.contains(host)
    }

    func markMicrophoneGranted(host: String?) {
        guard let host, !host.isEmpty else { return }
        guard !micGrantedHosts.contains(host) else { return }
        micGrantedHosts.insert(host)
        persistGranted()
    }

    func clearGrantedHosts() {
        grantedHosts.removeAll()
        micGrantedHosts.removeAll()
        persistGranted()
    }

    // MARK: - Freeze memory

    /// True when this site's feed should hold the picture perfectly still.
    func isFrozen(host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        return frozenHosts.contains(host)
    }

    func setFrozen(_ frozen: Bool, host: String?) {
        guard let host, !host.isEmpty else { return }
        if frozen {
            frozenHosts.insert(host)
        } else {
            frozenHosts.remove(host)
        }
        persistFrozen()
    }

    func clearFrozenHosts() {
        frozenHosts.removeAll()
        persistFrozen()
    }

    // MARK: - Prompt memory

    func shouldPrompt(host: String?) -> Bool {
        guard let host, !host.isEmpty else { return true }
        return !silencedHosts.contains(host)
    }

    func silence(host: String?) {
        guard let host, !host.isEmpty else { return }
        silencedHosts.insert(host)
        persistSilenced()
    }

    func unsilence(host: String) {
        silencedHosts.remove(host)
        persistSilenced()
    }

    func clearSilencedHosts() {
        silencedHosts.removeAll()
        persistSilenced()
    }

    // MARK: - Reset

    /// Returns every new switch to the pre-upgrade state in one action.
    func resetToPreUpgradeBehavior() {
        settings = .allOff
        pillPlacement = .default
        clearSilencedHosts()
        clearFrozenHosts()
        clearGrantedHosts()
    }

    func restoreShippedDefaults() {
        settings = .default
        pillPlacement = .default
    }

    // MARK: - Persistence

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }

    private func persistPlacement() {
        guard let data = try? JSONEncoder().encode(pillPlacement) else { return }
        UserDefaults.standard.set(data, forKey: placementKey)
    }

    private func persistSilenced() {
        UserDefaults.standard.set(Array(silencedHosts), forKey: silencedKey)
    }

    private func persistFrozen() {
        UserDefaults.standard.set(Array(frozenHosts), forKey: frozenKey)
    }

    private func persistGranted() {
        UserDefaults.standard.set(Array(grantedHosts), forKey: grantedKey)
        UserDefaults.standard.set(Array(micGrantedHosts), forKey: micGrantedKey)
    }
}
