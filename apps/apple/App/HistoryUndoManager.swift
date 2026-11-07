import AppKit

final class HistoryUndoManager: UndoManager {
    private var next: HistoryEntry? {
        MainActor.assumeIsolated { TaskQueue.shared.history.nextUndo }
    }

    override var canUndo: Bool { next != nil }

    override var canRedo: Bool { false }

    override var undoActionName: String { next?.undoActionName ?? "" }

    override var undoMenuItemTitle: String { undoMenuTitle(forUndoActionName: undoActionName) }

    override func undo() {
        MainActor.assumeIsolated { FileActions.undoLatest() }
    }
}
