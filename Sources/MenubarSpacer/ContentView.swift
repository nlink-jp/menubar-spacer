import SwiftUI

/// Scaffold UI: it reads and describes the live state, and lists the presets.
/// Applying, previewing and restoring are Phase 1/2 work — until the preference
/// writer and its hardware checks exist, this window must not offer a button
/// that claims to change anything.
struct ContentView: View {
    private let preferences: SpacingPreferenceReading
    @State private var currentHost: SpacingSettings = .unset
    @State private var anyHost: SpacingSettings = .unset

    init(preferences: SpacingPreferenceReading = SystemSpacingPreferences()) {
        self.preferences = preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Menu bar spacing")
                .font(.title2.weight(.semibold))

            GroupBox("Current state") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("This Mac", value: describe(currentHost))
                    LabeledContent("All Macs", value: describe(anyHost))
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Presets") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SpacingPreset.allCases) { preset in
                        LabeledContent(preset.rawValue) {
                            Text(preset.value.map(String.init) ?? "unset")
                                .monospacedDigit()
                                .foregroundStyle(preset.isMeasured ? .primary : .secondary)
                        }
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Scaffold build \(AppInfo.version): applying, preview and restore are not implemented yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380)
        .onAppear(perform: reload)
    }

    private func reload() {
        currentHost = preferences.read(.currentHost)
        anyHost = preferences.read(.anyHost)
    }

    private func describe(_ settings: SpacingSettings) -> String {
        if settings == .unset { return "OS default (both keys unset)" }
        if let value = settings.uniformValue { return "\(value)" }
        return "mixed (\(text(settings.spacing)) / \(text(settings.selectionPadding)))"
    }

    private func text(_ value: StoredValue) -> String {
        value.integerValue.map(String.init) ?? "unset"
    }
}

#Preview {
    ContentView(preferences: StubSpacingPreferences(currentHost: .uniform(8)))
}
