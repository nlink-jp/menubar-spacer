import Foundation

/// What the two keys held before this app first changed them, plus what the Mac
/// was last observed to hold after one of our writes. One record, not a history:
/// the only state worth keeping is the way back.
///
/// Both fields are captured from what was actually read, never from what was
/// intended. `original` in particular may hold values this app would never
/// produce — a hand-set 100, or a string — and those are exactly the values a
/// restore has to put back.
struct BackupRecord: Equatable, Codable, Sendable {
    /// The state read immediately before the first apply.
    var original: SpacingSettings
    /// The state read back after the most recent write. Not the target: a write
    /// that only half landed must leave the record describing the Mac as it is.
    var applied: SpacingSettings
    var capturedAt: Date
    /// Set only while a write is in doubt: what this app's own earlier write had
    /// left, which the write in progress set out to replace. The record is
    /// stored before the first mutation and names the target as `applied`; if
    /// that write then fails, the Mac holds either the target or this, and
    /// nothing read afterwards can say which — `CFPreferencesSetMultiple` has
    /// already run when the flush fails, so the process may read back a value
    /// the disk never got. Naming both lets Undo recognise its own state
    /// whichever it is. Never an outsider's value (ADR-0001 §10), and cleared
    /// once a write has been read back. Optional, so a record written by an
    /// earlier version still decodes — and an earlier version reading this one
    /// ignores the key.
    var replaced: SpacingSettings? = nil
}

/// What "Restore" should do, decided from the record and the live state before
/// anything is written.
enum RestoreDecision: Equatable, Sendable {
    /// Nothing was ever changed by this app.
    case noBackup
    /// The live state already equals the original; there is nothing to undo.
    case alreadyOriginal
    /// The live state is explicable by our own write — safe to put the original back.
    case restore([WriteOperation])
    /// Someone else changed the keys after our write. Restoring would silently
    /// discard their change, so the UI must ask instead of deciding.
    case changedExternally(current: SpacingSettings, original: SpacingSettings)
    /// The recorded original holds something that cannot be written back.
    case unrestorableOriginal(SpacingSettings)
}

enum RestorePlanner {
    static func decide(record: BackupRecord?, current: SpacingSettings) -> RestoreDecision {
        guard let record else { return .noBackup }
        if current == record.original { return .alreadyOriginal }
        guard record.original.isRestorable else {
            return .unrestorableOriginal(record.original)
        }
        guard isExplainedByOurWrite(current: current, record: record) else {
            return .changedExternally(current: current, original: record.original)
        }
        return .restore(SpacingPlan.operations(from: current, to: record.original))
    }

    /// True when every key holds either what it held before our write, what we
    /// last observed after it, or — while a write is in doubt — what that write
    /// was replacing (`replaced`). That covers the exact state we left behind, and
    /// also a write that landed on one key only — whether because the OS ignored
    /// half of it or because the app died between the two. Attributing such a
    /// state to an outsider would make the app refuse to clean up its own mess.
    ///
    /// A third party that happens to set a key to precisely the value we wrote is
    /// indistinguishable from us, and is treated as us. Restoring is the right
    /// move either way.
    static func isExplainedByOurWrite(current: SpacingSettings, record: BackupRecord) -> Bool {
        SpacingKey.allCases.allSatisfy { key in
            current[key] == record.original[key] || current[key] == record.applied[key]
                || (record.replaced.map { current[key] == $0[key] } ?? false)
        }
    }
}
