import Foundation

enum ApplyOutcome: Equatable {
    /// The keys already held the requested state; nothing was written.
    case alreadyApplied(SpacingSettings)
    case applied(SpacingSettings)
    /// Applied, but over a state neither we nor the record accounts for: someone
    /// changed the keys outside this app after our last write. Reported rather
    /// than refused — the user asked for this value — but never silently.
    case appliedOverExternalChange(SpacingSettings, replaced: SpacingSettings)
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
    /// The recorded original holds a value that cannot be written back.
    case unrestorableOriginal(SpacingSettings)
    case noEffect(expected: SpacingSettings, actual: SpacingSettings)
}

/// Whether a way back exists. One value, not two booleans: a UI that reads
/// "no backup" when the record is merely unreadable would tell the user nothing
/// is in effect at the exact moment something is.
enum BackupStatus: Equatable, Sendable {
    /// Named `absent`, not `none`: `BackupStatus.none` would collide with
    /// `Optional.none` at every call site that holds a `BackupStatus?`.
    case absent
    case present
    case unreadable
}

/// Everything the UI needs to describe the situation in one read.
struct SpacingState: Equatable {
    var currentHost: SpacingSettings
    var anyHost: SpacingSettings
    /// The preset the live state corresponds to, or nil when it came from
    /// somewhere else (a hand-edited `defaults` write, another tool).
    var preset: SpacingPreset?
    var backup: BackupStatus
}

extension SpacingState {
    /// What the menu bar actually uses. A key set for this host wins; a key that
    /// is not falls back to the value set for every host — which is where the
    /// widely copied `defaults write -g NSStatusItemSpacing …` puts it. This app
    /// writes the current host only, so that value is never its own, and the
    /// first version read it (`anyHost`) and then showed nothing of it: a Mac
    /// running at 6 was described as "the macOS default", with the default row
    /// marked "in effect".
    var effective: SpacingSettings {
        var result = currentHost
        for key in SpacingKey.allCases where result[key] == .absent {
            result[key] = anyHost[key]
        }
        return result
    }

    /// True when some of what is in effect comes from the every-host value.
    var inheritsFromEveryHost: Bool { effective != currentHost }
}

/// Applying and undoing, in the one order that is safe: the way back is stored
/// before anything is written, every write is verified by reading it back, and
/// the record is then corrected to describe what the Mac actually holds.
///
/// Every mutating path runs under the store's exclusive lock, and reads the live
/// state inside it. The sequence is a read-modify-write over state shared with
/// every other copy of this app on the Mac.
struct SpacingCoordinator {
    let preferences: SpacingPreferenceReading & SpacingPreferenceWriting
    let backups: BackupStoring
    var now: () -> Date = Date.init

    /// Display only, and deliberately lock-free: blocking the UI to render a
    /// status would be worse than rendering one a moment out of date.
    func state() -> SpacingState {
        let currentHost = preferences.read(.currentHost)
        var backup = BackupStatus.absent
        do {
            backup = try backups.load() == nil ? .absent : .present
        } catch {
            backup = .unreadable
        }
        return SpacingState(currentHost: currentHost,
                            anyHost: preferences.read(.anyHost),
                            preset: SpacingPreset.matching(currentHost),
                            backup: backup)
    }

