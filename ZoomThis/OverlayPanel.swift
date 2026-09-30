import AppKit

final class OverlayPanel: NSPanel {
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelOperation(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        guard let onCancel else {
            super.cancelOperation(sender)
            return
        }
        onCancel()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
