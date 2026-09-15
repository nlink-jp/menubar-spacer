import Foundation

enum ApplyOutcome: Equatable {
    /// The keys already held the requested state; nothing was written.
    case alreadyApplied(SpacingSettings)
    case applied(SpacingSettings)
    /// The write went through but the OS does not hold what was asked for.
    /// These keys are undocumented; this is a state the product must be able to
    /// report rather than claim success.
    case noEffect(expected: SpacingSettings, actual: SpacingSettings)
}

enum RestoreOutcome: Equatable {
    /// This app has changed nothing.
    case nothingToRestore
    case alreadyOriginal
    case restored(SpacingSettings)
    /// Someone else changed the keys after our write. Undoing now would discard
    /// their change silently, so the caller has to decide.
    case refusedExternalChange(current: SpacingSettings, original: SpacingSettings)
    case unusableBackup
    case noEffect(expected: SpacingSettings, actual: SpacingSettings)
}

/// Everything the UI needs to describe the situation in one read.
struct SpacingState: Equatable {
    var currentHost: SpacingSettings
    var anyHost: SpacingSettings
    /// The preset the live state corresponds to, or nil when it came from
    /// somewhere else (a hand-edited `defaults` write, another tool).
    var preset: SpacingPreset?
    var hasBackup: Bool
    var backupUnreadable: Bool
}

/// Applying and undoing, in the one order that is safe: the way back is stored
/// before anything is written, and every write is verified by reading it back.
struct SpacingCoordinator {
    let preferences: SpacingPreferenceReading & SpacingPreferenceWriting
    let backups: BackupStoring
    var now: () -> Date = Date.init

    func state() -> SpacingState {
        let currentHost = preferences.read(.currentHost)
        var hasBackup = false
        var unreadable = false
        do {
            hasBackup = try backups.load() != nil
        } catch {
            unreadable = true
        }
        return SpacingState(currentHost: currentHost,
                            anyHost: preferences.read(.anyHost),
                            preset: SpacingPreset.matching(currentHost),
                            hasBackup: hasBackup,
                            backupUnreadable: unreadable)
    }

    func apply(_ preset: SpacingPreset) throws -> ApplyOutcome {
        let target = preset.settings
        let current = preferences.read(.currentHost)

        var existing: BackupRecord?
        var hadUnreadableBackup = false
        do {
            existing = try backups.load()
        } catch {
            // Returning to the OS default is the escape hatch. It needs no record
            // and cannot make recovery worse — whatever the unreadable file held
            // is already lost — so it stays available even here. Every other
            // preset refuses, rather than overwrite the only record of the
            // state this Mac had before the app touched it.
            guard target == .unset else { throw error }
            hadUnreadableBackup = true
        }

        let operations = SpacingPlan.operations(from: current, to: target)
        guard !operations.isEmpty else {
            try settle(current: current, record: existing, discardUnreadable: hadUnreadableBackup)
            return .alreadyApplied(current)
        }

        // The way back is durable before the first mutation, never after it.
        let record = BackupRecord(original: existing?.original ?? current,
                                  applied: target,
                                  capturedAt: now())
        if !hadUnreadableBackup {
            try backups.save(record)
        }

        let actual = try preferences.apply(operations)
        guard actual == target else {
            return .noEffect(expected: target, actual: actual)
        }
        try settle(current: actual, record: hadUnreadableBackup ? nil : record,
                   discardUnreadable: hadUnreadableBackup)
        return .applied(actual)
    }

    func restore() throws -> RestoreOutcome {
        let current = preferences.read(.currentHost)
        let record: BackupRecord?
        do {
            record = try backups.load()
        } catch {
            // Never write from a record that could not be read.
            return .unusableBackup
        }
        guard let record else { return .nothingToRestore }

        switch RestorePlanner.decide(record: record, current: current) {
        case .noBackup:
            return .nothingToRestore
        case .unusableBackup:
            return .unusableBackup
        case let .changedExternally(current, original):
            return .refusedExternalChange(current: current, original: original)
        case .alreadyOriginal:
            try backups.clear()
            return .alreadyOriginal
        case let .restore(operations):
            let actual = try preferences.apply(operations)
            guard actual == record.original else {
                return .noEffect(expected: record.original, actual: actual)
            }
            try backups.clear()
            return .restored(actual)
        }
    }

    /// Keeps "there is a backup" meaning "something of ours is in effect": the
    /// record is dropped once the Mac is back to the state it had beforehand.
    private func settle(current: SpacingSettings, record: BackupRecord?,
                        discardUnreadable: Bool) throws {
        if discardUnreadable {
            try backups.clear()
            return
        }
        if let record, current == record.original {
            try backups.clear()
        }
    }
}
