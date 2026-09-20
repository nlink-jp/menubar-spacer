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
    /// this Mac's own setting is cleared, that value is what applies — so "the
    /// macOS default" is then the wrong name for the result, and a first attempt
    /// that merely appended a sentence produced "Already the macOS default…
    /// applies: 6." The phrase itself depends on it.
    static func apply(_ outcome: ApplyOutcome, everyHost: SpacingSettings = .unset) -> String {
        applyText(outcome, Wording(everyHost: everyHost))
    }

    static func restore(_ outcome: RestoreOutcome, everyHost: SpacingSettings = .unset) -> String {
        restoreText(outcome, Wording(everyHost: everyHost))
    }

    /// How a state is put into words, given what is set for every Mac.
    struct Wording {
        let everyHost: SpacingSettings

        /// True when some key of `settings` is left to the every-host value.
        func inherits(_ settings: SpacingSettings) -> Bool {
            SpacingKey.allCases.contains { settings[$0] == .absent && everyHost[$0] != .absent }
        }

        /// "the macOS default", "8", … as the object of a sentence.
        func describe(_ settings: SpacingSettings) -> String {
            if settings == .unset {
                return inherits(settings)
                    ? "no spacing of its own, so the one set for every Mac outside this app "
                        + "applies (\(plain(everyHost)))"
                    : "the macOS default"
            }
            let own = plain(settings)
            return inherits(settings)
                ? own + ", in part from a value set for every Mac outside this app" : own
        }

        func nowReads(_ settings: SpacingSettings) -> String {
            if settings == .unset {
                return inherits(settings)
                    ? "This Mac now has " + describe(settings)
                    : "Spacing is back to the macOS default"
            }
            return "Spacing set to \(describe(settings))"
        }

        func already(_ settings: SpacingSettings) -> String {
            settings == .unset && inherits(settings)
                ? "This Mac already has " + describe(settings)
                : "Already \(describe(settings))"
        }

        private func plain(_ settings: SpacingSettings) -> String {
            if settings == .unset { return "the macOS default" }
            if let value = settings.uniformValue { return String(value) }
            return "a setting made outside this app"
        }
    }

    private static func applyText(_ outcome: ApplyOutcome, _ w: Wording) -> String {
        switch outcome {
        case let .applied(settings):
            return "\(w.nowReads(settings)). \(relaunchNote)"
        case let .alreadyApplied(settings):
            return "\(w.already(settings)). Nothing was changed."
        case let .alreadyAppliedRecordSetAside(settings):
            return "\(w.already(settings)), so the spacing was not changed. The saved "
                + "original that could not be read has been moved aside; you can choose any "
                + "spacing again."
        case let .appliedOverExternalChange(settings, replaced):
            return "\(w.nowReads(settings)), replacing \(w.describe(replaced)) that was set "
                + "outside this app. \(relaunchNote)"
        case let .noEffect(_, actual):
            return "macOS did not accept the change — the spacing is still "
                + "\(w.describe(actual)). This version of macOS may ignore the setting."
        }
    }

    private static func restoreText(_ outcome: RestoreOutcome, _ w: Wording) -> String {
        switch outcome {
        case let .restored(settings):
            return "Put back the spacing this Mac had before: \(w.describe(settings)). \(relaunchNote)"
        case .alreadyOriginal:
            return "Already back to how it was."
        case .nothingToRestore:
            return "Nothing to undo — this app has not changed anything."
        case let .refusedExternalChange(current, _):
            return "The spacing was changed outside this app (now \(w.describe(current))). "
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
                + "\(w.describe(actual)). This version of macOS may ignore the setting."
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
        case SpacingWriteError.synchronizationFailed, SpacingWriteError.processInDoubt:
            // Not "try again": after a save that failed, this window cannot tell
            // what the Mac holds, and a second attempt acts on a read it should
            // not believe. The first version of this sentence invited exactly
            // that.
            return "macOS would not save the change, so this window can no longer tell what "
                + "your Mac holds. Quit menubar-spacer and open it again: your earlier "
                + "spacing and the way back are kept."
        case SpacingWriteError.unrestorableValue:
            return "This Mac's earlier setting cannot be written back, so nothing was "
                + "changed. You can still choose the macOS default."
        default:
            return "The spacing could not be changed, and nothing else was changed."
        }
    }
}
