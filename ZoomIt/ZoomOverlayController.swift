import AppKit
import UniformTypeIdentifiers

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
/// └──────────┘  right-click  └──────────┘   Esc (commit)  └───────────┘
///       │                         │              │
///       │ right-click / Esc       │ Esc          │ right-click (commit)
///       ▼                         ▼              ▼
///   [dismiss]                 [dismiss]      [→ Panning]
/// ```
///
/// - **Panning**: mouse moves pan the viewport, scroll zooms, left-click enters drawing, right-click/Esc dismisses.
/// - **Drawing**: left-drag draws strokes (tool chosen by modifiers), right-click returns to panning, Esc dismisses.
/// - **TextInput**: keystrokes fill a text buffer, Esc commits text and returns to drawing,
///   right-click commits text and returns to panning.
final class ZoomOverlayController {
    private var window: NSWindow?
    private var zoomView: ZoomOverlayView?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var onDismiss: (() -> Void)?
    private var isDismissing = false
    private var targetZoom: CGFloat = 2.0
    private let animationDuration = 0.2
    private var animateIn = true
    private(set) var mode: OverlayMode = .panning

    private var drawingState = DrawingState()
    private var isDragging = false
    private var dragStart: CGPoint = .zero // image coords
    private var dragCurrent: CGPoint = .zero // image coords
    private var panningMousePosition: NSPoint = .zero
    private var isCursorHidden = false
    private var activeTool: DrawingTool = .freehand

    // Text input state
    private var textBuffer: String = ""
    private var textInsertionPoint: CGPoint = .zero // image coords
    private var textFontSize: CGFloat = 24.0
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

