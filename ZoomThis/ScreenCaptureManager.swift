import AppKit
import ScreenCaptureKit
import os.log

private extension Logger {
    static let capture = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ZoomThis", category: "capture")
}

final class ScreenCaptureManager {

    struct CaptureResult {
        let image: CGImage
        let screen: NSScreen
    }

    func captureScreen() async -> CaptureResult? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else {
            return nil
        }

        guard let displayID = screen.displayID else { return nil }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: {
                $0.displayID == displayID
            }) else {
                return nil
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = Int(screen.backingScaleFactor)
            config.width = display.width * scale
            config.height = display.height * scale
            config.showsCursor = false
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGDisplayCopyColorSpace(displayID).name ?? CGColorSpace.displayP3

            let raw = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
            let image = Self.makeOpaque(raw)
            return CaptureResult(image: image, screen: screen)
        } catch {
            Logger.capture.error("Screen capture failed: \(error)")
            return nil
        }
    }

    /// Re-wrap the image with alpha stripped (noneSkipFirst) so shadow pixels
    /// with alpha < 255 render as fully opaque. Shares the underlying data
    /// provider — no pixel copy occurs.
    private static func makeOpaque(_ image: CGImage) -> CGImage {
        guard let provider = image.dataProvider else { return image }
        let noAlpha = CGBitmapInfo(rawValue:
            (image.bitmapInfo.rawValue & ~CGBitmapInfo.alphaInfoMask.rawValue)
            | CGImageAlphaInfo.noneSkipFirst.rawValue)
        return CGImage(
            width: image.width, height: image.height,
            bitsPerComponent: image.bitsPerComponent,
            bitsPerPixel: image.bitsPerPixel,
            bytesPerRow: image.bytesPerRow,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: noAlpha,
            provider: provider,
            decode: image.decode,
            shouldInterpolate: image.shouldInterpolate,
            intent: image.renderingIntent
        ) ?? image
    }

}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
