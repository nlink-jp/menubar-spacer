import SwiftUI

/// Scaffold UI: it reads and describes the live state, and lists the presets.
/// Applying, previewing and restoring are Phase 2 work — the coordinator exists
/// and is tested, but nothing here calls it yet, so this window must not offer a
/// control that claims to change anything.
struct ContentView: View {
    private let coordinator: SpacingCoordinator
    @State private var state: SpacingState?

    init(coordinator: SpacingCoordinator = SpacingCoordinator(preferences: SystemSpacingPreferences(),
                                                              backups: FileBackupStore())) {
        self.coordinator = coordinator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Menu bar spacing")
                .font(.title2.weight(.semibold))

            GroupBox("Current spacing") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("This Mac", value: SpacingDescription.spacing(state?.currentHost))
                    LabeledContent("All Macs", value: SpacingDescription.spacing(state?.anyHost))
                    LabeledContent("Can be undone", value: SpacingDescription.backup(state?.backup))
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Presets") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SpacingPreset.allCases) { preset in
                        LabeledContent(preset.title) {
                            Text(preset.value.map(String.init) ?? "—").monospacedDigit()
                        }
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Version \(AppInfo.version)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { state = coordinator.state() }
    }
}

/// What the person in front of the screen is told. Deliberately free of the
/// app's own vocabulary: no key names, no "absent", no build status.
enum SpacingDescription {
    static func spacing(_ settings: SpacingSettings?) -> String {
        guard let settings else { return "—" }
        if settings == .unset { return "macOS default" }
        if let value = settings.uniformValue { return String(value) }
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
    ContentView(coordinator: SpacingCoordinator(preferences: StubSpacingPreferences(currentHost: .uniform(8)),
                                                backups: StubBackupStore()))
}
