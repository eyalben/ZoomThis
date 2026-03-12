import SwiftUI

@main
struct ZoomThisApp: App {
    @State private var appState = AppState()
    private static var didAutoOpenSettings = false
    @Environment(\.openWindow) private var openWindow

    private var zoomShortcut: String {
        shortcutString(keyCode: appState.hotkeyKeyCode, modifiers: appState.hotkeyModifiers)
    }

    private var timerShortcut: String {
        shortcutString(keyCode: appState.timerHotkeyKeyCode, modifiers: appState.timerHotkeyModifiers)
    }

    private func autoOpenSettingsIfNeeded() {
        guard !Self.didAutoOpenSettings else { return }
        guard appState.isFirstRun || appState.showSettingsOnLaunch else { return }
        Self.didAutoOpenSettings = true
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        let _ = autoOpenSettingsIfNeeded()
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
    }
}
