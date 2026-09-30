import AppKit

final class BreakTimerController {
    private static let escapeHotkeyID = UInt32.max - 1
    private let escapeHotkeyManager = HotkeyManager()
    private var window: NSWindow?
    private var timerView: BreakTimerView?
    private var countdownTimer: Timer?
    private var deadline: Date?
    private var localEventMonitor: Any?
    private var onDismiss: (() -> Void)?
    private var resignObserver: Any?

    private(set) var remainingSeconds: Int = 0
    private(set) var isActive = false
    private(set) var isMinimized = false

    @discardableResult
    func show(duration: TimeInterval, onDismiss: @escaping () -> Void) -> Bool {
        guard !isActive, duration.isFinite, duration > 0, duration < Double(Int.max) else { return false }
        // Resolve screen before mutating state to avoid stuck isActive on early return
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else { return false }
        guard armEscapeShortcut() else { return false }
        self.onDismiss = onDismiss
        deadline = Date().addingTimeInterval(duration)
        remainingSeconds = Int(duration.rounded(.up))
        isActive = true
        isMinimized = false
        let screenFrame = screen.frame

        let window = OverlayPanel(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .normal
        window.isOpaque = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .black

        let timerView = BreakTimerView(frame: screenFrame)
        timerView.remainingSeconds = remainingSeconds
        window.contentView = timerView
        self.timerView = timerView
        self.window = window
        window.onCancel = { [weak self] in self?.dismiss() }

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
        return true
    }

    private func armEscapeShortcut() -> Bool {
        escapeHotkeyManager.register(id: Self.escapeHotkeyID, keyCode: 53, modifiers: 0, suspendDuringMenuTracking: false) { [weak self] in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateRemainingTime()
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func updateRemainingTime() {
        guard let deadline else { return }
        remainingSeconds = Int(max(0, deadline.timeIntervalSinceNow).rounded(.up))
        timerView?.remainingSeconds = remainingSeconds
        if remainingSeconds == 0 { dismiss() }
    }

    private func startEventMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .scrollWheel]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handleEvent(event)
        }
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        guard isActive, !isMinimized, let window, event.window === window else { return event }
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
            guard event.scrollingDeltaY != 0 else { return nil }
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
        guard let deadline else { return }
        self.deadline = deadline.addingTimeInterval(TimeInterval(delta))
        updateRemainingTime()
    }

    func minimize() {
        guard isActive, !isMinimized else { return }
        isMinimized = true
        escapeHotkeyManager.unregister(id: Self.escapeHotkeyID)
        window?.orderOut(nil)
    }

    func restore() {
        guard isActive, isMinimized else { return }
        updateRemainingTime()
        guard isActive, armEscapeShortcut() else { return }
        isMinimized = false
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func dismiss() {
        escapeHotkeyManager.unregister(id: Self.escapeHotkeyID)
        countdownTimer?.invalidate()
        countdownTimer = nil
        deadline = nil

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
