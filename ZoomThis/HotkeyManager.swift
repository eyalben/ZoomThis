import Carbon
import os

final class HotkeyManager {
    private var eventHandlerRef: EventHandlerRef?
    private var registrations: [(id: UInt32, ref: EventHotKeyRef)] = []

    nonisolated private static let lock = OSAllocatedUnfairLock<[UInt32: @Sendable () -> Void]>(initialState: [:])

    nonisolated static func setCallback(_ callback: (@Sendable () -> Void)?, for id: UInt32) {
        lock.withLock { $0[id] = callback }
    }

    nonisolated static func callback(for id: UInt32) -> (@Sendable () -> Void)? {
        lock.withLock { $0[id] }
    }

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, callback: @escaping @Sendable () -> Void) {
        unregister(id: id)
        HotkeyManager.setCallback(callback, for: id)

        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: 0x5A4D_4954, id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let ref = hotKeyRef {
            registrations.append((id: id, ref: ref))
        }
    }

    func unregister(id: UInt32) {
        if let index = registrations.firstIndex(where: { $0.id == id }) {
            UnregisterEventHotKey(registrations[index].ref)
            registrations.remove(at: index)
        }
        HotkeyManager.setCallback(nil, for: id)

        if registrations.isEmpty {
            removeHandler()
        }
    }

    func unregisterAll() {
        for reg in registrations {
            UnregisterEventHotKey(reg.ref)
            HotkeyManager.setCallback(nil, for: reg.id)
        }
        registrations.removeAll()
        removeHandler()
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func removeHandler() {
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }

    deinit {
        unregisterAll()
    }
}

private nonisolated func hotkeyEventHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    _: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return OSStatus(eventNotHandledErr) }
    HotkeyManager.callback(for: hotKeyID.id)?()
    return noErr
}
