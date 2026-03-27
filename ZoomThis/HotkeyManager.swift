import Carbon.HIToolbox
import AppKit
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ZoomThis", category: "hotkey")

final class HotkeyManager {
    private struct Registration {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let callback: @Sendable () -> Void
        let hotKeyRef: EventHotKeyRef
    }

    /// FourCC signature: 'ZMTH'
    private static let hotKeySignature: OSType = 0x5A4D_5448

    private var registrations: [UInt32: Registration] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var suspendedRegistrations: [Registration] = []
    private var menuTrackingObservers: [Any] = []

    init() {
        installEventHandler()
        observeMenuTracking()
    }

    // MARK: - Public

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, callback: @escaping @Sendable () -> Void) {
        unregister(id: id)

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: id)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &ref
        )

        guard status == noErr, let ref else {
            logger.error("RegisterEventHotKey failed for id \(id), status \(status)")
            return
        }

        registrations[id] = Registration(id: id, keyCode: keyCode, modifiers: modifiers, callback: callback, hotKeyRef: ref)
    }

    func unregister(id: UInt32) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(registration.hotKeyRef)
    }

    func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.hotKeyRef)
        }
        registrations.removeAll()
        suspendedRegistrations.removeAll()
    }

    // MARK: - Menu Tracking

    private func observeMenuTracking() {
        let beginObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suspendHotkeys()
        }

        let endObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeHotkeys()
        }

        menuTrackingObservers = [beginObserver, endObserver]
    }

    private func suspendHotkeys() {
        guard suspendedRegistrations.isEmpty else { return }
        suspendedRegistrations = Array(registrations.values)
        for reg in registrations.values {
            UnregisterEventHotKey(reg.hotKeyRef)
        }
        registrations.removeAll()
    }

    private func resumeHotkeys() {
        let toRestore = suspendedRegistrations
        suspendedRegistrations.removeAll()
        for reg in toRestore {
            register(id: reg.id, keyCode: reg.keyCode, modifiers: reg.modifiers, callback: reg.callback)
        }
    }

    // MARK: - Carbon Event Handler

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr else { return err }

                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                if let reg = mgr.registrations[hotKeyID.id] {
                    reg.callback()
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        if status != noErr {
            logger.error("InstallEventHandler failed, status \(status)")
        }
    }

    deinit {
        unregisterAll()
        for observer in menuTrackingObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }
}
