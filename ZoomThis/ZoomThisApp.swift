import SwiftUI

@main
struct ZoomThisApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow
    private static var didAutoOpenSettings = false

    private var zoomShortcut: String {
        shortcutString(keyCode: appState.hotkeyKeyCode, modifiers: appState.hotkeyModifiers)
    }

    private var timerShortcut: String {
        shortcutString(keyCode: appState.timerHotkeyKeyCode, modifiers: appState.timerHotkeyModifiers)
    }

    private var shouldAutoOpenSettings: Bool {
        guard !Self.didAutoOpenSettings else { return false }
        return appState.isFirstRun || appState.showSettingsOnLaunch
    }

    var body: some Scene {
        MenuBarExtra("ZoomThis", systemImage: "plus.magnifyingglass") {
            Button("Zoom \(zoomShortcut)") {
                Task { await appState.activateZoom() }
            }
            .disabled(appState.isZoomActive || appState.isTimerActive)

            Button("Break Timer \(timerShortcut)") {
                appState.activateTimer()
            }
            .disabled(appState.isZoomActive || (appState.isTimerActive && !appState.breakTimerController.isMinimized))

            if appState.isTimerActive && appState.breakTimerController.isMinimized {
                Button("Restore Timer") {
                    appState.breakTimerController.restore()
                }
            }

            Divider()

            Button("Settings...") {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Quit ZoomThis") {
                NSApplication.shared.terminate(nil)
            }
        }

        Window("ZoomThis Settings", id: "settings") {
            SettingsView()
                .environment(appState)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                }
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .defaultSize(width: 520, height: 420)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(shouldAutoOpenSettings ? .presented : .suppressed)
    }
}
