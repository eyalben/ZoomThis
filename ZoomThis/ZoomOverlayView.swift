import AppKit
import CoreGraphics

final class ZoomOverlayView: NSView {
    let image: CGImage
    private var mousePosition: NSPoint = .zero
    var zoomFactor: CGFloat = 2.0 {
        didSet { needsDisplay = true }
    }
    var drawingState: DrawingState?
    var inProgressAction: DrawingAction? {
        didSet { needsDisplay = true }
    }
    var cropSelection: CGRect? {
        didSet { needsDisplay = true }
    }

    // Cursor dot preview for drawing mode
    private var cursorDotPosition: NSPoint = .zero
    var showCursorDot: Bool = false {
        didSet { needsDisplay = true }
    }
    var cursorDotDiameter: CGFloat = 6 {
        didSet { needsDisplay = true }
    }
    var cursorDotColor: NSColor = .red {
        didSet { needsDisplay = true }
    }

    // Cached committed drawing layer — invalidated on commit/undo
    private var committedLayer: CGImage?
    private var committedActionCount = 0

    init(image: CGImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Suppress default NSBeep — key events are handled by the event monitor
    }

    func updateMousePosition(_ screenPoint: NSPoint) {
        mousePosition = screenPoint
        needsDisplay = true
    }

    func updateCursorDotPosition(_ screenPoint: NSPoint) {
        cursorDotPosition = screenPoint
        needsDisplay = true
    }

    // MARK: - Coordinate Conversion

    private func currentCropRect() -> CGRect {
        let viewWidth = bounds.width
        let viewHeight = bounds.height
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let scaleX = imageWidth / viewWidth
        let scaleY = imageHeight / viewHeight

        let viewMouseX = mousePosition.x - frame.origin.x
        let viewMouseY = mousePosition.y - frame.origin.y
        let imageMouseX = viewMouseX * scaleX
        let imageMouseY = (viewHeight - viewMouseY) * scaleY

        let cropWidth = imageWidth / zoomFactor
        let cropHeight = imageHeight / zoomFactor

        var cropX = imageMouseX - cropWidth / 2
        var cropY = imageMouseY - cropHeight / 2
        cropX = max(0, min(cropX, imageWidth - cropWidth))
        cropY = max(0, min(cropY, imageHeight - cropHeight))

        return CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
    }

    func imagePoint(from viewPoint: NSPoint) -> CGPoint {
        let viewWidth = bounds.width
        let viewHeight = bounds.height
        let cropRect = currentCropRect()
        let imageX = cropRect.origin.x + (viewPoint.x / viewWidth) * cropRect.width
        let imageY = cropRect.origin.y + ((viewHeight - viewPoint.y) / viewHeight) * cropRect.height
        return CGPoint(x: imageX, y: imageY)
    }

    private func viewPoint(from imagePoint: CGPoint) -> NSPoint {
        let viewWidth = bounds.width
        let viewHeight = bounds.height
        let cropRect = currentCropRect()
        let viewX = ((imagePoint.x - cropRect.origin.x) / cropRect.width) * viewWidth
        let viewY = viewHeight - ((imagePoint.y - cropRect.origin.y) / cropRect.height) * viewHeight
        return NSPoint(x: viewX, y: viewY)
    }

    // MARK: - Committed Layer Cache

    private func invalidateCommittedLayerIfNeeded() {
        guard let drawingState else { return }
        if drawingState.actions.count != committedActionCount {
            committedLayer = nil
            committedActionCount = drawingState.actions.count
        }
    }

    private func getOrBuildCommittedLayer() -> CGImage? {
        guard let drawingState, !drawingState.actions.isEmpty else { return nil }

        invalidateCommittedLayerIfNeeded()
        if let committedLayer { return committedLayer }

        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        guard let ctx = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip context to Y-down so drawing coordinates match CGImage convention
        ctx.translateBy(x: 0, y: CGFloat(image.height))
        ctx.scaleBy(x: 1, y: -1)

        // Find last board/erase action to skip rendering earlier actions
        var startIndex = 0
        for i in stride(from: drawingState.actions.count - 1, through: 0, by: -1) {
            switch drawingState.actions[i] {
            case .whiteboard, .blackboard, .eraseAll:
                startIndex = i
                break
            default:
                continue
            }
            if startIndex > 0 { break }
        }

        for i in startIndex..<drawingState.actions.count {
            drawingState.actions[i].render(in: ctx, imageSize: imageSize, sourceImage: image)
        }

        committedLayer = ctx.makeImage()
        return committedLayer
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let cropRect = currentCropRect()

        // Draw the zoomed screenshot: crop in image coords then draw into view
        guard let croppedImage = image.cropping(to: cropRect) else { return }
        context.interpolationQuality = .high
        context.draw(croppedImage, in: bounds)

        // Draw annotations
        if let drawingState, (!drawingState.actions.isEmpty || inProgressAction != nil) {
            drawAnnotations(context: context, cropRect: cropRect)
        }

        // Draw crop selection overlay
        if let cropSelection {
            drawCropSelection(context: context, selection: cropSelection)
        }

        // Draw cursor dot preview (drawing mode only, not exported)
        if showCursorDot {
            drawCursorDot(context: context)
        }
    }

