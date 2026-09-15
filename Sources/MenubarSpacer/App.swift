import AppKit
import SwiftUI

/// A non-resident window app: launch, choose, apply, quit. It deliberately does
/// not live in the menu bar — a tool whose job is to reclaim menu bar width
/// should not spend an icon's worth of it.
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

/// `@main` lives here rather than on the `App` struct because a SwiftUI `App`
/// cannot run anything before its Scene, and two decisions have to be made
/// first: whether this process is a preview child, and whether another copy of
/// the app is already running.
@main
enum Main {
    static func main() {
        switch Launch.decide(arguments: Array(CommandLine.arguments.dropFirst()),
                             otherInstanceCount: Launch.otherInstanceCount()) {
        case let .preview(seconds):
            PreviewSession.run(seconds: seconds)
        case .exitAlreadyRunning:
            FileHandle.standardError.write(Data("menubar-spacer is already running\n".utf8))
            exit(0)
        case .run:
            MenubarSpacerApp.main()
        }
    }
}

enum AppInfo {
    /// The bundle's version, or "dev" when run outside a built `.app`.
    static var version: String {
        version(bundleValue: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString"))
    }

    /// The display rule, separated from the bundle lookup so it can be tested.
    static func version(bundleValue: Any?) -> String {
        guard let value = bundleValue as? String,
              !value.trimmingCharacters(in: .whitespaces).isEmpty
        else { return "dev" }
        return value
    }
}
