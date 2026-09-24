import Foundation
import UIKit

/// One kept still. Temporary clips are never written here.
struct KeptSlotRecord: Codable, Sendable, Equatable {
    var facing: String
    var slot: Int
    var imageFile: String
    var stampFile: String?
    var originalFile: String?
    var crops: ShapeCrops
}

struct KeptSlot: Sendable {
    var facing: String
    var slot: Int
    var image: UIImage
    var stamp: Data?
    var original: UIImage?
    var crops: ShapeCrops
}

/// Front 1/2 and Back 1/2, kept until Clear All. Files go first, then records.
final class KeptStillStore {
    static let notice = "Stills stay in the app until you Clear All."
    static let noticeSeenKey = "keptStills.noticeSeen"

    private let directory: URL
    private let indexURL: URL
    private var records: [KeptSlotRecord] = []

    init(directory: URL? = nil) {
        let folder = directory ?? (try? ProtectedDirectory.make(named: "KeptStills")) ?? FileManager.default.temporaryDirectory
        self.directory = folder
        indexURL = folder.appendingPathComponent("slots.json")
        records = Self.load(indexURL)
    }

    func save(facing: String, slot: Int, image: UIImage, stamp: Data?, original: UIImage?, crops: ShapeCrops) {
        remove(facing: facing, slot: slot)
        let id = UUID().uuidString
        let imageName = "\(id).png"
        guard let picture = image.pngData() else { return }
        try? ProtectedDirectory.write(picture, to: directory.appendingPathComponent(imageName))
        var stampName: String?
        if let stamp {
            stampName = "\(id)-stamp.jpg"
            try? ProtectedDirectory.write(stamp, to: directory.appendingPathComponent(stampName!))
        }
        var originalName: String?
        if let original, let data = original.pngData() {
            originalName = "\(id)-original.png"
            try? ProtectedDirectory.write(data, to: directory.appendingPathComponent(originalName!))
        }
        records.append(KeptSlotRecord(
            facing: facing,
            slot: slot,
            imageFile: imageName,
            stampFile: stampName,
            originalFile: originalName,
            crops: crops
        ))
        writeIndex()
    }

    func remove(facing: String, slot: Int) {
        guard let index = records.firstIndex(where: { $0.facing == facing && $0.slot == slot }) else { return }
        deleteFiles(records[index])
        records.remove(at: index)
        writeIndex()
    }

    func swap(facing: String) {
        guard let first = records.firstIndex(where: { $0.facing == facing && $0.slot == 0 }),
              let second = records.firstIndex(where: { $0.facing == facing && $0.slot == 1 })
        else { return }
        records[first].slot = 1
        records[second].slot = 0
        writeIndex()
    }

    /// Deletes every picture file, then the index.
    func clearAll() {
        for record in records {
            deleteFiles(record)
        }
        records = []
        try? FileManager.default.removeItem(at: indexURL)
    }

    /// Skips a record whose picture is gone. A missing Media 1 lets Media 2 move up.
    func restored() -> [KeptSlot] {
        var loaded: [KeptSlot] = []
        var changed = false
        for record in records {
            guard let picture = image(named: record.imageFile) else {
                changed = true
                continue
            }
            loaded.append(KeptSlot(
                facing: record.facing,
                slot: record.slot,
                image: picture,
                stamp: record.stampFile.flatMap { data(named: $0) },
                original: record.originalFile.flatMap { self.image(named: $0) },
                crops: record.crops
            ))
        }
        let promoted = promoteMissingFirstSlots(loaded)
        if changed || promoted.map(\.slot) != loaded.map(\.slot) {
            records = records.compactMap { record in
                guard image(named: record.imageFile) != nil else { return nil }
                guard let match = promoted.first(where: { $0.facing == record.facing && $0.image.pngData() == image(named: record.imageFile)?.pngData() }) else {
                    return record
                }
                var updated = record
                updated.slot = match.slot
                return updated
            }
            writeIndex()
        }
        return promoted
    }

    func fileExists(named name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
    }

    private func promoteMissingFirstSlots(_ slots: [KeptSlot]) -> [KeptSlot] {
        var result: [KeptSlot] = []
        for facing in ["front", "back"] {
            let mine = slots.filter { $0.facing == facing }.sorted { $0.slot < $1.slot }
            guard var first = mine.first else { continue }
            if first.slot != 0 {
                first = KeptSlot(facing: first.facing, slot: 0, image: first.image, stamp: first.stamp, original: first.original, crops: first.crops)
                result.append(first)
                result.append(contentsOf: mine.dropFirst())
            } else {
                result.append(contentsOf: mine)
            }
        }
        return result
    }

    private func deleteFiles(_ record: KeptSlotRecord) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(record.imageFile))
        if let stamp = record.stampFile {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(stamp))
        }
        if let original = record.originalFile {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(original))
        }
    }

    private func image(named name: String) -> UIImage? {
        guard let data = data(named: name) else { return nil }
        return UIImage(data: data)
    }

    private func data(named name: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    private func writeIndex() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? ProtectedDirectory.write(data, to: indexURL)
    }

    private static func load(_ url: URL) -> [KeptSlotRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([KeptSlotRecord].self, from: data)) ?? []
    }
}
