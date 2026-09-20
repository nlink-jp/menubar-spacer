import SwiftUI

struct ContentView: View {
    @StateObject private var model: SpacingViewModel

    init(model: SpacingViewModel? = nil) {
        _model = StateObject(wrappedValue: model ?? SpacingViewModel(
            coordinator: SpacingCoordinator(preferences: SystemSpacingPreferences(),
                                            backups: FileBackupStore())))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            SpacingSampleView(current: model.state.effective, selection: $model.selection)

            HStack(spacing: 10) {
                Button("Apply") { model.apply() }
                    .keyboardShortcut(.defaultAction)
                Button("Undo my changes") { model.restore() }
                    .disabled(!model.canUndo)
            }

            Text(OutcomeMessage.scopeNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Divider()

            Text("Version \(AppInfo.version)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { model.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Menu bar spacing")
                .font(.title2.weight(.semibold))
            Text("Currently \(SpacingDescription.spacing(model.state.effective)).")
                .foregroundStyle(.secondary)
            if let note = SpacingDescription.everyHostNote(model.state) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// What the person in front of the screen is told about the current state.
/// Deliberately free of the app's own vocabulary: no key names, no "absent".
enum SpacingDescription {
    static func spacing(_ settings: SpacingSettings?) -> String {
        guard let settings else { return "unknown" }
        if settings == .unset { return "the macOS default" }
        if let value = settings.uniformValue { return "set to \(value)" }
        return "set outside this app"
    }

    /// Said only when it changes what a choice here will do: the value in
    /// effect is not this Mac's own, so "macOS default" does not mean Apple's.
    static func everyHostNote(_ state: SpacingState) -> String? {
        guard state.hasEveryHostValue else { return nil }
        if state.inheritsFromEveryHost {
            return "That spacing is set for every Mac you sign in to, outside this app. "
                + "A spacing chosen here overrides it on this Mac; “macOS default” here "
                + "returns to that value, not to Apple's."
        }
        // Shown while this Mac's own setting hides it, too: this is the moment
        // "macOS default" is about to mean something else.
        // "A spacing (set to 6) is also set…" is what this read as until it was
        // drawn and looked at: `spacing(_:)` is a predicate phrase, not a value.
        let which = state.anyHost.uniformValue.map { "A spacing of \($0)" } ?? "A spacing"
        return "\(which) is also set for every Mac you sign in to, outside this app. "
            + "“macOS default” here returns to that value, not to Apple's."
    }

    static func backup(_ status: BackupStatus?) -> String {
        guard let status else { return "—" }
        switch status {
        case .absent: return "nothing to undo"
        case .present: return "yes"
        case .unreadable: return "the saved original cannot be read"
        }
    }
}

#Preview {
    ContentView(model: SpacingViewModel(
        coordinator: SpacingCoordinator(preferences: StubSpacingPreferences(currentHost: .uniform(8)),
                                        backups: StubBackupStore())))
}
