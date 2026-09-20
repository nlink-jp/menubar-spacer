import Foundation

enum ApplyOutcome: Equatable {
    /// The keys already held the requested state; nothing was written.
    case alreadyApplied(SpacingSettings)
    /// As above, and the saved original — which could not be decoded — was moved
    /// aside on the way. Its own case so that the sentence for it does not say
    /// "nothing was changed".
    case alreadyAppliedRecordSetAside(SpacingSettings)
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

    /// True when an every-host value exists at all — also while this host's own
    /// setting hides it, because that is when "macOS default" is about to mean
    /// something other than Apple's default.
    var hasEveryHostValue: Bool { anyHost != .unset }
}

/// Whether this process can still believe what it reads. A reference, so that
/// every copy of the coordinator shares the one answer.
///
/// `CFPreferencesSetMultiple` has already changed the process's own view by the
/// time the flush can fail, so after a failed flush a read may return a value
/// the disk never got — for the rest of the process's life, as far as anyone
/// has measured. Writing the record to survive that was half of the repair; the
/// other half is this. The very next click re-read the keys, believed the
/// answer, and acted on it: a retried Undo found "already original" and dropped
/// the record while the disk still held the app's value, and a second change
/// recorded the first failure's phantom as the state it replaced. So once a
/// flush fails, this process reads and writes nothing more. A new process reads
/// from disk, and the record it finds explains either outcome.
final class ProcessTrust: @unchecked Sendable {
    /// The process's own. A coordinator built later in the same process — a
    /// window rebuilt by SwiftUI, say — must inherit the doubt, not start
    /// believing again; tests pass their own so that a "relaunch" can forget.
    static let shared = ProcessTrust()

    private let lock = NSLock()
    private var failed = false
    var flushHasFailed: Bool {
        lock.lock(); defer { lock.unlock() }
        return failed
    }
    func recordFailedFlush() {
        lock.lock(); defer { lock.unlock() }
        failed = true
    }
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
    var trust: ProcessTrust = .shared

    /// True once a write in this process failed to flush: the window has to say
    /// so and stop offering actions, because what it displays is a read too.
    var isInDoubt: Bool { trust.flushHasFailed }

    /// The only caller of `preferences.apply`. A failed flush is remembered
    /// before the error leaves.
    private func write(_ operations: [WriteOperation]) throws -> SpacingSettings {
        do {
            return try preferences.apply(operations)
        } catch let error as SpacingWriteError {
            if case .synchronizationFailed = error { trust.recordFailedFlush() }
            throw error
        }
    }

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
        guard !isInDoubt else { throw SpacingWriteError.processInDoubt }
        return try backups.withExclusiveAccess { () throws -> ApplyOutcome in
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
                    return .alreadyAppliedRecordSetAside(current)
                } else if let existing, current == existing.original {
                    discardRecord()
                }
                return .alreadyApplied(current)
            }

            let original = existing?.original ?? current
            let external = existing.map {
                !RestorePlanner.isExplainedByOurWrite(current: current, record: $0)
            } ?? false

            // The way back is stored before the first mutation, never after it —
            // so it has to be written for a state the Mac is not in yet. It
            // therefore names both states the Mac can be left in: the target,
            // and what is being replaced when that is this app's own earlier
            // write (never an outsider's: §10). If the write below throws, the
            // record is left exactly like that. Nothing read after a failed
            // flush can be trusted to say which of the two the Mac holds, and
            // the first attempt at this — settling from such a read — could
            // drop the record, and the original with it.
            if !damaged {
                let replaced = (existing != nil && !external) ? current : nil
                try backups.save(BackupRecord(original: original, applied: target,
                                              capturedAt: now(), replaced: replaced))
            }

            let actual = try write(operations)

            if damaged {
                // Only now, after a write this app actually performed, is the
                // unreadable file moved aside — and moved, not deleted.
                try backups.quarantine()
            } else {
                try settle(original: original, actual: actual)
            }

            guard actual == target else {
                return .noEffect(expected: target, actual: actual)
            }
            return external ? .appliedOverExternalChange(actual, replaced: current)
                            : .applied(actual)
        }
    }

    func restore() throws -> RestoreOutcome {
        guard !isInDoubt else { throw SpacingWriteError.processInDoubt }
        return try backups.withExclusiveAccess { () throws -> RestoreOutcome in
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
                // A restore stores no intention first — the record it works
                // from already explains both the state it leaves and the one
                // it aims at — so a write that throws leaves it as it is, and
                // pressing Restore again resumes.
                let actual = try write(operations)
                guard actual == record.original else {
                    // Keep the record describing the Mac, so pressing Restore
                    // again resumes instead of blaming an outsider.
                    try settle(original: record.original, actual: actual)
                    return .noEffect(expected: record.original, actual: actual)
                }
                discardRecord()
                return .restored(actual)
            }
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