    func apply(_ preset: SpacingPreset) throws -> ApplyOutcome {
        try backups.withExclusiveAccess { () throws -> ApplyOutcome in
            let target = preset.settings

            var existing: BackupRecord?
            var damaged = false
            var beyondRetry = false
            do {
                existing = try backups.load()
            } catch {
                // Returning to the OS default is the escape hatch. It needs no
                // record and cannot make recovery worse — whatever the damaged
                // file holds is already unreadable — so it stays available even
                // here. Every other preset refuses, rather than overwrite the
                // only record of the state this Mac had before the app ran.
                guard target == .unset else { throw error }
                damaged = true
                if case BackupStoreError.undecodable = error { beyondRetry = true }
            }

            let current = preferences.read(.currentHost)
            let operations = SpacingPlan.operations(from: current, to: target)

            guard !operations.isEmpty else {
                if beyondRetry {
                    // The way home was chosen and the Mac is already there, so
                    // no write will follow to move the file aside — and its
                    // bytes were read and are not a record, so no later read
                    // will do better. Left in place it refuses every value
                    // preset from now on, with an Undo that cannot use it
                    // either. It is moved, not deleted: what it holds stays on
                    // disk for a person. A file that merely could not be READ
                    // is still left exactly where it is (ADR-0001 §11): that
                    // failure may be gone on the next attempt.
                    try backups.quarantine()
                } else if let existing, current == existing.original {
                    discardRecord()
                }
                return .alreadyApplied(current)
            }

            let original = existing?.original ?? current
            let external = existing.map {
                !RestorePlanner.isExplainedByOurWrite(current: current, record: $0)
            } ?? false

            // The way back is stored before the first mutation, never after it.
            if !damaged {
                try backups.save(BackupRecord(original: original, applied: target, capturedAt: now()))
            }

            let actual = try write(operations, recordFor: damaged ? nil : original)

            if damaged {
                // Only now, after a write this app actually performed, is the
                // unreadable file moved aside — and moved, not deleted.
                try backups.quarantine()
            }

            guard actual == target else {
                return .noEffect(expected: target, actual: actual)
            }
            return external ? .appliedOverExternalChange(actual, replaced: current)
                            : .applied(actual)
        }
    }

    func restore() throws -> RestoreOutcome {
        try backups.withExclusiveAccess { () throws -> RestoreOutcome in
            let record: BackupRecord?
            do {
                record = try backups.load()
            } catch {
                // Never write from a record that could not be read.
                return .unusableBackup
            }
            let current = preferences.read(.currentHost)

            switch RestorePlanner.decide(record: record, current: current) {
            case .noBackup:
                return .nothingToRestore
            case let .unrestorableOriginal(settings):
                return .unrestorableOriginal(settings)
            case let .changedExternally(current, original):
                return .refusedExternalChange(current: current, original: original)
            case .alreadyOriginal:
                discardRecord()
                return .alreadyOriginal
            case let .restore(operations):
                guard let record else { return .nothingToRestore }
                // The record is kept describing the Mac whatever the write
                // does, so pressing Restore again resumes instead of blaming an
                // outsider; once the Mac is back at its original it is dropped.
                let actual = try write(operations, recordFor: record.original)
                guard actual == record.original else {
                    return .noEffect(expected: record.original, actual: actual)
                }
                return .restored(actual)
            }
        }
    }

    /// Writes, and leaves the record describing what the Mac holds afterwards —
    /// on the way out through an error exactly as on success.
    ///
    /// The record is saved for the *target* before the first mutation, because
    /// the way back has to exist before anything changes. That is a statement
    /// of intention, and ADR-0001 §2 allows the record none: it is corrected
    /// from observation once the write returns. The first version corrected it
    /// only when the write returned normally. A write that threw — a failed
    /// flush is the one the OS actually produces — left the record claiming a
    /// state the Mac never reached, and the next Undo compared that claim with
    /// the live keys, found them different, and refused the user's own change
    /// as somebody else's.
    ///
    /// `original` is nil when there is no record to keep (the damaged-file
    /// path, which writes without one).
    private func write(_ operations: [WriteOperation],
                       recordFor original: SpacingSettings?) throws -> SpacingSettings {
        do {
            let actual = try preferences.apply(operations)
            if let original { try settle(original: original, actual: actual) }
            return actual
        } catch {
            // Observed, not taken from the error: what matters is what the Mac
            // holds now. Best effort — the write's own failure is the error the
            // caller needs, and a record that could not be corrected is no worse
            // than the one this replaces.
            if let original {
                try? settle(original: original, actual: preferences.read(.currentHost))
            }
            throw error
        }
    }

    /// Makes the record describe what the Mac actually holds — never the target
    /// that was asked for. Once the Mac is back at its original state the record
    /// is dropped, so "there is a backup" keeps meaning "something of ours is in
    /// effect".
    private func settle(original: SpacingSettings, actual: SpacingSettings) throws {
        if actual == original {
            discardRecord()
        } else {
            try backups.save(BackupRecord(original: original, applied: actual, capturedAt: now()))
        }
    }

    /// Best effort by design: a write that already succeeded must not be
    /// reported as a failure because the bookkeeping file would not delete. A
    /// leftover record is harmless — the next restore reports `alreadyOriginal`
    /// and clears it.
    private func discardRecord() {
        try? backups.clear()
    }
}
