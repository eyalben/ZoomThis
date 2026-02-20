import AppKit

/// A translucent HUD tooltip anchored to the bottom-left of the screen
/// that shows the active color name or drawing tool in drawing mode.
final class ToolTipHUD {

    enum Content {
        case color(name: String, color: NSColor)
        case tool(name: String, sfSymbol: String)
    }

    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var isFadingOut = false

    // Subviews
    private var backgroundView: NSView?
    private var dotView: NSView?
    private var iconView: NSImageView?
    private var label: NSTextField?

    private let panelHeight: CGFloat = 36
    private let cornerRadius: CGFloat = 12
    private let margin: CGFloat = 20

    // MARK: - Public API

    func show(content: Content) {
        ensurePanel()
        configureContent(content)
        positionBottomLeft()
        fadeIn()
        scheduleDismiss()
    }

    func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        isFadingOut = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel?.animator().alphaValue = 0
        }
        panel?.orderOut(nil)
    }

    func teardown() {
        hide()
        panel?.close()
        panel = nil
        backgroundView = nil
        dotView = nil
        iconView = nil
        label = nil
    }

    // MARK: - Panel Setup

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .screenSaver + 1
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.alphaValue = 0

        // Translucent dark background
        let bg = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: panelHeight))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.75).cgColor
        bg.layer?.cornerRadius = cornerRadius
        bg.layer?.masksToBounds = true
        bg.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(bg)
        self.backgroundView = bg

        // Color dot (hidden by default)
        let dot = NSView(frame: NSRect(x: 14, y: 11, width: 14, height: 14))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 7
        dot.isHidden = true
        bg.addSubview(dot)
        self.dotView = dot

        // SF Symbol icon (hidden by default)
        let icon = NSImageView(frame: NSRect(x: 12, y: 8, width: 20, height: 20))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .white
        icon.isHidden = true
        bg.addSubview(icon)
        self.iconView = icon

        // Label
        let textField = NSTextField(labelWithString: "")
        textField.font = .systemFont(ofSize: 15, weight: .medium)
        textField.textColor = .white
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.isEditable = false
        textField.sizeToFit()
        textField.frame.origin = NSPoint(x: 36, y: 8)
        bg.addSubview(textField)
        self.label = textField

        self.panel = panel
    }

    // MARK: - Content Configuration

    private func configureContent(_ content: Content) {
        guard let label, let dotView, let iconView else { return }

        switch content {
        case .color(let name, let color):
            dotView.layer?.backgroundColor = color.cgColor
            dotView.isHidden = false
            iconView.isHidden = true
            label.stringValue = name
        case .tool(let name, let sfSymbol):
            dotView.isHidden = true
            if let img = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: name) {
                iconView.image = img
                iconView.isHidden = false
            } else {
                iconView.isHidden = true
            }
            label.stringValue = name
        }

        label.sizeToFit()
        let leftInset: CGFloat = dotView.isHidden && iconView.isHidden ? 14 : 36
        label.frame.origin.x = leftInset

        let panelWidth = leftInset + label.frame.width + 16
        panel?.setContentSize(NSSize(width: panelWidth, height: panelHeight))
    }

    // MARK: - Positioning

    private func positionBottomLeft() {
        guard let panel else { return }
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main
        guard let frame = screen?.frame else { return }

        let x = frame.minX + margin
        let y = frame.minY + margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Animation

    private func fadeIn() {
        guard let panel else { return }
        isFadingOut = false
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    private func fadeOut() {
        guard let panel, !isFadingOut else { return }
        isFadingOut = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.isFadingOut else { return }
            self.panel?.orderOut(nil)
            self.isFadingOut = false
        })
    }

    private func scheduleDismiss() {
        dismissTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }
}
