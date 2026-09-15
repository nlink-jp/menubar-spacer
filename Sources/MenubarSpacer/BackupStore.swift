import Foundation

/// Where the way back is kept. One record or none.
protocol BackupStoring {
    /// The stored record, or nil when this app has changed nothing.
    /// Throws rather than returning nil when a record exists but cannot be read:
    /// pretending there is no backup would tell the user nothing was changed
    /// while their Mac still is.
    func load() throws -> BackupRecord?
    func save(_ record: BackupRecord) throws
    func clear() throws
}

enum BackupStoreError: Error, Equatable {
    /// A record file exists but is not readable as one.
    case unreadable(String)
}

/// A single JSON file under Application Support, written atomically.
struct FileBackupStore: BackupStoring {
    let url: URL

    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("jp.nlink.menubar-spacer", isDirectory: true)
            .appendingPathComponent("backup.json", isDirectory: false)
    }

    init(url: URL = FileBackupStore.applicationSupport) {
        self.url = url
    }

    func load() throws -> BackupRecord? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupStoreError.unreadable(String(describing: error))
        }
        do {
            return try JSONDecoder().decode(BackupRecord.self, from: data)
        } catch {
            throw BackupStoreError.unreadable(String(describing: error))
        }
    }

    func save(_ record: BackupRecord) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: url, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

/// An in-memory store for previews and tests.
final class StubBackupStore: BackupStoring {
    var record: BackupRecord?
    var loadError: BackupStoreError?
    private(set) var saveCount = 0
    private(set) var clearCount = 0

    init(record: BackupRecord? = nil) {
        self.record = record
    }

    func load() throws -> BackupRecord? {
        if let loadError { throw loadError }
        return record
    }

    func save(_ record: BackupRecord) throws {
        saveCount += 1
        self.record = record
    }

    func clear() throws {
        clearCount += 1
        record = nil
    }
}
