import AppKit

final class BreakTimerView: NSView {
    var remainingSeconds: Int = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Black background
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)

        // Format time as MM:SS
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        let timeString = String(format: "%02d:%02d", minutes, seconds)

        // Draw centered white text
        let fontSize = min(bounds.width, bounds.height) * 0.25
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .light)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let nsString = timeString as NSString
        let textSize = nsString.size(withAttributes: attributes)
        let drawRect = CGRect(
            x: 0,
            y: (bounds.height - textSize.height) / 2,
            width: bounds.width,
            height: textSize.height
        )
        nsString.draw(in: drawRect, withAttributes: attributes)
    }
}
