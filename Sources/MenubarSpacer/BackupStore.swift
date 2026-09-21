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
    /// Moves an unreadable record aside instead of deleting it. A file that
    /// cannot be decoded today may still be readable by a person, and the read
    /// may have failed for a transient reason.
    func quarantine() throws

    /// Runs `body` while holding exclusive access across every instance of this
    /// app on this Mac. The read-current → load → save → write sequence is a
    /// read-modify-write over shared state: without this, a second instance can
    /// record a state this app itself produced as the user's original.
    func withExclusiveAccess<T>(_ body: () throws -> T) throws -> T
}

enum BackupStoreError: Error, Equatable {
    /// A record file exists and could not be read. The cause may be transient,
    /// so nothing is decided about the file on the strength of this.
    case unreadable(String)
    /// The file was read, and what it holds is not a record. Reading it again
    /// returns the same bytes: this one does not get better by waiting.
    case undecodable(String)
    case lockFailed(String)
    /// The record could not be written. Its own case so that a failure to write
    /// down the way back is never reported as a failure to change the spacing.
    case notSaved(String)
}

/// A single JSON file under Application Support, written atomically, guarded by
/// a lock file beside it.
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
            throw BackupStoreError.undecodable(String(describing: error))
        }
    }

    func save(_ record: BackupRecord) throws {
        do {
            try createContainer()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(record).write(to: url, options: .atomic)
        } catch {
            throw BackupStoreError.notSaved(String(describing: error))
        }
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func quarantine() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        // The stamp has one-second resolution, and a second unusable file within
        // the same second made the move fail — the user was then told the
        // spacing "could not be changed". A numbered suffix keeps both.
        let folder = url.deletingLastPathComponent()
        let base = url.lastPathComponent + ".damaged-" + stamp
        var destination = folder.appendingPathComponent(base)
        var n = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            n += 1
            destination = folder.appendingPathComponent("\(base)-\(n)")
        }
        try FileManager.default.moveItem(at: url, to: destination)
    }

    func withExclusiveAccess<T>(_ body: () throws -> T) throws -> T {
        try createContainer()
        let lockURL = url.deletingLastPathComponent().appendingPathComponent("lock")
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else {
            throw BackupStoreError.lockFailed("open(\(lockURL.lastPathComponent)) failed: \(errno)")
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw BackupStoreError.lockFailed("flock failed: \(errno)")
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private func createContainer() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
    }
}

/// An in-memory store for previews and tests.
final class StubBackupStore: BackupStoring {
    var record: BackupRecord?
    var loadError: BackupStoreError?
    /// Simulates a record file that will not delete.
    var clearError: BackupStoreError?
    /// Simulates a record file that will not write.
    var saveError: BackupStoreError?
    /// Runs after each successful save, so a test can let the pre-write record
    /// through and fail the correction that follows it.
    var onSave: (() -> Void)?
    private(set) var saveCount = 0
    private(set) var clearCount = 0
    private(set) var quarantineCount = 0
    private(set) var lockDepth = 0
    /// Every load/save/clear/quarantine and the writes the coordinator performs,
    /// in order, so a test can assert the sequence and not just the totals.
    private(set) var journal: [String] = []
    /// Runs the first time exclusive access is taken, to simulate another
    /// instance acting in the window the lock is supposed to close.
    var onLock: (() -> Void)?

    init(record: BackupRecord? = nil) {
        self.record = record
    }

    func note(_ entry: String) { journal.append(entry) }

    func load() throws -> BackupRecord? {
        journal.append("load")
        if let loadError { throw loadError }
        return record
    }

    func save(_ record: BackupRecord) throws {
        journal.append("save")
        if let saveError { throw saveError }
        saveCount += 1
        self.record = record
        onSave?()
    }

    func clear() throws {
        journal.append("clear")
        if let clearError { throw clearError }
        clearCount += 1
        record = nil
    }

    func quarantine() throws {
        journal.append("quarantine")
        quarantineCount += 1
        loadError = nil
        record = nil
    }

    func withExclusiveAccess<T>(_ body: () throws -> T) throws -> T {
        journal.append("lock")
        lockDepth += 1
        if let onLock {
            self.onLock = nil
            onLock()
        }
        defer {
            lockDepth -= 1
            journal.append("unlock")
        }
        return try body()
    }
}
