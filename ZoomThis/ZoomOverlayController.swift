import AppKit
import UniformTypeIdentifiers
import os

private let overlayLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ZoomThis", category: "overlay")

enum OverlayMode {
    case panning
    case drawing
    case textInput(NSTextAlignment)
}

enum DrawingTool {
    case freehand
    case line
    case rect
    case ellipse
    case arrow
}

/// Controls the zoom overlay lifecycle and routes input events through a three-mode state machine.
///
/// State machine transitions:
/// ```
/// ┌──────────┐  left-click   ┌──────────┐   T / Shift+T   ┌───────────┐
/// │ Panning  │──────────────▶│ Drawing  │───────────────▶│ TextInput │
/// │          │◀──────────────│          │◀───────────────│           │
/// └──────────┘  right-click  └──────────┘ Return (commit) └───────────┘
///       │                         │              │
///       │ right-click / Esc       │ Esc          │ Esc
///       ▼                         ▼              ▼
///   [dismiss]                 [dismiss]       [dismiss]
/// ```
///
/// - **Panning**: mouse moves pan the viewport, scroll zooms, left-click enters drawing, right-click/Esc dismisses.
/// - **Drawing**: left-drag draws strokes (tool chosen by modifiers), right-click returns to panning, Esc dismisses.
/// - **TextInput**: keystrokes fill a text buffer, Return commits text and returns to drawing,
///   right-click commits text and returns to panning. Escape immediately exits every mode.
final class ZoomOverlayController {
    private static let escapeHotkeyID = UInt32.max
    private let escapeHotkeyManager = HotkeyManager()
    private var window: OverlayPanel?
    private var zoomView: ZoomOverlayView?
    private var localEventMonitor: Any?
    private var focusObservers: [Any] = []
    private var savePanel: NSSavePanel?
    private var onDismiss: (() -> Void)?
    private(set) var isDismissing = false
    private var animationTimer: Timer?
    private var targetZoom: CGFloat = 2.0
    private let animationDuration = 0.2
    private var animateIn = true
    private(set) var mode: OverlayMode = .panning

    private var drawingState = DrawingState()
    private let toolTipHUD = ToolTipHUD()
    private var isDragging = false
    private var dragStart: CGPoint = .zero // image coords
    private var dragCurrent: CGPoint = .zero // image coords
    private var panningMousePosition: NSPoint = .zero
    private var isCursorHidden = false
    private var activeTool: DrawingTool = .freehand
    private var lastDrawingModifiers: NSEvent.ModifierFlags = []

    // Text input state
    private var textBuffer: String = ""
    private var textInsertionPoint: CGPoint = .zero // image coords
    private var textFontSize: CGFloat = 24.0
    private var textFontName = "Helvetica"
    private var textAlignment: NSTextAlignment = .left
    private var cursorBlinkTimer: Timer?
    private var cursorVisible = true

    // Crop export
    private var isCropMode = false
    private var cropExportAction: CropExportAction = .clipboard
    private var cropStart: CGPoint = .zero
    private var cropCurrent: CGPoint = .zero
    private var isCropDragging = false

    enum CropExportAction {
        case clipboard
        case save
    }

