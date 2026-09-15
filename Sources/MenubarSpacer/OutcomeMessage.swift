import Foundation

/// Every sentence the app says about what just happened.
///
/// Pure, and gathered in one place so they can be read in the order an operator
/// meets them. Two rules: each one names what changed and what to do next, and
/// none of them uses the app's own vocabulary — no preference key names, no
/// "absent", no type names.
enum OutcomeMessage {
    static let relaunchNote = "Quit and reopen an app to see its menu bar icons move."

    static func apply(_ outcome: ApplyOutcome) -> String {
        switch outcome {
        case let .applied(settings):
            return "\(nowReads(settings)). \(relaunchNote)"
        case let .alreadyApplied(settings):
            return "Already \(describe(settings)). Nothing was changed."
        case let .appliedOverExternalChange(settings, replaced):
            return "\(nowReads(settings)), replacing \(describe(replaced)) that was set "
                + "outside this app. \(relaunchNote)"
        case let .noEffect(_, actual):
            return "macOS did not accept the change — the spacing is still "
                + "\(describe(actual)). This version of macOS may ignore the setting."
        }
    }

    static func restore(_ outcome: RestoreOutcome) -> String {
        switch outcome {
        case let .restored(settings):
            return "Put back the spacing this Mac had before: \(describe(settings)). \(relaunchNote)"
        case .alreadyOriginal:
            return "Already back to how it was."
        case .nothingToRestore:
            return "Nothing to undo — this app has not changed anything."
        case let .refusedExternalChange(current, _):
            return "The spacing was changed outside this app (now \(describe(current))). "
                + "Undoing would throw that away, so nothing was changed. "
                + "Choose the macOS default if you want to clear it."
        case .unusableBackup:
            return "The saved original cannot be read, so nothing was changed. "
                + "You can still choose the macOS default."
        case .unrestorableOriginal:
            return "This Mac's earlier setting cannot be written back, so nothing was "
                + "changed. You can still choose the macOS default."
        case let .noEffect(_, actual):
            return "macOS did not accept the change — the spacing is still "
                + "\(describe(actual)). This version of macOS may ignore the setting."
        }
    }

    static func failure(_ error: Error) -> String {
        switch error {
        case BackupStoreError.unreadable:
            return "The saved original cannot be read, so nothing was changed. "
                + "Choosing the macOS default still works, and clears it."
        case BackupStoreError.lockFailed:
            return "Another copy of this app is busy changing the spacing. "
                + "Try again in a moment."
        case SpacingWriteError.synchronizationFailed:
            return "macOS would not save the change. Nothing else was changed; try again."
        case SpacingWriteError.unrestorableValue:
            return "This Mac's earlier setting cannot be written back, so nothing was "
                + "changed. You can still choose the macOS default."
        default:
            return "The spacing could not be changed, and nothing else was changed."
        }
    }

    private static func nowReads(_ settings: SpacingSettings) -> String {
        settings == .unset ? "Spacing is back to the macOS default"
                           : "Spacing set to \(describe(settings))"
    }

    private static func describe(_ settings: SpacingSettings) -> String {
        if settings == .unset { return "the macOS default" }
        if let value = settings.uniformValue { return String(value) }
        return "a setting made outside this app"
    }
}
