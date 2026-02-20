import SwiftUI

@main
struct ZoomThisApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    private var zoomShortcut: String {
        shortcutString(keyCode: appState.hotkeyKeyCode, modifiers: appState.hotkeyModifiers)
    }

    private var timerShortcut: String {
        shortcutString(keyCode: appState.timerHotkeyKeyCode, modifiers: appState.timerHotkeyModifiers)
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
                openWindow(id: "settings")
                NSApplication.shared.activate()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit ZoomThis") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        Window("ZoomThis Settings", id: "settings") {
            SettingsView()
                .environment(appState)
        }
        .defaultSize(width: 640, height: 480)
        .windowResizability(.contentSize)
    }
}