    func show(image: CGImage, screen: NSScreen, initialZoom: CGFloat = 2.0, animateIn: Bool = true, defaultColor: NSColor = .red, defaultLineWidth: CGFloat = 3.0, defaultTextFontSize: CGFloat = 24.0, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.targetZoom = initialZoom
        self.animateIn = animateIn
        self.textFontSize = defaultTextFontSize
        isDismissing = false
        mode = .panning
        drawingState.reset(color: defaultColor, lineWidth: defaultLineWidth)
        isDragging = false
        isCursorHidden = false
        panningMousePosition = .zero
        isCropMode = false
        isCropDragging = false
        textBuffer = ""
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

        let zoomView = ZoomOverlayView(image: image, frame: screenFrame)
        zoomView.zoomFactor = animateIn ? 1.0 : initialZoom
        zoomView.drawingState = drawingState
        window.contentView = zoomView
        self.zoomView = zoomView
        self.window = window

        zoomView.updateMousePosition(NSEvent.mouseLocation)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        if animateIn {
            animateZoom(from: 1.0, to: targetZoom) { [weak self] in
                self?.startEventMonitor()
            }
        } else {
            startEventMonitor()
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
            matching: [.keyDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged,
                       .leftMouseDown, .leftMouseUp, .rightMouseDown, .scrollWheel]
        ) { [weak self] event in
            self?.handleEvent(event) ?? event
        }
        // Global monitor catches Escape even when the app loses focus
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.dismiss()
            }
        }
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
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
        let viewPoint = NSPoint(
            x: screenPoint.x - zoomView.frame.origin.x,
            y: screenPoint.y - zoomView.frame.origin.y
        )
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
        case 53: // Escape
            dismiss()
            return nil
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
        case .mouseMoved:
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
        case 53: // Escape
            dismiss()
            return nil
        case 15: // R
            drawingState.currentColor = isShift ? NSColor.red.withAlphaComponent(0.3) : .red
            drawingState.isBlurMode = false
            return nil
        case 5: // G
            drawingState.currentColor = isShift ? NSColor.green.withAlphaComponent(0.3) : .green
            drawingState.isBlurMode = false
            return nil
        case 11: // B
            drawingState.currentColor = isShift ? NSColor.blue.withAlphaComponent(0.3) : .blue
            drawingState.isBlurMode = false
            return nil
        case 16: // Y
            drawingState.currentColor = isShift ? NSColor.yellow.withAlphaComponent(0.3) : .yellow
            drawingState.isBlurMode = false
            return nil
        case 31: // O
            drawingState.currentColor = isShift ? NSColor.orange.withAlphaComponent(0.3) : .orange
            drawingState.isBlurMode = false
            return nil
        case 35: // P
            drawingState.currentColor = isShift ? NSColor.systemPink.withAlphaComponent(0.3) : .systemPink
            drawingState.isBlurMode = false
            return nil
        case 7: // X → blur mode
            drawingState.isBlurMode = true
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
            } else {
                adjustZoomByStep(0.5)
            }
            return nil
        case 125: // Down arrow
            if mods.contains(.control) {
                drawingState.currentLineWidth = max(drawingState.currentLineWidth - 1, 1)
            } else {
                adjustZoomByStep(-0.5)
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

    private func handleDrawingMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let imgPt = imagePoint(from: NSEvent.mouseLocation) else { return nil }
        isDragging = true
        dragStart = imgPt
        dragCurrent = imgPt
        drawingState.inProgressPoints = [imgPt]
        return nil
    }

    private func handleDrawingMouseDrag(_ event: NSEvent) -> NSEvent? {
        guard isDragging, let imgPt = imagePoint(from: NSEvent.mouseLocation) else { return nil }
        dragCurrent = imgPt
        drawingState.inProgressPoints.append(imgPt)

        activeTool = toolFromModifiers(event.modifierFlags)
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
    // Esc commits the text and returns to drawing, right-click commits and returns to panning,
    // left-click commits current text and starts a new text entry at the click location.

    private func enterTextInputMode(_ alignment: NSTextAlignment) {
        textAlignment = alignment
        textBuffer = ""
        textFontSize = 24.0
        cursorVisible = true

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
            NSCursor.crosshair.set()
            return nil
        case .mouseMoved:
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
                commitText()
                startCropExport(.clipboard)
            } else {
                commitText()
                exportToClipboard()
            }
            return nil
        }
        // Ctrl+S → save
        if mods.contains(.control) && event.keyCode == 1 {
            if mods.contains(.shift) {
                commitText()
                startCropExport(.save)
            } else {
                commitText()
                exportSave()
            }
            return nil
        }

        switch event.keyCode {
        case 53: // Escape → commit text and return to drawing
            commitText()
            mode = .drawing
            stopCursorBlink()
            NSCursor.crosshair.set()
            return nil
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
            NSCursor.crosshair.set()
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

    private func commitText() {
        stopCursorBlink()
        guard !textBuffer.isEmpty else {
            zoomView?.inProgressAction = nil
            return
        }
        let font = NSFont.systemFont(ofSize: textFontSize)
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
        let font = NSFont.systemFont(ofSize: textFontSize)
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
        isCropMode = true
        cropExportAction = action
        isCropDragging = false
        NSCursor.crosshair.set()
    }

    private func handleCropEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            if event.keyCode == 53 { // Escape → cancel crop
                isCropMode = false
                zoomView?.cropSelection = nil
                zoomView?.needsDisplay = true
                return nil
            }
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
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "ZoomIt Screenshot.png"
        panel.level = .screenSaver + 1
        panel.begin { response in
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
        mode = .drawing
        unhideCursor()
        NSCursor.crosshair.set()
    }

    private func returnToPanningMode() {
        mode = .panning
        hideCursor()
        // Warp cursor back to where it was when drawing mode was entered.
        // The cursor is hidden so the warp is invisible to the user.
        let flippedY = NSScreen.main.map { $0.frame.height - panningMousePosition.y } ?? panningMousePosition.y
        CGWarpMouseCursorPosition(CGPoint(x: panningMousePosition.x, y: flippedY))
        zoomView?.updateMousePosition(panningMousePosition)
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
        let flippedY = NSScreen.main.map { $0.frame.height - center.y } ?? center.y
        CGWarpMouseCursorPosition(CGPoint(x: center.x, y: flippedY))
        zoomView?.updateMousePosition(center)
    }

    // MARK: - Dismiss

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        stopCursorBlink()
        unhideCursor()

        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }

        let currentZoom = zoomView?.zoomFactor ?? targetZoom
        if animateIn {
            animateZoom(from: currentZoom, to: 1.0) { [weak self] in
                self?.tearDown()
            }
        } else {
            tearDown()
        }
    }

    private func animateZoom(from startZoom: CGFloat, to endZoom: CGFloat, completion: @escaping () -> Void) {
        let startTime = CACurrentMediaTime()

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }

            let progress = min((CACurrentMediaTime() - startTime) / self.animationDuration, 1.0)
            let eased = 1.0 - (1.0 - progress) * (1.0 - progress)
            self.zoomView?.zoomFactor = startZoom + (endZoom - startZoom) * CGFloat(eased)

            if progress >= 1.0 {
                timer.invalidate()
                completion()
            }
        }
    }

    private func tearDown() {
        window?.orderOut(nil)
        window = nil
        zoomView = nil
        mode = .panning
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}
