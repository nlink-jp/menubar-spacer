import Foundation
import SwiftUI

/// The window's state, and the only place the UI touches the coordinator.
///
/// Work runs on the calling thread: a write is a handful of local CFPreferences
/// calls, and the lock it takes is uncontended because the app is
/// single-instance and the preview child never writes. Moving this off the main
/// thread would buy nothing and put a safety-critical sequence behind a second
/// source of truth.
@MainActor
final class SpacingViewModel: ObservableObject {
    @Published private(set) var state: SpacingState
    @Published private(set) var message: String?
    @Published var selection: SpacingPreset

    private let coordinator: SpacingCoordinator
    private let startPreview: (Double) throws -> Void

    init(coordinator: SpacingCoordinator,
         startPreview: @escaping (Double) throws -> Void = { try PreviewLauncher.start(seconds: $0) }) {
        self.coordinator = coordinator
        self.startPreview = startPreview
        let state = coordinator.state()
        self.state = state
        self.selection = state.preset ?? .osDefault
    }

    /// True while this app is holding a spacing the Mac did not have before.
    var canUndo: Bool { state.backup != .absent }

    func refresh() {
        state = coordinator.state()
    }

    func apply() {
        do {
            let outcome = try coordinator.apply(selection)
            var text = OutcomeMessage.apply(outcome)
            // The change is invisible in every app that is already running, so
            // the app shows it itself — in a child process, the only kind that
            // can pick up a spacing written a moment ago.
            if outcome.changedSomething, (try? startPreview(Launch.defaultPreviewSeconds)) != nil {
                text += " " + OutcomeMessage.previewNote
            }
            message = text
        } catch {
            message = OutcomeMessage.failure(error)
        }
        refresh()
    }

    func restore() {
        do {
            message = OutcomeMessage.restore(try coordinator.restore())
        } catch {
            message = OutcomeMessage.failure(error)
        }
        refresh()
        selection = state.preset ?? .osDefault
    }

    /// Shows the spacing **that is in effect now** — not the one selected in the
    /// window. A preview of an unapplied value is impossible: a process takes
    /// the spacing that was in effect when it launched, so there is nothing to
    /// show until the value has been written.
    func showCurrentSpacing() {
        do {
            try startPreview(Launch.defaultPreviewSeconds)
            message = OutcomeMessage.previewNote
        } catch {
            message = "The sample icons could not be shown. Nothing was changed."
        }
    }
}
