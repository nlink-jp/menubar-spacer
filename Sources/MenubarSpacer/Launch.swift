import AppKit
import Foundation

/// What this process should do. Decided before any window exists.
enum LaunchDecision: Equatable {
    case run
    /// Another copy of this app is already running.
    case exitAlreadyRunning
}

enum Launch {
    /// Pure, so the rule can be tested without launching anything.
    static func decide(otherInstanceCount: Int) -> LaunchDecision {
        otherInstanceCount > 0 ? .exitAlreadyRunning : .run
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
