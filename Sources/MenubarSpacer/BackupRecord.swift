import Foundation

/// What the two keys held before this app first changed them, plus what it wrote.
/// One record, not a history: the only state worth keeping is the way back.
struct BackupRecord: Equatable, Codable, Sendable {
    /// The state captured immediately before the first apply.
    var original: SpacingSettings
    /// The state this app last wrote, used to detect changes made elsewhere.
    var applied: SpacingSettings
    var capturedAt: Date

    var isPlausible: Bool { original.isPlausible && applied.isPlausible }
}

/// What "Restore" should do, decided from the record and the live state before
/// anything is written.
enum RestoreDecision: Equatable, Sendable {
    /// Nothing was ever changed by this app.
    case noBackup
    /// The live state already equals the original; there is nothing to undo.
    case alreadyOriginal
    /// The live state is what this app last wrote — safe to put the original back.
    case restore([WriteOperation])
    /// Someone else changed the keys after our apply. Restoring would silently
    /// discard their change, so the UI must ask instead of deciding.
    case changedExternally(current: SpacingSettings, original: SpacingSettings)
    /// The backup file is unusable (corrupt values). Never write from it.
    case unusableBackup
}

enum RestorePlanner {
    static func decide(record: BackupRecord?, current: SpacingSettings) -> RestoreDecision {
        guard let record else { return .noBackup }
        guard record.isPlausible else { return .unusableBackup }
        if current == record.original { return .alreadyOriginal }
        guard current == record.applied else {
            return .changedExternally(current: current, original: record.original)
        }
        return .restore(SpacingPlan.operations(from: current, to: record.original))
    }
}
