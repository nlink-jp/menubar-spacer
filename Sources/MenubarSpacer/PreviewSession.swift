import AppKit

/// The preview process: three real status items, shown at whatever spacing is in
/// effect when this process starts, then gone.
///
/// It exists as a separate process because of the measured behaviour: a process
/// keeps the spacing that was in effect when it launched, no matter when its
/// items are created, so the app that just wrote the new value cannot show it
/// itself (docs/en/phase1-results.md §2).
enum PreviewSession {
    static func run(seconds: Double) {
        let app = NSApplication.shared
        // No Dock icon and no window: this process is only ever three icons.
        app.setActivationPolicy(.accessory)
        let delegate = PreviewDelegate(seconds: seconds)
        app.delegate = delegate
        app.run()
    }
}

final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private let seconds: Double
    private var items: [NSStatusItem] = []

    init(seconds: Double) {
        self.seconds = seconds
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        items = ["circle.fill", "square.fill", "triangle.fill"].map { symbol in
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Spacing preview")
            image?.size = NSSize(width: 15, height: 15)
            item.button?.image = image
            item.button?.setAccessibilityLabel("Menubar Spacer preview")
            item.button?.toolTip = "Menu bar spacing preview"
            return item
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            NSApp.terminate(nil)
        }
        // A preview must never be able to hold the menu bar because the run loop
        // wedged: the same discipline the measurement probe uses.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + seconds + 5) {
            _Exit(0)
        }
    }
}
