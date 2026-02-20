import AppKit

final class BreakTimerController {
    private var window: NSWindow?
    private var timerView: BreakTimerView?
    private var countdownTimer: Timer?
    private var localEventMonitor: Any?
    private var onDismiss: (() -> Void)?
    private var resignObserver: Any?

    private(set) var remainingSeconds: Int = 0
    private(set) var isActive = false
    private(set) var isMinimized = false

    func show(duration: TimeInterval, onDismiss: @escaping () -> Void) {
        guard !isActive else { return }
        // Resolve screen before mutating state to avoid stuck isActive on early return
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else { return }
        self.onDismiss = onDismiss
        remainingSeconds = Int(duration)
        isActive = true
        isMinimized = false
        let screenFrame = screen.frame

        let window = OverlayPanel(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .black

        let timerView = BreakTimerView(frame: screenFrame)
        timerView.remainingSeconds = remainingSeconds
        window.contentView = timerView
        self.timerView = timerView
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        startCountdown()
        startEventMonitor()

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.minimize()
        }
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.remainingSeconds -= 1
            self.timerView?.remainingSeconds = self.remainingSeconds
            if self.remainingSeconds <= 0 {
                self.dismiss()
            }
        }
    }

    private func startEventMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .scrollWheel]
        ) { [weak self] event in
            self?.handleEvent(event)
        }
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            if event.keyCode == 53 { // Escape
                dismiss()
                return nil
            }
            switch event.keyCode {
            case 126: // Up arrow
                adjustTime(event.modifierFlags.contains(.control) ? 30 : 10)
                return nil
            case 125: // Down arrow
                adjustTime(event.modifierFlags.contains(.control) ? -30 : -10)
                return nil
            default:
                return event
            }
        case .scrollWheel:
            let seconds: Int
            if event.modifierFlags.contains(.control) {
                seconds = event.scrollingDeltaY > 0 ? 30 : -30
            } else {
                seconds = event.scrollingDeltaY > 0 ? 10 : -10
            }
            adjustTime(seconds)
            return nil
        default:
            return event
        }
    }

    private func adjustTime(_ delta: Int) {
        remainingSeconds = max(0, remainingSeconds + delta)
        timerView?.remainingSeconds = remainingSeconds
        if remainingSeconds <= 0 {
            dismiss()
        }
    }

    func minimize() {
        guard isActive, !isMinimized else { return }
        isMinimized = true
        window?.orderOut(nil)
    }

    func restore() {
        guard isActive, isMinimized else { return }
        isMinimized = false
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func dismiss() {
        countdownTimer?.invalidate()
        countdownTimer = nil

        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }

        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
            resignObserver = nil
        }

        window?.orderOut(nil)
        window = nil
        timerView = nil
        isActive = false
        isMinimized = false

        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}
