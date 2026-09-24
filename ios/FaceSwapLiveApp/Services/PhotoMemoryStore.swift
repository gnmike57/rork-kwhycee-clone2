import Foundation

/// One photo's teaching: strength, an optional live rest, corrections and the rig.
///
/// Live expression logs are not stored. This is only the still's own map.
struct PhotoMemory: Codable, Sendable, Equatable {
    var fingerprint: PhotoFingerprint
    var strength: Double
    var calibration: [Float]?
    var rig: FaceRig
    var savedAt: Date

    static let defaultStrength = 0.8
}

/// About 200 photos or 50 MB, oldest dropped first. Locked with the phone.
final class PhotoMemoryStore {
    private let directory: URL
    private let photoBudget: Int
    private let byteBudget: Int
    private let indexURL: URL
    private(set) var records: [PhotoMemory] = []

    init(directory: URL? = nil, photoBudget: Int = 200, byteBudget: Int = 50 * 1024 * 1024) {
        let folder = directory ?? (try? ProtectedDirectory.make(named: "FaceMemory")) ?? FileManager.default.temporaryDirectory
        self.directory = folder
        self.photoBudget = photoBudget
        self.byteBudget = byteBudget
        indexURL = folder.appendingPathComponent("memories.json")
        records = Self.load(indexURL)
    }

    var count: Int { records.count }

    var byteSize: Int {
        (try? Data(contentsOf: indexURL).count) ?? 0
    }

    func match(_ fingerprint: PhotoFingerprint) -> PhotoMemory? {
        records.first { $0.fingerprint.matches(fingerprint) }
    }

    func save(_ memory: PhotoMemory) {
        records.removeAll { $0.fingerprint.matches(memory.fingerprint) }
        records.append(memory)
        records.sort { $0.savedAt < $1.savedAt }
        evict()
        write()
    }

    func removeAll() {
        records = []
        try? FileManager.default.removeItem(at: indexURL)
    }

    private func evict() {
        while records.count > photoBudget {
            records.removeFirst()
        }
        while records.count > 1, encodedSize(records) > byteBudget {
            records.removeFirst()
        }
    }

    private func write() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? ProtectedDirectory.write(data, to: indexURL)
    }

    private static func load(_ url: URL) -> [PhotoMemory] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PhotoMemory].self, from: data)) ?? []
    }

    private func encodedSize(_ records: [PhotoMemory]) -> Int {
        (try? JSONEncoder().encode(records).count) ?? 0
    }
}
