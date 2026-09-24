import Foundation

/// App storage that stays on the phone: locked while the phone is locked,
/// and left out of backups.
enum ProtectedDirectory {
    static func make(named name: String, base: URL? = nil) throws -> URL {
        let root = base ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
        return mutable
    }

    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }

    static func isProtected(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let protection = attributes?[.protectionKey] as? FileProtectionType
        return values?.isExcludedFromBackup == true && protection == .complete
    }
}
