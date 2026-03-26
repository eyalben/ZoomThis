import AppKit
import CoreGraphics

enum DrawingAction {
    case freehand(points: [CGPoint], color: NSColor, lineWidth: CGFloat)
    case line(from: CGPoint, to: CGPoint, color: NSColor, lineWidth: CGFloat)
    case rect(origin: CGPoint, size: CGSize, color: NSColor, lineWidth: CGFloat)
    case ellipse(origin: CGPoint, size: CGSize, color: NSColor, lineWidth: CGFloat)
    case arrow(from: CGPoint, to: CGPoint, color: NSColor, lineWidth: CGFloat)
    case text(string: String, position: CGPoint, font: NSFont, color: NSColor, alignment: NSTextAlignment)
    case blur(points: [CGPoint], lineWidth: CGFloat)
    case whiteboard
    case blackboard
    case eraseAll

    func render(in context: CGContext, imageSize: CGSize, sourceImage: CGImage? = nil) {
        switch self {
        case .freehand(let points, let color, let lineWidth):
            guard points.count >= 2 else { return }
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.beginPath()
            context.move(to: points[0])
            for i in 1..<points.count {
                context.addLine(to: points[i])
            }
            context.strokePath()

        case .line(let from, let to, let color, let lineWidth):
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.beginPath()
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()

        case .rect(let origin, let size, let color, let lineWidth):
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            context.stroke(CGRect(origin: origin, size: size))

        case .ellipse(let origin, let size, let color, let lineWidth):
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            context.strokeEllipse(in: CGRect(origin: origin, size: size))

        case .arrow(let from, let to, let color, let lineWidth):
            context.setStrokeColor(color.cgColor)
            context.setFillColor(color.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            // Compute arrowhead geometry first so we can shorten the line
            let angle = atan2(to.y - from.y, to.x - from.x)
            let headLength = max(lineWidth * 6, 18.0)
            let headAngle: CGFloat = .pi / 6
            // Start the line at the base of the arrowhead to avoid overflow
            let baseOffset = headLength * cos(headAngle)
            let lineStart = CGPoint(
                x: from.x + baseOffset * cos(angle),
                y: from.y + baseOffset * sin(angle)
            )
            context.beginPath()
            context.move(to: lineStart)
            context.addLine(to: to)
            context.strokePath()
            // Draw arrowhead at the start point (where the user clicked)
            let p1 = CGPoint(
                x: from.x + headLength * cos(angle - headAngle),
                y: from.y + headLength * sin(angle - headAngle)
            )
            let p2 = CGPoint(
                x: from.x + headLength * cos(angle + headAngle),
                y: from.y + headLength * sin(angle + headAngle)
            )
            context.beginPath()
            context.move(to: from)
            context.addLine(to: p1)
            context.addLine(to: p2)
            context.closePath()
            context.fillPath()

        case .text(let string, let position, let font, let color, let alignment):
            // Push this CGContext as NSGraphicsContext so NSString.draw targets it
            let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext
            defer { NSGraphicsContext.restoreGraphicsState() }

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = alignment
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
            let nsString = string as NSString
            let size = nsString.size(withAttributes: attributes)
            let verticalOffset = size.height / 2
            let drawRect: CGRect
            switch alignment {
            case .right:
                drawRect = CGRect(x: position.x - size.width, y: position.y - verticalOffset, width: size.width + 100, height: size.height * 10)
            default:
                drawRect = CGRect(x: position.x, y: position.y - verticalOffset, width: size.width + 100, height: size.height * 10)
            }
            nsString.draw(in: drawRect, withAttributes: attributes)

        case .blur(let points, let lineWidth):
            guard let sourceImage, points.count >= 2 else { return }
            // Create a path from the points to use as clip
            let path = CGMutablePath()
            path.move(to: points[0])
            for i in 1..<points.count {
                path.addLine(to: points[i])
            }
            // Create a stroked version of the path for the clip region
            let strokedPath = path.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
            context.saveGState()
            context.addPath(strokedPath)
            context.clip()
            // Draw pixelated version: scale down then back up
            let smallW = max(1, Int(imageSize.width * 0.08))
            let smallH = max(1, Int(imageSize.height * 0.08))
            if let smallContext = CGContext(data: nil, width: smallW, height: smallH,
                                            bitsPerComponent: 8, bytesPerRow: 0,
                                            space: sourceImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) {
                smallContext.interpolationQuality = .none
                smallContext.draw(sourceImage, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
                if let pixelated = smallContext.makeImage() {
                    context.interpolationQuality = .none
                    // Temporarily undo Y-flip for CGImage drawing (CGContext.draw expects Y-up)
                    context.scaleBy(x: 1, y: -1)
                    context.translateBy(x: 0, y: -imageSize.height)
                    context.draw(pixelated, in: CGRect(origin: .zero, size: imageSize))
                }
            }
            context.restoreGState()

        case .whiteboard:
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: imageSize))

        case .blackboard:
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(origin: .zero, size: imageSize))

        case .eraseAll:
            // Clear to transparent — the caller should re-draw the source image after this
            context.clear(CGRect(origin: .zero, size: imageSize))
        }
    }
}
