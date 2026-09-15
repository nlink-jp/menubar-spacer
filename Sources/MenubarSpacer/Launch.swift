import AppKit
import Foundation

/// What this process should do. Decided before any window exists.
enum LaunchDecision: Equatable {
    /// Show the app.
    case run
    /// Be a preview: put real status items in the menu bar for a few seconds and
    /// exit. Spawned by the running app after it writes a new spacing, because
    /// the value is latched per process — see docs/en/phase1-results.md.
    case preview(seconds: Double)
    /// Another copy of this app is already running.
    case exitAlreadyRunning
}

enum Launch {
    static let previewFlag = "--preview"
    static let defaultPreviewSeconds = 6.0

    /// Pure, so the rule can be tested without launching anything.
    ///
    /// The preview is decided **before** the single-instance check on purpose:
    /// a preview is always a child of the running app, so guarding it would make
    /// the feature a silent no-op.
    static func decide(arguments: [String], otherInstanceCount: Int) -> LaunchDecision {
        if arguments.first == previewFlag {
            let seconds = arguments.count > 1 ? Double(arguments[1]) : nil
            return .preview(seconds: clampPreview(seconds ?? defaultPreviewSeconds))
        }
        return otherInstanceCount > 0 ? .exitAlreadyRunning : .run
    }

    /// A preview holds the menu bar; it must never be able to hold it forever.
    static func clampPreview(_ seconds: Double) -> Double {
        guard seconds.isFinite, seconds > 0 else { return defaultPreviewSeconds }
        return min(seconds, 30)
    }

    static func previewArguments(seconds: Double) -> [String] {
        [previewFlag, String(clampPreview(seconds))]
    }

    /// Copies of this bundle already running, excluding this process. Covers
    /// direct execution and `open -n`, which `LSMultipleInstancesProhibited`
    /// does not.
    static func otherInstanceCount() -> Int {
        guard let identifier = Bundle.main.bundleIdentifier else { return 0 }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .count
    }
}

/// Starts a preview of the current spacing as a child of this process.
enum PreviewLauncher {
    /// Nothing to undo and nothing to record: the child only draws.
    static func start(seconds: Double = Launch.defaultPreviewSeconds,
                      executable: URL? = Bundle.main.executableURL) throws {
        guard let executable else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = Launch.previewArguments(seconds: seconds)
        try process.run()
    }
}
