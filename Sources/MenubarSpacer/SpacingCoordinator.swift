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

/// The spacing was changed and the record of the way back was not. The change
/// stands; what is stale is the app's own bookkeeping, and applying any spacing
/// again rewrites it. Its own error so that this is never reported as "the
/// spacing could not be changed", which is what v0.1.0 and v0.1.1 said.
enum SpacingRecordError: Error, Equatable {
    case notUpdated(actual: SpacingSettings, cause: String)
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

            let actual: SpacingSettings
            if damaged {
                actual = try preferences.apply(operations)
                // Only now, after a write that took this Mac home, is the
                // unreadable file moved aside — and moved, not deleted. A write
                // the OS ignored, or that landed on one key only, leaves this
                // app's value in effect, and the file may be the way back from
                // it: v0.1.0 set it aside regardless. A file that does not
                // decode is no way back whatever happened, so it still goes.
                if actual == target || beyondRetry { try backups.quarantine() }
            } else {
                actual = try write(operations, from: current, record: existing,
                                   original: original, storingFirst: target)
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
                let actual = try write(operations, from: current, record: record,
                                       original: record.original, storingFirst: nil)
                guard actual == record.original else {
                    return .noEffect(expected: record.original, actual: actual)
                }
                return .restored(actual)
            }
        }
    }

    /// Stores the way back, writes, and leaves the record describing what the
    /// read-back found.
    ///
    /// `target` is what an apply is about to ask for; a restore passes nil,
    /// because it has a record already and stores no intention.
    private func write(_ operations: [WriteOperation], from current: SpacingSettings,
                       record existing: BackupRecord?, original: SpacingSettings,
                       storingFirst target: SpacingSettings?) throws -> SpacingSettings {
        if let target {
            // The way back is stored before the first mutation, never after it —
            // so it is written for the target, and corrected below.
            try backups.save(BackupRecord(original: original, applied: target, capturedAt: now()))
        }

        let actual: SpacingSettings
        do {
            actual = try preferences.apply(operations)
        } catch {
            // macOS says the change was not saved, so the record goes back to
            // what it was — without reading anything: after a failed save a
            // read can still return the value that was asked for. v0.1.0 left
            // the record naming the target, and Undo then refused the user's
            // own earlier change as somebody else's. With no earlier record the
            // new one stays: it is right if the write landed after all, and
            // harmless if it did not (Undo finds the Mac already original).
            if target != nil, let existing { try? backups.save(existing) }
            throw error
        }

        // The Mac has been changed by now, so a failure to write the record down
        // is not a failure to change the spacing (`SpacingRecordError`), and it
        // is not even worth reporting where the record already on disk says what
        // this would have written.
        do {
            if actual == original {
                // Back where the Mac started: "there is a backup" keeps meaning
                // "something of ours is in effect".
                discardRecord()
            } else if actual == current {
                // Nothing changed, so the record goes back exactly as it was.
                // Recording `actual` instead would adopt a value someone else
                // had set as this app's own, and a later Undo would remove it
                // without a word (§10).
                if target != nil, let existing { try backups.save(existing) }
            } else if actual != target {
                // A write that landed in part: the pre-write record names the
                // target, which the Mac does not hold, so this correction is
                // the one that matters.
                try backups.save(BackupRecord(original: original, applied: actual, capturedAt: now()))
            } else {
                // The write did what was asked, so the record stored before it
                // already says this. Worth writing again for `capturedAt`, not
                // worth a failure.
                try? backups.save(BackupRecord(original: original, applied: actual, capturedAt: now()))
            }
        } catch {
            throw SpacingRecordError.notUpdated(actual: actual, cause: String(describing: error))
        }
        return actual
    }

    /// Best effort by design: a write that already succeeded must not be
    /// reported as a failure because the bookkeeping file would not delete. A
    /// leftover record is harmless — the next restore reports `alreadyOriginal`
    /// and clears it.
    private func discardRecord() {
        try? backups.clear()
    }
}
