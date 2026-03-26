import AppKit
import os

final class HotkeyManager {
    private struct Registration {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let callback: @Sendable () -> Void
    }

    private var registrations: [Registration] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var globalMonitorScheduled = false

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, callback: @escaping @Sendable () -> Void) {
        unregister(id: id)
        registrations.append(Registration(id: id, keyCode: keyCode, modifiers: modifiers, callback: callback))
        installLocalMonitorIfNeeded()
        scheduleGlobalMonitorIfNeeded()
    }

    func unregister(id: UInt32) {
        registrations.removeAll { $0.id == id }
        if registrations.isEmpty {
            removeMonitors()
        }
    }

    func unregisterAll() {
        registrations.removeAll()
        removeMonitors()
    }

    private func installLocalMonitorIfNeeded() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil
            }
            return event
        }
    }

    private func scheduleGlobalMonitorIfNeeded() {
        guard globalMonitor == nil, !globalMonitorScheduled else { return }
        globalMonitorScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.installGlobalMonitor()
        }
    }

    private func installGlobalMonitor() {
        globalMonitorScheduled = false
        guard globalMonitor == nil, !registrations.isEmpty else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }

    private func removeMonitors() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        globalMonitorScheduled = false
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let keyCode = UInt32(event.keyCode)
        let modifiers = cocoaToCarbonModifiers(event.modifierFlags)

        for reg in registrations where reg.keyCode == keyCode && reg.modifiers == modifiers {
            reg.callback()
            return true
        }
        return false
    }

    deinit {
        unregisterAll()
    }
}
