import Foundation

/// Every sentence the app says about what just happened.
///
/// Pure, and gathered in one place so they can be read in the order an operator
/// meets them. Two rules: each one names what changed and what to do next, and
/// none of them uses the app's own vocabulary — no preference key names, no
/// "absent", no type names.
enum OutcomeMessage {
    static let relaunchNote = "Quit and reopen an app to see its menu bar icons move."

    /// What this setting does **not** reach, stated where the choice is made
    /// rather than inside a message that scrolls away. Both facts were found by
    /// using the app on real hardware, not from the documentation that does not
    /// exist for these keys: after a full sign out and back in, third-party
    /// icons had taken the new spacing while macOS's own had not.
    static let scopeNote = """
        Each app takes the new spacing when it next launches; sign out and back \
        in to apply it everywhere at once. macOS's own icons — Wi-Fi, battery, \
        the clock, Control Center — keep their spacing either way.
        """

    /// `everyHost` is the value set for every Mac outside this app, if any. When
    /// this Mac's own setting is cleared, that value is what applies, and a
    /// sentence that said "the macOS default" under a header reading "set to 6"
    /// was the first version of this.
    static func apply(_ outcome: ApplyOutcome, everyHost: SpacingSettings = .unset) -> String {
        withEveryHost(applyText(outcome), settings: settings(of: outcome), everyHost: everyHost)
    }

    static func restore(_ outcome: RestoreOutcome, everyHost: SpacingSettings = .unset) -> String {
        withEveryHost(restoreText(outcome), settings: settings(of: outcome), everyHost: everyHost)
    }

    /// Appended only when the outcome left this Mac without a setting of its
    /// own while one exists for every Mac: that is the value now in use.
    private static func withEveryHost(_ text: String, settings: SpacingSettings?,
                                      everyHost: SpacingSettings) -> String {
        guard settings == .unset, everyHost != .unset else { return text }
        return text + " This Mac has no setting of its own now, so the one made for every "
            + "Mac outside this app applies: \(describe(everyHost))."
    }

    private static func settings(of outcome: ApplyOutcome) -> SpacingSettings? {
        switch outcome {
        case let .applied(s), let .alreadyApplied(s), let .alreadyAppliedRecordSetAside(s): return s
        case let .appliedOverExternalChange(s, _): return s
        case let .noEffect(_, actual): return actual
        }
    }

    private static func settings(of outcome: RestoreOutcome) -> SpacingSettings? {
        switch outcome {
        case let .restored(s): return s
        case let .noEffect(_, actual): return actual
        default: return nil
        }
    }

    private static func applyText(_ outcome: ApplyOutcome) -> String {
        switch outcome {
        case let .applied(settings):
            return "\(nowReads(settings)). \(relaunchNote)"
        case let .alreadyApplied(settings):
            return "Already \(describe(settings)). Nothing was changed."
        case let .alreadyAppliedRecordSetAside(settings):
            return "Already \(describe(settings)), so the spacing was not changed. The saved "
                + "original that could not be read has been moved aside; you can choose any "
                + "spacing again."
        case let .appliedOverExternalChange(settings, replaced):
            return "\(nowReads(settings)), replacing \(describe(replaced)) that was set "
                + "outside this app. \(relaunchNote)"
        case let .noEffect(_, actual):
            return "macOS did not accept the change — the spacing is still "
                + "\(describe(actual)). This version of macOS may ignore the setting."
        }
    }

    private static func restoreText(_ outcome: RestoreOutcome) -> String {
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
        case BackupStoreError.undecodable:
            return "The saved original cannot be read, so nothing was changed. "
                + "Choosing the macOS default still works, and clears it."
        case BackupStoreError.unreadable:
            // Not "and clears it": a read that failed may succeed next time, and
            // the file is left alone until a write has actually happened.
            return "The saved original could not be read just now, so nothing was "
                + "changed. Try again; choosing the macOS default still works."
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
