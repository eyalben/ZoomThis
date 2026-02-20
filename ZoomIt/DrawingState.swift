import AppKit

final class DrawingState {
    var actions: [DrawingAction] = []
    var currentColor: NSColor = .red
    var currentLineWidth: CGFloat = 3.0
    var isBlurMode = false

    // In-progress tracking for freehand
    var inProgressPoints: [CGPoint] = []
    // In-progress tracking for shapes
    var inProgressOrigin: CGPoint?

    func undo() {
        guard !actions.isEmpty else { return }
        actions.removeLast()
    }

    func reset() {
        actions.removeAll()
        inProgressPoints.removeAll()
        inProgressOrigin = nil
        currentColor = .red
        currentLineWidth = 3.0
        isBlurMode = false
    }

    func reset(color: NSColor, lineWidth: CGFloat) {
        actions.removeAll()
        inProgressPoints.removeAll()
        inProgressOrigin = nil
        currentColor = color
        currentLineWidth = lineWidth
        isBlurMode = false
    }
}
