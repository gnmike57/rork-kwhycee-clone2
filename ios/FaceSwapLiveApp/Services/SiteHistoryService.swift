import Foundation

@Observable
@MainActor
final class SiteHistoryService {
    var entries: [SiteHistoryEntry] = []

    private let storageKey = "site_history_v1"

    init() {
        loadEntries()
    }

    func addEntry(_ entry: SiteHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > 500 {
            entries = Array(entries.prefix(500))
        }
        saveEntries()
    }

    func entriesForSite(_ url: String) -> [SiteHistoryEntry] {
        // Same rule the list screen uses: one normalized key per site, so a
        // host never matches because it happens to be a substring of another.
        let key = normalizedSiteKey(for: url)
        return entries.filter { normalizedSiteKey(for: $0.siteURL) == key }
    }

    func lastSuccessfulProfile(for url: String) -> String? {
        entriesForSite(url).first(where: { $0.wasSuccessful })?.profileUsed
    }

    func clearHistory() {
        entries = []
        saveEntries()
    }

    func addEntries(_ newEntries: [SiteHistoryEntry]) {
        entries.insert(contentsOf: newEntries, at: 0)
        if entries.count > 500 {
            entries = Array(entries.prefix(500))
        }
        saveEntries()
    }

    func uniqueSites() -> [String] {
        var sitesByKey: [String: String] = [:]

        for entry in entries {
            let key = normalizedSiteKey(for: entry.siteURL)
            if sitesByKey[key] == nil {
                sitesByKey[key] = entry.siteURL
            }
        }

        return Array(sitesByKey.values).sorted()
    }

    private func normalizedSiteKey(for urlString: String) -> String {
        let normalizedInput = urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard
            let url = URL(string: normalizedInput),
            let host = url.host?.lowercased()
        else {
            return normalizedInput
        }

        if let scheme = url.scheme?.lowercased(), !scheme.isEmpty {
            return "\(scheme)://\(host)"
        }

        return host
    }

    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            entries = try JSONDecoder().decode([SiteHistoryEntry].self, from: data)
        } catch {
            entries = []
        }
    }

    private func saveEntries() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // Silently fail on encode error
        }
    }
}
