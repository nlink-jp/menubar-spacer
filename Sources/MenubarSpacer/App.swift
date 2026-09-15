import SwiftUI

/// A non-resident window app: launch, choose, apply, quit. It deliberately does
/// not live in the menu bar — a tool whose job is to reclaim menu bar width
/// should not spend an icon's worth of it.
@main
struct MenubarSpacerApp: App {
    var body: some Scene {
        Window("Menubar Spacer", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

enum AppInfo {
    /// The bundle's version, or "dev" when run outside a built `.app`.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
