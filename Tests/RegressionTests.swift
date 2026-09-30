import AppKit
import Carbon.HIToolbox

@main
struct RegressionTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var failures = 0
        func check(_ name: String, _ body: () -> Bool) {
            if body() { print("PASS: \(name)") }
            else { print("FAIL: \(name)"); failures += 1 }
        }
        func image(_ color: NSColor) -> CGImage {
            let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            return ctx.makeImage()!
        }
        func bitmap(_ image: NSImage?) -> NSBitmapImageRep? {
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return NSBitmapImageRep(cgImage: cg)
        }
        func colorIs(_ bitmap: NSBitmapImageRep?, _ color: NSColor) -> Bool {
            guard let actual = bitmap?.colorAt(x: 50, y: 50)?.usingColorSpace(.deviceRGB),
                  let expected = color.usingColorSpace(.deviceRGB) else { return false }
            return abs(actual.redComponent - expected.redComponent) < 0.03
                && abs(actual.greenComponent - expected.greenComponent) < 0.03
                && abs(actual.blueComponent - expected.blueComponent) < 0.03
                && abs(actual.alphaComponent - expected.alphaComponent) < 0.03
        }
        let drawing = DrawingState()
        let view = ZoomOverlayView(image: image(.blue), frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.zoomFactor = 1
        view.drawingState = drawing
        drawing.actions = [.blackboard, .eraseAll]
        check("Erase-all export preserves opaque source image") {
            colorIs(bitmap(view.renderCurrentViewToImage()), .blue)
        }
        check("Cropped erase-all export preserves source image") {
            colorIs(bitmap(view.renderImageRegion(CGRect(x: 0, y: 0, width: 100, height: 100))), .blue)
        }
        drawing.undo()
        check("Undoing erase restores the board in export") {
            colorIs(bitmap(view.renderCurrentViewToImage()), .black)
        }
        func renderedView() -> NSBitmapImageRep {
            let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            view.draw(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
            return NSBitmapImageRep(cgImage: ctx.makeImage()!)
        }
        _ = renderedView()
        drawing.undo()
        drawing.actions.append(.whiteboard)
        check("Undo and replacement refresh cache even at same action count") {
            colorIs(renderedView(), .white)
        }
        drawing.actions.append(.whiteboard)
        _ = renderedView()
        let replacement = DrawingState()
        replacement.actions = [.blackboard, .blackboard]
        view.drawingState = replacement
        check("Replacing drawing state invalidates cached annotations") {
            colorIs(renderedView(), .black)
        }
        let window = NSWindow(contentRect: NSRect(x: 400, y: 300, width: 100, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.setFrameOrigin(NSPoint(x: 400, y: 300))
        let screenCenter = window.convertPoint(toScreen: NSPoint(x: 50, y: 50))
        view.zoomFactor = 2
        view.updateMousePosition(screenCenter)
        check("Panning uses screen-to-window conversion away from screen origin") {
            let point = view.imagePoint(from: NSPoint(x: 50, y: 50))
            return abs(point.x - 50) < 0.01 && abs(point.y - 50) < 0.01
        }
        let textContext = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        textContext.translateBy(x: 0, y: 100)
        textContext.scaleBy(x: 1, y: -1)
        DrawingAction.text(string: "A", position: CGPoint(x: 60, y: 50), font: NSFont.systemFont(ofSize: 24),
                           color: .red, alignment: .right).render(in: textContext, imageSize: CGSize(width: 100, height: 100))
        check("Right-aligned text ends at insertion point") {
            let pixels = NSBitmapImageRep(cgImage: textContext.makeImage()!)
            var xs: [Int] = []
            for y in 0..<100 {
                for x in 0..<100 where (pixels.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { xs.append(x) }
            }
            return !xs.isEmpty && xs.max()! <= 60 && xs.min()! >= 35
        }
        // Keep temporary windows hidden while exercising the actual local event monitors.
        let settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                      styleMask: .borderless, backing: .buffered, defer: false)
        func key(_ code: UInt16, _ characters: String, in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                        characters: characters, charactersIgnoringModifiers: characters,
                                        isARepeat: false, keyCode: code)!
            NSApp.sendEvent(event)
        }
        let countdown = BreakTimerController()
        countdown.show(duration: 30) {}
        let initialSeconds = countdown.remainingSeconds
        key(126, "", in: settingsWindow)
        check("Timer ignores arrow keys in another window") { countdown.remainingSeconds == initialSeconds }
        countdown.minimize()
        key(53, "", in: settingsWindow)
        check("Minimized timer ignores Escape in Settings") { countdown.isActive }
        countdown.dismiss()
        countdown.show(duration: 30) {}
        NSApp.windows.first(where: { $0.contentView is BreakTimerView })?.orderOut(nil)
        let beforeTracking = countdown.remainingSeconds
        let trackingEnd = Date().addingTimeInterval(1.15)
        while Date() < trackingEnd {
            _ = RunLoop.main.run(mode: .eventTracking, before: trackingEnd)
        }
        check("Countdown advances during event tracking") { countdown.remainingSeconds < beforeTracking }
        let beforeDelay = countdown.remainingSeconds
        Thread.sleep(forTimeInterval: 2.1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        check("Countdown catches up after delayed timer delivery") { countdown.remainingSeconds <= beforeDelay - 2 }
        countdown.dismiss()
        countdown.show(duration: 30) {}
        let timerWindow = NSApp.windows.first { $0.contentView is BreakTimerView && $0.isVisible }!
        timerWindow.alphaValue = 0
        timerWindow.cancelOperation(nil)
        check("Timer responder cancellation dismisses without the event monitor") { !countdown.isActive }
        countdown.dismiss()
        if let screen = NSScreen.screens.first {
            let overlay = ZoomOverlayController()
            overlay.show(image: image(.blue), screen: screen, animateIn: false, defaultTextFontSize: 40) {}
            let overlayWindow = NSApp.windows.first { ($0.contentView as? ZoomOverlayView) != nil && $0.contentView !== view }!
            overlayWindow.alphaValue = 0
            let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 50, y: 50),
                                           modifierFlags: [], timestamp: 0, windowNumber: overlayWindow.windowNumber,
                                           context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            NSApp.sendEvent(click)
            key(17, "t", in: overlayWindow)
            let overlayView = overlayWindow.contentView as! ZoomOverlayView
            check("Text entry respects the configured font size") {
                if case .text(_, _, let font, _, _) = overlayView.inProgressAction { return font.pointSize == 40 }
                return false
            }
            key(15, "r", in: settingsWindow)
            check("Zoom overlay ignores text typed in another window") {
                if case .text(let text, _, _, _, _) = overlayView.inProgressAction { return !text.contains("r") }
                return false
            }
            key(8, "c", in: overlayWindow, modifiers: [.control, .shift])
            check("Crop export from text input returns to drawing mode") {
                if case .drawing = overlay.mode { return true }
                return false
            }
            key(53, "", in: overlayWindow)
            check("Escape closes the overlay while selecting a crop") { !overlayWindow.isVisible }
            overlay.dismiss()
        }
        if let screen = NSScreen.screens.first {
            func showOverlay(animated: Bool, onDismiss: @escaping () -> Void) -> (ZoomOverlayController, NSWindow) {
                let controller = ZoomOverlayController()
                controller.show(image: image(.blue), screen: screen, animateIn: animated, onDismiss: onDismiss)
                let window = NSApp.windows.first { $0.contentView is ZoomOverlayView && $0.contentView !== view && $0.isVisible }!
                window.alphaValue = 0
                return (controller, window)
            }
            var dismissals = 0
            var (overlay, overlayWindow) = showOverlay(animated: true) { dismissals += 1 }
            key(53, "", in: overlayWindow)
            check("Escape immediately closes the overlay during zoom-in animation") {
                dismissals == 1 && !overlayWindow.isVisible && !overlay.isDismissing
            }
            // Allow any unfinished entrance animation to fire; it must not reinstall monitors.
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            check("Cancelled zoom-in animation cannot revive the overlay") {
                dismissals == 1 && !overlayWindow.isVisible
            }
            overlay.dismiss()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))

            dismissals = 0
            (overlay, overlayWindow) = showOverlay(animated: false) { dismissals += 1 }
            let escapeEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                              timestamp: 0, windowNumber: overlayWindow.windowNumber,
                                              context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                              isARepeat: false, keyCode: 53)!
            overlayWindow.contentView!.keyDown(with: escapeEvent)
            check("Responder fallback closes zoom if Escape bypasses the monitor") {
                dismissals == 1 && !overlayWindow.isVisible
            }
            overlay.dismiss()

            dismissals = 0
            (overlay, overlayWindow) = showOverlay(animated: false) { dismissals += 1 }
            overlayWindow.cancelOperation(nil)
            check("Panel cancellation closes zoom without relying on an event monitor") {
                dismissals == 1 && !overlayWindow.isVisible
            }
            overlay.dismiss()

            dismissals = 0
            (overlay, overlayWindow) = showOverlay(animated: false) { dismissals += 1 }
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            check("Losing app focus immediately removes the overlay") {
                dismissals == 1 && !overlayWindow.isVisible
            }
            overlay.dismiss()

            dismissals = 0
            (overlay, overlayWindow) = showOverlay(animated: false) { dismissals += 1 }
            // The standalone test executable does not run NSApplication's activation loop.
            // Deliver the notification AppKit sends when another window becomes key.
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: overlayWindow)
            check("Losing keyboard focus cannot leave the zoom overlay blocking the screen") {
                dismissals == 1 && !overlayWindow.isVisible
            }
            overlay.dismiss()

            dismissals = 0
            (overlay, overlayWindow) = showOverlay(animated: false) { dismissals += 1 }
            let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                          timestamp: 0, windowNumber: overlayWindow.windowNumber, context: nil,
                                          eventNumber: 1, clickCount: 1, pressure: 1)!
            NSApp.sendEvent(click)
            key(17, "t", in: overlayWindow)
            key(53, "", in: overlayWindow)
            check("Escape exits the entire zoom mode while entering text") {
                dismissals == 1 && !overlayWindow.isVisible
            }
            overlay.dismiss()

            dismissals = 0
            (overlay, overlayWindow) = showOverlay(animated: true) { dismissals += 1 }
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            overlay.dismiss()
            overlayWindow.cancelOperation(nil)
            check("Emergency cancellation interrupts the zoom-out animation") {
                dismissals == 1 && !overlayWindow.isVisible && !overlay.isDismissing
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            check("Repeated cancellation runs dismissal cleanup only once") { dismissals == 1 }
            overlay.dismiss()
        }
        // Send a native Carbon shortcut event instead of an NSEvent. This exercises
        // the independent exit path that does not require a key window or local monitor.
        func nativeEscape(id: UInt32) -> Bool {
            var event: EventRef?
            guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(), 0, &event) == noErr,
                  let event else { return false }
            defer { ReleaseEvent(event) }
            var hotkey = EventHotKeyID(signature: 0x5A4D5448, id: id)
            guard SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    MemoryLayout<EventHotKeyID>.size, &hotkey) == noErr else { return false }
            return SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr
        }
        func escapeIsAvailable() -> Bool {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(53, 0, EventHotKeyID(signature: 0x54455354, id: 88),
                                             GetApplicationEventTarget(), 0, &ref)
            if let ref { UnregisterEventHotKey(ref) }
            return status == noErr
        }
        if let screen = NSScreen.screens.first {
            for duringMenuTracking in [false, true] {
                var dismissals = 0
                let overlay = ZoomOverlayController()
                overlay.show(image: image(.blue), screen: screen, animateIn: false) { dismissals += 1 }
                let window = NSApp.windows.first { $0.contentView is ZoomOverlayView && $0.contentView !== view && $0.isVisible }!
                window.alphaValue = 0
                check("Zoom arms a global Escape shortcut") { !escapeIsAvailable() }
                check("Zoom window does not cover system emergency dialogs") { window.level == .normal }
                if duringMenuTracking {
                    NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)
                }
                let delivered = nativeEscape(id: UInt32.max)
                check(duringMenuTracking ? "Global Escape stays available during menu tracking" : "Native Escape closes zoom without window keyboard delivery") {
                    delivered && dismissals == 1 && !window.isVisible
                }
                if duringMenuTracking {
                    NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: nil)
                }
                overlay.dismiss(animated: false)
                check("Closing zoom releases the global Escape shortcut") { escapeIsAvailable() }
            }
            var blocker: EventHotKeyRef?
            let blocked = RegisterEventHotKey(53, 0, EventHotKeyID(signature: 0x54455354, id: 89),
                                             GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &blocker) == noErr
            var dismissals = 0
            let overlay = ZoomOverlayController()
            overlay.show(image: image(.blue), screen: screen, animateIn: false) { dismissals += 1 }
            let visibleZoom = NSApp.windows.first { $0.contentView is ZoomOverlayView && $0.contentView !== view && $0.isVisible }
            visibleZoom?.alphaValue = 0
            check("Zoom refuses to open if Escape cannot be registered") { blocked && dismissals == 1 && visibleZoom == nil }
            overlay.dismiss(animated: false)
            if let blocker { UnregisterEventHotKey(blocker) }
        }
        countdown.show(duration: 30) {}
        NSApp.windows.first { $0.contentView is BreakTimerView && $0.isVisible }?.alphaValue = 0
        check("Timer arms a global Escape shortcut") { !escapeIsAvailable() }
        countdown.minimize()
        check("Minimizing timer releases global Escape for other apps") { escapeIsAvailable() }
        countdown.restore()
        NSApp.windows.first { $0.contentView is BreakTimerView && $0.isVisible }?.alphaValue = 0
        check("Restoring timer re-arms global Escape") { !escapeIsAvailable() }
        let timerEscapeDelivered = nativeEscape(id: UInt32.max - 1)
        check("Native Escape closes the timer without window keyboard delivery") { timerEscapeDelivered && !countdown.isActive }
        countdown.dismiss()
        // Probe Carbon registrations to verify menu tracking and recorder interactions.
        let hotkeys = HotkeyManager()
        let probeCode: UInt32 = 46
        let probeModifiers: UInt32 = 0x1B00
        func keyIsAvailable() -> Bool {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(probeCode, probeModifiers, EventHotKeyID(signature: 0x54535453, id: 77),
                                             GetApplicationEventTarget(), 0, &ref)
            if let ref { UnregisterEventHotKey(ref) }
            return status == noErr
        }
        hotkeys.register(id: 99, keyCode: probeCode, modifiers: probeModifiers) {}
        check("Hotkey registers before menu tracking") { !keyIsAvailable() }
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        check("Menu tracking suspends hotkeys") { keyIsAvailable() }
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: nil)
        check("Nested menu tracking keeps hotkeys suspended") { keyIsAvailable() }
        hotkeys.unregister(id: 99)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: nil)
        check("Unregister during menu tracking prevents stale restoration") { keyIsAvailable() }
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        hotkeys.register(id: 99, keyCode: probeCode, modifiers: probeModifiers) {}
        check("Register during menu tracking stays suspended") { keyIsAvailable() }
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: nil)
        check("New registration resumes when menu tracking ends") { !keyIsAvailable() }
        hotkeys.unregisterAll()
        hotkeys.register(id: 99, keyCode: probeCode, modifiers: probeModifiers) {}
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        hotkeys.unregister(id: 99)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: nil)
        check("Unregister during a single menu session removes suspended registration") { keyIsAvailable() }
        hotkeys.unregisterAll()
        print("\(failures) regression check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
