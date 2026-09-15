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

            SpacingSampleView(current: model.state.currentHost, selection: $model.selection)

            HStack(spacing: 10) {
                Button("Apply") { model.apply() }
                    .keyboardShortcut(.defaultAction)
                Button("Undo my changes") { model.restore() }
                    .disabled(!model.canUndo)
            }

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
            Text("Currently \(SpacingDescription.spacing(model.state.currentHost)).")
                .foregroundStyle(.secondary)
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
