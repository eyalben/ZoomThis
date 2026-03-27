import SwiftUI
import ServiceManagement
import os.log

private extension Logger {
    static let general = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ZoomThis", category: "general")
}

@MainActor @Observable
final class AppState {
    static let zoomHotkeyID: UInt32 = 1  // Ctrl+1
    // ID 2 reserved for future Ctrl+2 (e.g. drawing-only mode)
    static let timerHotkeyID: UInt32 = 3  // Ctrl+3

    // Zoom settings
    var hotkeyKeyCode: UInt32 = 18      // '1' key
    var hotkeyModifiers: UInt32 = 0x1000 // Ctrl
    var initialZoomFactor: CGFloat = 2.0
    var zoomAnimationEnabled: Bool = true

    // Timer settings
    var timerHotkeyKeyCode: UInt32 = 20  // '3' key
    var timerHotkeyModifiers: UInt32 = 0x1000 // Ctrl
    var defaultTimerDuration: TimeInterval = 300 // 5 minutes

    // Drawing defaults
    var defaultPenColor: String = "red"
    var defaultPenThickness: CGFloat = 3.0
    var defaultTextFontName: String = "Helvetica"
    var defaultTextFontSize: CGFloat = 24.0

    // General
    var showSettingsOnLaunch: Bool = true
    var isFirstRun: Bool { UserDefaults.standard.object(forKey: "hotkeyKeyCode") == nil }

    // State
    var isZoomActive = false
    var isTimerActive = false
    var hasScreenRecordingPermission = false
    var isLaunchAtLoginEnabled = false

    let hotkeyManager = HotkeyManager()
    let screenCaptureManager = ScreenCaptureManager()
    let overlayController = ZoomOverlayController()
    let breakTimerController = BreakTimerController()
    let permissionManager = PermissionManager()

    private var permissionPollTimer: Timer?

    init() {
        loadSettings()
        registerHotkey()
        registerTimerHotkey()
        isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        checkPermissions()
    }

    // MARK: - Permission Polling

    func startPermissionPolling() {
        stopPermissionPolling()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.checkPermissions()
                if self?.hasScreenRecordingPermission == true {
                    self?.stopPermissionPolling()
                }
            }
        }
    }

    func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func checkPermissions() {
        hasScreenRecordingPermission = permissionManager.hasScreenRecordingPermission()
    }

    // MARK: - Launch at Login

    func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            Logger.general.error("Launch at login toggle failed: \(error)")
            isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Zoom Hotkey

    func registerHotkey() {
        hotkeyManager.unregister(id: AppState.zoomHotkeyID)
        hotkeyManager.register(id: AppState.zoomHotkeyID, keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.activateZoom()
            }
        }
    }

    // MARK: - Timer Hotkey

    func registerTimerHotkey() {
        hotkeyManager.unregister(id: AppState.timerHotkeyID)
        hotkeyManager.register(id: AppState.timerHotkeyID, keyCode: timerHotkeyKeyCode, modifiers: timerHotkeyModifiers) { [weak self] in
            Task { @MainActor [weak self] in
                self?.activateTimer()
            }
        }
    }

    // MARK: - Zoom

    func activateZoom() async {
        if isZoomActive {
            isZoomActive = false
            overlayController.dismiss()
            return
        }
        guard !overlayController.isDismissing, !isTimerActive else { return }
        guard let result = await screenCaptureManager.captureScreen() else {
            hasScreenRecordingPermission = false
            return
        }
        hasScreenRecordingPermission = true
        isZoomActive = true
        overlayController.show(
            image: result.image,
            screen: result.screen,
            initialZoom: initialZoomFactor,
            animateIn: zoomAnimationEnabled,
            defaultColor: defaultNSColor(),
            defaultLineWidth: defaultPenThickness,
            defaultTextFontSize: defaultTextFontSize
        ) { [weak self] in
            self?.deactivateZoom()
        }
    }

    func deactivateZoom() {
        isZoomActive = false
    }

    // MARK: - Timer

    func activateTimer() {
        guard !isZoomActive, !isTimerActive else {
            // If timer is active and minimized, restore it
            if isTimerActive && breakTimerController.isMinimized {
                breakTimerController.restore()
            }
            return
        }
        isTimerActive = true
        breakTimerController.show(duration: defaultTimerDuration) { [weak self] in
            self?.deactivateTimer()
        }
    }

    func deactivateTimer() {
        isTimerActive = false
    }

    // MARK: - Defaults Helpers

    func defaultNSColor() -> NSColor {
        switch defaultPenColor {
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "pink": return .systemPink
        default: return .red
        }
    }

    // MARK: - Persistence

    func loadSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "hotkeyKeyCode") != nil {
            hotkeyKeyCode = UInt32(defaults.integer(forKey: "hotkeyKeyCode"))
            hotkeyModifiers = UInt32(defaults.integer(forKey: "hotkeyModifiers"))
        }
        if defaults.object(forKey: "initialZoomFactor") != nil {
            initialZoomFactor = CGFloat(defaults.double(forKey: "initialZoomFactor"))
        }
        if defaults.object(forKey: "zoomAnimationEnabled") != nil {
            zoomAnimationEnabled = defaults.bool(forKey: "zoomAnimationEnabled")
        }
        if defaults.object(forKey: "timerHotkeyKeyCode") != nil {
            timerHotkeyKeyCode = UInt32(defaults.integer(forKey: "timerHotkeyKeyCode"))
            timerHotkeyModifiers = UInt32(defaults.integer(forKey: "timerHotkeyModifiers"))
        }
        if defaults.object(forKey: "defaultTimerDuration") != nil {
            defaultTimerDuration = defaults.double(forKey: "defaultTimerDuration")
        }
        if let color = defaults.string(forKey: "defaultPenColor") {
            defaultPenColor = color
        }
        if defaults.object(forKey: "defaultPenThickness") != nil {
            defaultPenThickness = CGFloat(defaults.double(forKey: "defaultPenThickness"))
        }
        if let fontName = defaults.string(forKey: "defaultTextFontName") {
            defaultTextFontName = fontName
        }
        if defaults.object(forKey: "defaultTextFontSize") != nil {
            defaultTextFontSize = CGFloat(defaults.double(forKey: "defaultTextFontSize"))
        }
        if defaults.object(forKey: "showSettingsOnLaunch") != nil {
            showSettingsOnLaunch = defaults.bool(forKey: "showSettingsOnLaunch")
        }
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(Int(hotkeyKeyCode), forKey: "hotkeyKeyCode")
        defaults.set(Int(hotkeyModifiers), forKey: "hotkeyModifiers")
        defaults.set(Double(initialZoomFactor), forKey: "initialZoomFactor")
        defaults.set(zoomAnimationEnabled, forKey: "zoomAnimationEnabled")
        defaults.set(Int(timerHotkeyKeyCode), forKey: "timerHotkeyKeyCode")
        defaults.set(Int(timerHotkeyModifiers), forKey: "timerHotkeyModifiers")
        defaults.set(defaultTimerDuration, forKey: "defaultTimerDuration")
        defaults.set(defaultPenColor, forKey: "defaultPenColor")
        defaults.set(Double(defaultPenThickness), forKey: "defaultPenThickness")
        defaults.set(defaultTextFontName, forKey: "defaultTextFontName")
        defaults.set(Double(defaultTextFontSize), forKey: "defaultTextFontSize")
        defaults.set(showSettingsOnLaunch, forKey: "showSettingsOnLaunch")
    }
}
