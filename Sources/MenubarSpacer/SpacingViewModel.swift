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

    init(coordinator: SpacingCoordinator) {
        self.coordinator = coordinator
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
            message = OutcomeMessage.apply(try coordinator.apply(selection))
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

}
