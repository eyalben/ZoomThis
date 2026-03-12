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

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
            return CaptureResult(image: image, screen: screen)
        } catch {
            Logger.capture.error("Screen capture failed: \(error)")
            return nil
        }
    }

}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