    private func drawAnnotations(context: CGContext, cropRect: CGRect) {
        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))

        // Use cached committed layer if only panning (no in-progress action)
        if inProgressAction == nil, let layer = getOrBuildCommittedLayer() {
            // Draw the committed layer cropped to current view
            if let cropped = layer.cropping(to: cropRect) {
                context.saveGState()
                context.interpolationQuality = .high
                // Draw into full view bounds
                context.draw(cropped, in: bounds)
                context.restoreGState()
            }
            return
        }

        // When there's an in-progress action, build a temporary composite
        guard let offscreenContext = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // Flip context to Y-down so drawing coordinates match CGImage convention
        offscreenContext.translateBy(x: 0, y: CGFloat(image.height))
        offscreenContext.scaleBy(x: 1, y: -1)

        // Draw committed layer into offscreen (temporarily unflip for CGImage draw)
        if let layer = getOrBuildCommittedLayer() {
            offscreenContext.saveGState()
            offscreenContext.scaleBy(x: 1, y: -1)
            offscreenContext.translateBy(x: 0, y: -CGFloat(image.height))
            offscreenContext.draw(layer, in: CGRect(origin: .zero, size: imageSize))
            offscreenContext.restoreGState()
        }

        // Draw in-progress action on top (context is Y-down)
        if let inProgressAction {
            inProgressAction.render(in: offscreenContext, imageSize: imageSize, sourceImage: image)
        }

        guard let compositeImage = offscreenContext.makeImage(),
              let croppedDrawing = compositeImage.cropping(to: cropRect) else { return }

        context.saveGState()
        context.interpolationQuality = .high
        context.draw(croppedDrawing, in: bounds)
        context.restoreGState()
    }

    private func drawCropSelection(context: CGContext, selection: CGRect) {
        // Convert selection (in image coords) to view coords
        let topLeft = viewPoint(from: CGPoint(x: selection.minX, y: selection.minY))
        let bottomRight = viewPoint(from: CGPoint(x: selection.maxX, y: selection.maxY))
        let viewRect = CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )

        // Dimming overlay outside selection
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        // Fill bounds then clear the selection
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(viewRect)
        context.addPath(path)
        context.fillPath(using: .evenOdd)
        context.restoreGState()

        // Dashed border
        context.saveGState()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [6, 4])
        context.stroke(viewRect)
        context.restoreGState()
    }

    // MARK: - Cursor Dot

    private func drawCursorDot(context: CGContext) {
        // Convert screen-space cursor dot position to view-local coords
        let viewX = cursorDotPosition.x - frame.origin.x
        let viewY = cursorDotPosition.y - frame.origin.y
        let diameter = max(cursorDotDiameter, 6)
        let radius = diameter / 2

        let dotRect = CGRect(
            x: viewX - radius,
            y: viewY - radius,
            width: diameter,
            height: diameter
        )

        // Filled dot
        context.saveGState()
        context.setFillColor(cursorDotColor.cgColor)
        context.fillEllipse(in: dotRect)

        // White stroke outline for visibility
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: dotRect)
        context.restoreGState()
    }

    // MARK: - Export Helpers

    func renderCurrentViewToImage() -> NSImage? {
        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        let cropRect = currentCropRect()
        let width = Int(cropRect.width)
        let height = Int(cropRect.height)
        guard width > 0, height > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip context to Y-down so crop coordinates (Y-down image space) work directly
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        // Translate so crop region maps to context origin
        ctx.translateBy(x: -cropRect.origin.x, y: -cropRect.origin.y)

        // Draw base image (temporarily undo flip for CGContext.draw which expects Y-up)
        ctx.saveGState()
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: 0, y: -imageSize.height)
        ctx.draw(image, in: CGRect(origin: .zero, size: imageSize))
        ctx.restoreGState()

        // Draw annotations in full image space (context is Y-down)
        renderAnnotations(into: ctx, imageSize: imageSize)

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    func renderImageRegion(_ region: CGRect) -> NSImage? {
        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        let width = Int(region.width)
        let height = Int(region.height)
        guard width > 0, height > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip context to Y-down so region coordinates (Y-down image space) work directly
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        // Shift so the region maps to the context origin
        ctx.translateBy(x: -region.origin.x, y: -region.origin.y)

        // Draw base image (temporarily undo flip for CGContext.draw which expects Y-up)
        ctx.saveGState()
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: 0, y: -imageSize.height)
        ctx.draw(image, in: CGRect(origin: .zero, size: imageSize))
        ctx.restoreGState()

        // Draw annotations in full image space (context is Y-down)
        renderAnnotations(into: ctx, imageSize: imageSize)

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private func renderAnnotations(into ctx: CGContext, imageSize: CGSize) {
        guard let drawingState, !drawingState.actions.isEmpty else { return }

        var startIndex = 0
        for i in stride(from: drawingState.actions.count - 1, through: 0, by: -1) {
            switch drawingState.actions[i] {
            case .whiteboard, .blackboard, .eraseAll:
                startIndex = i
                break
            default:
                continue
            }
            if startIndex > 0 { break }
        }

        // Context is already Y-down (flipped by caller)
        for i in startIndex..<drawingState.actions.count {
            drawingState.actions[i].render(in: ctx, imageSize: imageSize, sourceImage: image)
        }
    }
}
