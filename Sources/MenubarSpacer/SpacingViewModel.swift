import Foundation
import SwiftUI

/// The window's state, and the only place the UI touches the coordinator.
///
/// Work runs on the calling thread: a write is a handful of local CFPreferences
/// calls, and the lock it takes is uncontended because the app is
/// single-instance. Moving this off the main
/// thread would buy nothing and put a safety-critical sequence behind a second
/// source of truth.
@MainActor
final class SpacingViewModel: ObservableObject {
    @Published private(set) var state: SpacingState
    @Published private(set) var message: String?
    @Published var selection: SpacingPreset

    private let coordinator: SpacingCoordinator

    init(coordinator: SpacingCoordinator) {
        self.coordinator = coordinator
        let state = coordinator.state()
        self.state = state
        self.selection = state.preset ?? .osDefault
    }

    /// True while this app is holding a spacing the Mac did not have before.
    var canUndo: Bool { state.backup != .absent && !isInDoubt }

    /// True once a save failed in this window: what it shows is then a read it
    /// cannot vouch for, so it offers nothing but the advice to reopen.
    var isInDoubt: Bool { coordinator.isInDoubt }

    /// Not while in doubt: what the window shows is a read too, and after a save
    /// that failed it would display the value macOS reported and did not keep.
    /// The last state read before the failure stays on screen.
    func refresh() {
        guard !isInDoubt else { return }
        state = coordinator.state()
    }

    func apply() {
        do {
            let outcome = try coordinator.apply(selection)
            message = OutcomeMessage.apply(outcome, everyHost: coordinator.state().anyHost)
        } catch {
            message = OutcomeMessage.failure(error)
        }
        refresh()
    }

    func restore() {
        do {
            let outcome = try coordinator.restore()
            message = OutcomeMessage.restore(outcome, everyHost: coordinator.state().anyHost)
        } catch {
            message = OutcomeMessage.failure(error)
        }
        refresh()
        selection = state.preset ?? .osDefault
    }

}