    func show(image: CGImage, screen: NSScreen, initialZoom: CGFloat = 2.0, animateIn: Bool = true, defaultColor: NSColor = .red, defaultLineWidth: CGFloat = 3.0, defaultTextFontSize: CGFloat = 24.0, defaultTextFontName: String = "Helvetica", onDismiss: @escaping () -> Void) {
        // Safety net: tear down any prior session that wasn't fully cleaned up
        cleanup()

        self.onDismiss = onDismiss
        // Register an OS hotkey before showing anything. This remains available even when
        // AppKit routes keyboard events to another window or runs a menu's tracking loop.
        guard escapeHotkeyManager.register(id: Self.escapeHotkeyID, keyCode: 53, modifiers: 0, suspendDuringMenuTracking: false, callback: { [weak self] in
            // Carbon application-target handlers execute on the main event thread. Dismiss
            // synchronously; queuing a Task could leave it waiting behind a tracking loop.
            MainActor.assumeIsolated { self?.dismiss(animated: false) }
        }) else {
            overlayLogger.error("Zoom refused to open: the global Escape shortcut is unavailable")
            cleanup()
            return
        }
        overlayLogger.notice("Global Escape exit armed")
        self.targetZoom = initialZoom
        self.animateIn = animateIn
        self.textFontSize = defaultTextFontSize
        self.textFontName = defaultTextFontName
        drawingState.reset(color: defaultColor, lineWidth: defaultLineWidth)
        panningMousePosition = .zero
        isCropDragging = false
        textBuffer = ""
        let screenFrame = screen.frame

        let window = OverlayPanel(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // Keep system dialogs and other applications reachable even if this app stalls.
        window.level = .normal
        window.isOpaque = true
        window.hasShadow = false
        window.hidesOnDeactivate = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .black

        let zoomView = ZoomOverlayView(image: image, frame: screenFrame)
        zoomView.zoomFactor = animateIn ? 1.0 : initialZoom
        zoomView.drawingState = drawingState
        window.contentView = zoomView
        self.zoomView = zoomView
        self.window = window
        window.onCancel = { [weak self] in self?.dismiss(animated: false) }

        // Install Escape handling before activation and the entrance animation.
        startEventMonitor()
        observeFocusChanges()
        zoomView.updateMousePosition(NSEvent.mouseLocation)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(zoomView)
        overlayLogger.notice("Zoom presented: active=\(NSApp.isActive), isKey=\(window.isKeyWindow), overlayWindow=\(window.windowNumber), keyWindow=\(NSApp.keyWindow?.windowNumber ?? -1)")

        if animateIn {
            animateZoom(from: 1.0, to: targetZoom, completion: {})
        }
    }

    private func hideCursor() {
        guard !isCursorHidden else { return }
        NSCursor.hide()
        isCursorHidden = true
    }

    private func unhideCursor() {
        guard isCursorHidden else { return }
        NSCursor.unhide()
        isCursorHidden = false
    }

    private func startEventMonitor() {
        hideCursor()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDragged, .rightMouseDragged,
                       .leftMouseDown, .leftMouseUp, .rightMouseDown, .scrollWheel]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handleEvent(event)
        }
    }

    private func observeFocusChanges() {
        let center = NotificationCenter.default
        focusObservers = [
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
                // A global keyboard monitor requires Accessibility access. Remove the overlay
                // on focus loss so it cannot cover another app while receiving no keyboard input.
                overlayLogger.notice("Zoom app lost focus")
                self?.dismiss(animated: false)
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                guard let self, self.savePanel == nil else { return }
                overlayLogger.notice("Zoom window lost keyboard focus")
                self.dismiss(animated: false)
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
                guard let self, let window = self.window, !self.isDismissing, self.savePanel == nil else { return }
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(self.zoomView)
            }
        ]
    }

    private func removeFocusObservers() {
        for observer in focusObservers { NotificationCenter.default.removeObserver(observer) }
        focusObservers.removeAll()
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown, event.keyCode == 53 {
            overlayLogger.notice("Local Escape: eventWindow=\(event.window?.windowNumber ?? -1), keyWindow=\(NSApp.keyWindow?.windowNumber ?? -1)")
        }
        guard let window, (event.window ?? NSApp.keyWindow) === window else { return event }
        if event.type == .keyDown, event.keyCode == 53 {
            dismiss(animated: false)
            return nil
        }
        // Escape is available during animation; other input waits for a stable viewport.
        guard animationTimer == nil else { return nil }
        switch mode {
        case .panning:
            return handlePanningEvent(event)
        case .drawing:
            return handleDrawingEvent(event)
        case .textInput:
            return handleTextInputEvent(event)
        }
    }

    // MARK: - Coordinate Conversion

    private func imagePoint(from screenPoint: NSPoint) -> CGPoint? {
        guard let zoomView else { return nil }
        let viewPoint = zoomView.viewPoint(fromScreen: screenPoint)
        return zoomView.imagePoint(from: viewPoint)
    }

    // MARK: - Panning Mode
    // Contract: mouse moves update the viewport center, scroll adjusts zoom,
    // left-click transitions to drawing, right-click/Esc dismisses the overlay.

    private func handlePanningEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            return handlePanningKeyDown(event)
        case .scrollWheel:
            adjustZoom(event)
            return nil
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            zoomView?.updateMousePosition(NSEvent.mouseLocation)
            return event
        case .leftMouseDown:
            enterDrawingMode()
            return nil
        case .rightMouseDown:
            dismiss()
            return nil
        default:
            return event
        }
    }

    private func handlePanningKeyDown(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 126: // Up arrow
            adjustZoomByStep(0.5)
            return nil
        case 125: // Down arrow
            adjustZoomByStep(-0.5)
            return nil
        default:
            return event
        }
    }

    // MARK: - Drawing Mode
    // Contract: left-drag draws the active tool (modifier keys select tool),
    // scroll zooms (Ctrl+scroll adjusts line width), right-click returns to panning,
    // Esc dismisses, T enters text input.

    private func handleDrawingEvent(_ event: NSEvent) -> NSEvent? {
        if isCropMode {
            return handleCropEvent(event)
        }

        switch event.type {
        case .keyDown:
            return handleDrawingKeyDown(event)
        case .leftMouseDown:
            return handleDrawingMouseDown(event)
        case .leftMouseDragged:
            return handleDrawingMouseDrag(event)
        case .leftMouseUp:
            return handleDrawingMouseUp(event)
        case .flagsChanged:
            handleDrawingFlagsChanged(event)
            return event
        case .mouseMoved:
            zoomView?.updateCursorDotPosition(NSEvent.mouseLocation)
            return event
        case .rightMouseDown:
            returnToPanningMode()
            return nil
        case .scrollWheel:
            if event.modifierFlags.contains(.control) {
                adjustLineWidth(event)
            } else {
                adjustZoom(event)
            }
            updateCursorDot()
            return nil
        default:
            return event
        }
    }

    private func handleDrawingKeyDown(_ event: NSEvent) -> NSEvent? {
        let mods = event.modifierFlags

        // Ctrl+Z → undo
        if mods.contains(.command) && event.keyCode == 6 { // Cmd+Z
            drawingState.undo()
            zoomView?.needsDisplay = true
            return nil
        }
        if mods.contains(.control) && event.keyCode == 6 { // Ctrl+Z
            drawingState.undo()
            zoomView?.needsDisplay = true
            return nil
        }

        // Ctrl+C → copy to clipboard
        if mods.contains(.control) && event.keyCode == 8 {
            if mods.contains(.shift) {
                startCropExport(.clipboard)
            } else {
                exportToClipboard()
            }
            return nil
        }
        // Ctrl+S → save
        if mods.contains(.control) && event.keyCode == 1 {
            if mods.contains(.shift) {
                startCropExport(.save)
            } else {
                exportSave()
            }
            return nil
        }

        let isShift = mods.contains(.shift)

        switch event.keyCode {
        case 15: // R
            drawingState.currentColor = isShift ? NSColor.red.withAlphaComponent(0.3) : .red
            drawingState.isBlurMode = false
            updateCursorDot()
            showColorHUD(name: "Red", isHighlight: isShift)
            return nil
        case 5: // G
            drawingState.currentColor = isShift ? NSColor.green.withAlphaComponent(0.3) : .green
            drawingState.isBlurMode = false
            updateCursorDot()
            showColorHUD(name: "Green", isHighlight: isShift)
            return nil
        case 11: // B
            drawingState.currentColor = isShift ? NSColor.blue.withAlphaComponent(0.3) : .blue
            drawingState.isBlurMode = false
            updateCursorDot()
            showColorHUD(name: "Blue", isHighlight: isShift)
            return nil
        case 16: // Y
            drawingState.currentColor = isShift ? NSColor.yellow.withAlphaComponent(0.3) : .yellow
            drawingState.isBlurMode = false
            updateCursorDot()
            showColorHUD(name: "Yellow", isHighlight: isShift)
            return nil
        case 31: // O
            drawingState.currentColor = isShift ? NSColor.orange.withAlphaComponent(0.3) : .orange
            drawingState.isBlurMode = false
            updateCursorDot()
            showColorHUD(name: "Orange", isHighlight: isShift)
            return nil
        case 35: // P
            drawingState.currentColor = isShift ? NSColor.systemPink.withAlphaComponent(0.3) : .systemPink
            drawingState.isBlurMode = false
            updateCursorDot()
            showColorHUD(name: "Pink", isHighlight: isShift)
            return nil
        case 7: // X → blur mode
            drawingState.isBlurMode = true
            updateCursorDot()
            showBlurHUD()
            return nil
        case 14: // E → erase all
            drawingState.actions.append(.eraseAll)
            zoomView?.needsDisplay = true
            return nil
        case 13: // W → whiteboard
            drawingState.actions.append(.whiteboard)
            zoomView?.needsDisplay = true
            return nil
        case 40: // K → blackboard
            drawingState.actions.append(.blackboard)
            zoomView?.needsDisplay = true
            return nil
        case 17: // T → text input
            if isShift {
                enterTextInputMode(.right)
            } else {
                enterTextInputMode(.left)
            }
            return nil
        case 49: // Space → center cursor
            centerCursor()
            return nil
        case 126: // Up arrow
            if mods.contains(.control) {
                drawingState.currentLineWidth = min(drawingState.currentLineWidth + 1, 30)
                updateCursorDot()
            } else {
                adjustZoomByStep(0.5)
                updateCursorDot()
            }
            return nil
        case 125: // Down arrow
            if mods.contains(.control) {
                drawingState.currentLineWidth = max(drawingState.currentLineWidth - 1, 1)
                updateCursorDot()
            } else {
                adjustZoomByStep(-0.5)
                updateCursorDot()
            }
            return nil
        default:
            return event
        }
    }

    private func toolFromModifiers(_ flags: NSEvent.ModifierFlags) -> DrawingTool {
        if flags.contains(.shift) && flags.contains(.control) {
            return .arrow
        } else if flags.contains(.shift) {
            return .line
        } else if flags.contains(.control) {
            return .rect
        } else if flags.contains(.option) {
            return .ellipse
        }
        return .freehand
    }

    private func handleDrawingFlagsChanged(_ event: NSEvent) {
        guard !isDragging else { return }
        let relevant: NSEvent.ModifierFlags = [.shift, .control, .option]
        let current = event.modifierFlags.intersection(relevant)
        let previous = lastDrawingModifiers
        lastDrawingModifiers = current

        // Only show HUD when modifiers are being pressed, not released
        guard !current.isEmpty, current.rawValue > previous.rawValue else { return }

        let tool = toolFromModifiers(event.modifierFlags)
        switch tool {
        case .line:
            toolTipHUD.show(content: .tool(name: "Line", sfSymbol: "line.diagonal"))
        case .rect:
            toolTipHUD.show(content: .tool(name: "Rectangle", sfSymbol: "rectangle"))
        case .ellipse:
            toolTipHUD.show(content: .tool(name: "Ellipse", sfSymbol: "circle"))
        case .arrow:
            toolTipHUD.show(content: .tool(name: "Arrow", sfSymbol: "arrow.up.left"))
        case .freehand:
            break
        }
    }

    private func showColorHUD(name: String, isHighlight: Bool) {
        let displayName = isHighlight ? "\(name) Highlight" : name
        let color = drawingState.currentColor
        toolTipHUD.show(content: .color(name: displayName, color: color))
    }

    private func showBlurHUD() {
        toolTipHUD.show(content: .color(name: "Blur", color: .gray))
    }

    private func handleDrawingMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let imgPt = imagePoint(from: NSEvent.mouseLocation) else { return nil }
        isDragging = true
        activeTool = toolFromModifiers(event.modifierFlags)
        zoomView?.inProgressAction = nil
        dragStart = imgPt
        dragCurrent = imgPt
        drawingState.inProgressPoints = [imgPt]
        return nil
    }

    private func handleDrawingMouseDrag(_ event: NSEvent) -> NSEvent? {
        guard isDragging, let imgPt = imagePoint(from: NSEvent.mouseLocation) else { return nil }
        zoomView?.updateCursorDotPosition(NSEvent.mouseLocation)
        dragCurrent = imgPt
        drawingState.inProgressPoints.append(imgPt)

        if event.type == .leftMouseDragged {
            activeTool = toolFromModifiers(event.modifierFlags)
        }
        let color = drawingState.currentColor
        let lineWidth = drawingState.currentLineWidth

        switch activeTool {
        case .freehand:
            if drawingState.isBlurMode {
                zoomView?.inProgressAction = .blur(points: drawingState.inProgressPoints, lineWidth: lineWidth)
            } else {
                zoomView?.inProgressAction = .freehand(points: drawingState.inProgressPoints, color: color, lineWidth: lineWidth)
            }
        case .line:
            zoomView?.inProgressAction = .line(from: dragStart, to: imgPt, color: color, lineWidth: lineWidth)
        case .rect:
            let origin = CGPoint(x: min(dragStart.x, imgPt.x), y: min(dragStart.y, imgPt.y))
            let size = CGSize(width: abs(imgPt.x - dragStart.x), height: abs(imgPt.y - dragStart.y))
            zoomView?.inProgressAction = .rect(origin: origin, size: size, color: color, lineWidth: lineWidth)
        case .ellipse:
            let origin = CGPoint(x: min(dragStart.x, imgPt.x), y: min(dragStart.y, imgPt.y))
            let size = CGSize(width: abs(imgPt.x - dragStart.x), height: abs(imgPt.y - dragStart.y))
            zoomView?.inProgressAction = .ellipse(origin: origin, size: size, color: color, lineWidth: lineWidth)
        case .arrow:
            zoomView?.inProgressAction = .arrow(from: dragStart, to: imgPt, color: color, lineWidth: lineWidth)
        }

        zoomView?.needsDisplay = true
        return nil
    }

    private func handleDrawingMouseUp(_ event: NSEvent) -> NSEvent? {
        guard isDragging else { return nil }
        // Include the release location, including a click with no drag events.
        _ = handleDrawingMouseDrag(event)
        isDragging = false

        let color = drawingState.currentColor
        let lineWidth = drawingState.currentLineWidth

        let action: DrawingAction?
        switch activeTool {
        case .freehand:
            if drawingState.isBlurMode {
                action = .blur(points: drawingState.inProgressPoints, lineWidth: lineWidth)
            } else {
                action = .freehand(points: drawingState.inProgressPoints, color: color, lineWidth: lineWidth)
            }
        case .line:
            action = .line(from: dragStart, to: dragCurrent, color: color, lineWidth: lineWidth)
        case .rect:
            let origin = CGPoint(x: min(dragStart.x, dragCurrent.x), y: min(dragStart.y, dragCurrent.y))
            let size = CGSize(width: abs(dragCurrent.x - dragStart.x), height: abs(dragCurrent.y - dragStart.y))
            action = .rect(origin: origin, size: size, color: color, lineWidth: lineWidth)
        case .ellipse:
            let origin = CGPoint(x: min(dragStart.x, dragCurrent.x), y: min(dragStart.y, dragCurrent.y))
            let size = CGSize(width: abs(dragCurrent.x - dragStart.x), height: abs(dragCurrent.y - dragStart.y))
            action = .ellipse(origin: origin, size: size, color: color, lineWidth: lineWidth)
        case .arrow:
            action = .arrow(from: dragStart, to: dragCurrent, color: color, lineWidth: lineWidth)
        }

        if let action {
            drawingState.actions.append(action)
        }

        drawingState.inProgressPoints.removeAll()
        drawingState.inProgressOrigin = nil
        zoomView?.inProgressAction = nil
        zoomView?.needsDisplay = true
        return nil
    }

    // MARK: - Text Input Mode
    // Contract: keystrokes append to a text buffer shown as a live preview,
    // Escape exits zoom, Return commits the text and returns to drawing, right-click commits and returns to panning,
    // left-click commits current text and starts a new text entry at the click location.

    private func enterTextInputMode(_ alignment: NSTextAlignment) {
        textAlignment = alignment
        textBuffer = ""
        cursorVisible = true
        hideCursorDot()
        hideCursor()

        // Use current mouse position as insertion point
        if let imgPt = imagePoint(from: NSEvent.mouseLocation) {
            textInsertionPoint = imgPt
        }

        mode = .textInput(alignment)
        startCursorBlink()
        updateTextPreview()
    }

    private func handleTextInputEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            return handleTextKeyDown(event)
        case .leftMouseDown:
            // Commit current text and return to drawing
            commitText()
            mode = .drawing
            stopCursorBlink()
            updateCursorDot()
            return nil
        case .mouseMoved:
            zoomView?.updateCursorDotPosition(NSEvent.mouseLocation)
            return event
        case .scrollWheel:
            if event.modifierFlags.contains(.control) {
                let delta: CGFloat = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 10.0 : event.scrollingDeltaY
                textFontSize = max(8, min(textFontSize + delta, 200))
                updateTextPreview()
            }
            return nil
        case .rightMouseDown:
            commitText()
            returnToPanningMode()
            return nil
        default:
            return event
        }
    }

    private func handleTextKeyDown(_ event: NSEvent) -> NSEvent? {
        let mods = event.modifierFlags

        // Ctrl+Z → undo
        if (mods.contains(.control) || mods.contains(.command)) && event.keyCode == 6 {
            drawingState.undo()
            zoomView?.needsDisplay = true
            return nil
        }

        // Ctrl+C → copy
        if mods.contains(.control) && event.keyCode == 8 {
            if mods.contains(.shift) {
                finishTextInput()
                startCropExport(.clipboard)
            } else {
                finishTextInput()
                exportToClipboard()
            }
            return nil
        }
        // Ctrl+S → save
        if mods.contains(.control) && event.keyCode == 1 {
            if mods.contains(.shift) {
                finishTextInput()
                startCropExport(.save)
            } else {
                finishTextInput()
                exportSave()
            }
            return nil
        }

        switch event.keyCode {
        case 51: // Backspace
            if !textBuffer.isEmpty {
                textBuffer.removeLast()
                updateTextPreview()
            }
            return nil
        case 36: // Return → commit text and return to drawing
            commitText()
            mode = .drawing
            stopCursorBlink()
            updateCursorDot()
            return nil
        case 126: // Up arrow
            if mods.contains(.control) {
                textFontSize = min(textFontSize + 2, 200)
                updateTextPreview()
            }
            return nil
        case 125: // Down arrow
            if mods.contains(.control) {
                textFontSize = max(textFontSize - 2, 8)
                updateTextPreview()
            }
            return nil
        default:
            // Regular character input
            if let chars = event.characters, !chars.isEmpty, !mods.contains(.control), !mods.contains(.command) {
                textBuffer.append(chars)
                updateTextPreview()
            }
            return nil
        }
    }

    private func finishTextInput() {
        commitText()
        mode = .drawing
        updateCursorDot()
    }

    private func commitText() {
        stopCursorBlink()
        guard !textBuffer.isEmpty else {
            zoomView?.inProgressAction = nil
            return
        }
        let font = NSFont(name: textFontName, size: textFontSize) ?? NSFont.systemFont(ofSize: textFontSize)
        let action = DrawingAction.text(
            string: textBuffer,
            position: textInsertionPoint,
            font: font,
            color: drawingState.currentColor,
            alignment: textAlignment
        )
        drawingState.actions.append(action)
        textBuffer = ""
        zoomView?.inProgressAction = nil
        zoomView?.needsDisplay = true
    }

    private func updateTextPreview() {
        let displayText = textBuffer + (cursorVisible ? "|" : " ")
        let font = NSFont(name: textFontName, size: textFontSize) ?? NSFont.systemFont(ofSize: textFontSize)
        zoomView?.inProgressAction = .text(
            string: displayText,
            position: textInsertionPoint,
            font: font,
            color: drawingState.currentColor,
            alignment: textAlignment
        )
        zoomView?.needsDisplay = true
    }

    private func startCursorBlink() {
        cursorVisible = true
        cursorBlinkTimer?.invalidate()
        cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.cursorVisible.toggle()
            self.updateTextPreview()
        }
    }

    private func stopCursorBlink() {
        cursorBlinkTimer?.invalidate()
        cursorBlinkTimer = nil
    }

    // MARK: - Crop Export

    private func startCropExport(_ action: CropExportAction) {
        mode = .drawing
        isCropMode = true
        cropExportAction = action
        isCropDragging = false
        toolTipHUD.hide()
        hideCursorDot()
        unhideCursor()
        NSCursor.crosshair.set()
    }

    private func handleCropEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .rightMouseDown:
            isCropMode = false
            isCropDragging = false
            zoomView?.cropSelection = nil
            hideCursor()
            updateCursorDot()
            return nil
        case .keyDown:
            return event
        case .leftMouseDown:
            if let imgPt = imagePoint(from: NSEvent.mouseLocation) {
                cropStart = imgPt
                cropCurrent = imgPt
                isCropDragging = true
            }
            return nil
        case .leftMouseDragged:
            if isCropDragging, let imgPt = imagePoint(from: NSEvent.mouseLocation) {
                cropCurrent = imgPt
                let origin = CGPoint(x: min(cropStart.x, cropCurrent.x), y: min(cropStart.y, cropCurrent.y))
                let size = CGSize(width: abs(cropCurrent.x - cropStart.x), height: abs(cropCurrent.y - cropStart.y))
                zoomView?.cropSelection = CGRect(origin: origin, size: size)
                zoomView?.needsDisplay = true
            }
            return nil
        case .leftMouseUp:
            if isCropDragging {
                isCropDragging = false
                let origin = CGPoint(x: min(cropStart.x, cropCurrent.x), y: min(cropStart.y, cropCurrent.y))
                let size = CGSize(width: abs(cropCurrent.x - cropStart.x), height: abs(cropCurrent.y - cropStart.y))
                let cropRect = CGRect(origin: origin, size: size)
                isCropMode = false
                zoomView?.cropSelection = nil
                zoomView?.needsDisplay = true

                hideCursor()
                updateCursorDot()
                switch cropExportAction {
                case .clipboard:
                    exportRegionToClipboard(cropRect)
                case .save:
                    exportRegionSave(cropRect)
                }
            }
            return nil
        case .mouseMoved:
            return event
        default:
            return event
        }
    }

    // MARK: - Export

    private func exportToClipboard() {
        guard let zoomView else { return }
        guard let image = zoomView.renderCurrentViewToImage() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    private func exportSave() {
        guard let zoomView else { return }
        guard let image = zoomView.renderCurrentViewToImage() else { return }
        savePNG(image: image)
    }

    private func exportRegionToClipboard(_ region: CGRect) {
        guard let zoomView else { return }
        guard let image = zoomView.renderImageRegion(region) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    private func exportRegionSave(_ region: CGRect) {
        guard let zoomView else { return }
        guard let image = zoomView.renderImageRegion(region) else { return }
        savePNG(image: image)
    }

    private func savePNG(image: NSImage) {
        guard savePanel == nil else { return }
        unhideCursor()
        hideCursorDot()
        toolTipHUD.hide()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "ZoomThis Screenshot.png"
        panel.level = .modalPanel
        savePanel = panel
        panel.begin { [weak self] response in
            defer {
                self?.savePanel = nil
                if let self, let window = self.window, !self.isDismissing {
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(self.zoomView)
                    self.hideCursor()
                    self.updateCursorDot()
                }
            }
            guard response == .OK, let url = panel.url else { return }
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return }
            do {
                try png.write(to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to save screenshot"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    // MARK: - Mode Transitions

    private func enterDrawingMode() {
        panningMousePosition = NSEvent.mouseLocation
        zoomView?.updateCursorDotPosition(panningMousePosition)
        mode = .drawing
        hideCursor()
        updateCursorDot()
    }

    private func returnToPanningMode() {
        mode = .panning
        isDragging = false
        drawingState.inProgressPoints.removeAll()
        drawingState.inProgressOrigin = nil
        zoomView?.inProgressAction = nil
        toolTipHUD.hide()
        hideCursorDot()
        hideCursor()
        // Warp cursor back to where it was when drawing mode was entered.
        // The cursor is hidden so the warp is invisible to the user.
        let flippedY = NSScreen.screens.first.map { $0.frame.maxY - panningMousePosition.y } ?? panningMousePosition.y
        CGWarpMouseCursorPosition(CGPoint(x: panningMousePosition.x, y: flippedY))
        zoomView?.updateMousePosition(panningMousePosition)
    }

    // MARK: - Cursor Dot

    private func updateCursorDot() {
        guard let zoomView else { return }
        let screenDiameter = drawingState.currentLineWidth * zoomView.zoomFactor
            * zoomView.bounds.width / CGFloat(zoomView.image.width)
        zoomView.cursorDotDiameter = max(screenDiameter, 6)
        if drawingState.isBlurMode {
            zoomView.cursorDotColor = NSColor.gray.withAlphaComponent(0.5)
        } else {
            zoomView.cursorDotColor = drawingState.currentColor
        }
        zoomView.showCursorDot = true
    }

    private func hideCursorDot() {
        zoomView?.showCursorDot = false
    }

    // MARK: - Zoom

    private func adjustZoom(_ event: NSEvent) {
        guard let zoomView else { return }
        let delta: CGFloat
        if event.hasPreciseScrollingDeltas {
            delta = event.scrollingDeltaY / 100.0
        } else {
            delta = event.scrollingDeltaY * 0.1
        }
        let newZoom = max(1.0, min(zoomView.zoomFactor + delta, 10.0))
        zoomView.zoomFactor = newZoom
    }

    private func adjustZoomByStep(_ step: CGFloat) {
        guard let zoomView else { return }
        let newZoom = max(1.0, min(zoomView.zoomFactor + step, 10.0))
        zoomView.zoomFactor = newZoom
    }

    private func adjustLineWidth(_ event: NSEvent) {
        let delta: CGFloat
        if event.hasPreciseScrollingDeltas {
            delta = event.scrollingDeltaY / 10.0
        } else {
            delta = event.scrollingDeltaY
        }
        drawingState.currentLineWidth = max(1, min(drawingState.currentLineWidth + delta, 30))
    }

    private func centerCursor() {
        guard let window else { return }
        let center = NSPoint(
            x: window.frame.midX,
            y: window.frame.midY
        )
        let flippedY = NSScreen.screens.first.map { $0.frame.maxY - center.y } ?? center.y
        CGWarpMouseCursorPosition(CGPoint(x: center.x, y: flippedY))
        zoomView?.updateCursorDotPosition(center)
    }

    // MARK: - Dismiss

    func dismiss(animated: Bool = true) {
        guard window != nil else { return }
        if isDismissing {
            if !animated { cleanup() }
            return
        }
        isDismissing = true

        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        let currentZoom = zoomView?.zoomFactor ?? targetZoom
        if animateIn && animated {
            animateZoom(from: currentZoom, to: 1.0) { [weak self] in
                self?.cleanup()
            }
        } else {
            cleanup()
        }
    }

    private func animateZoom(from startZoom: CGFloat, to endZoom: CGFloat, completion: @escaping () -> Void) {
        animationTimer?.invalidate()
        let startTime = CACurrentMediaTime()

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); completion(); return }

            let progress = min((CACurrentMediaTime() - startTime) / self.animationDuration, 1.0)
            let eased = 1.0 - (1.0 - progress) * (1.0 - progress)
            self.zoomView?.zoomFactor = startZoom + (endZoom - startZoom) * CGFloat(eased)

            if progress >= 1.0 {
                timer.invalidate()
                self.animationTimer = nil
                completion()
            }
        }
        // Run in .common modes so the timer fires during menu tracking too
        RunLoop.current.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func cleanup() {
        escapeHotkeyManager.unregister(id: Self.escapeHotkeyID)
        animationTimer?.invalidate()
        animationTimer = nil

        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        removeFocusObservers()

        stopCursorBlink()
        toolTipHUD.teardown()
        unhideCursor()

        window?.onCancel = nil
        window?.orderOut(nil)
        window = nil
        zoomView = nil
        let pendingSave = savePanel
        savePanel = nil
        pendingSave?.cancel(nil)

        mode = .panning
        isDismissing = false
        isDragging = false
        isCropMode = false
        lastDrawingModifiers = []

        let callback = onDismiss
        onDismiss = nil
        if callback != nil { overlayLogger.notice("Zoom overlay removed and Escape released") }
        callback?()
    }
}
