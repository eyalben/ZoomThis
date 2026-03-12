import SwiftUI
import Carbon

// MARK: - Reusable Hotkey Recorder

struct HotkeyRecorderView: View {
    let label: String
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    var onStartRecording: (() -> Void)?
    var onChange: () -> Void

    @State private var isRecording = false
    @State private var localMonitor: Any?
    @State private var savedKeyCode: UInt32 = 0
    @State private var savedModifiers: UInt32 = 0

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(shortcutString(keyCode: keyCode, modifiers: modifiers))
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.secondary.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
                )

            if isRecording {
                Text("Press keys...")
                    .foregroundStyle(.secondary)
                    .phaseAnimator([false, true]) { content, phase in
                        content.opacity(phase ? 0.3 : 1.0)
                    } animation: { _ in
                        .easeInOut(duration: 0.7)
                    }
            } else {
                Button("Record") { startRecording() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .onDisappear { cancelRecording() }
    }

    private func startRecording() {
        savedKeyCode = keyCode
        savedModifiers = modifiers
        onStartRecording?()
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                keyCode = savedKeyCode
                modifiers = savedModifiers
                onChange()
                stopRecording()
                return nil
            }
            let carbonMods = cocoaToCarbonModifiers(event.modifierFlags)
            keyCode = UInt32(event.keyCode)
            modifiers = carbonMods
            onChange()
            stopRecording()
            return nil
        }
    }

    private func cancelRecording() {
        guard isRecording else { return }
        keyCode = savedKeyCode
        modifiers = savedModifiers
        onChange()
        stopRecording()
    }

    private func stopRecording() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isRecording = false
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    private var showPermissionOverlay: Bool {
        !appState.hasScreenRecordingPermission
    }

    var body: some View {
        Group {
            if showPermissionOverlay {
                permissionView
            } else {
                settingsTabView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showPermissionOverlay)
        .frame(width: 520, height: 420)
        .onAppear { appState.startPermissionPolling() }
        .onDisappear { appState.stopPermissionPolling() }
    }

    // MARK: - Settings Tab View

    private var settingsTabView: some View {
        TabView {
            Tab("About", systemImage: "info.circle") {
                aboutTab
            }
            Tab("Zoom", systemImage: "plus.magnifyingglass") {
                zoomTab
            }
            Tab("Timer", systemImage: "timer") {
                timerTab
            }
        }
    }

    // MARK: - Permission View

    private var permissionView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            VStack(spacing: 6) {
                Text("ZoomThis needs Screen Recording")
                    .font(.title2.bold())

                Text("This permission is required to capture and zoom the screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Button("Open System Settings") {
                appState.permissionManager.requestPermission()
                appState.permissionManager.openScreenRecordingSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Zoom Tab

    private var zoomTab: some View {
        @Bindable var appState = appState
        return Form {
            Section {
                HotkeyRecorderView(
                    label: "Zoom shortcut",
                    keyCode: $appState.hotkeyKeyCode,
                    modifiers: $appState.hotkeyModifiers,
                    onStartRecording: {
                        appState.hotkeyManager.unregister(id: AppState.zoomHotkeyID)
                    }
                ) {
                    appState.saveSettings()
                    appState.registerHotkey()
                }
            } header: {
                Text("Activation")
            } footer: {
                Text("Zoom in and annotate any part of your screen.")
            }

            Section("Keyboard Shortcuts") {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        shortcutSection("Navigation", shortcuts: [
                            ("Mouse", "Pan viewport"),
                            ("Scroll", "Zoom in/out"),
                            ("Right-click", "Back to pan"),
                            ("Escape", "Exit zoom"),
                        ])

                        shortcutSection("Drawing", shortcuts: [
                            ("Click", "Freehand"),
                            ("\u{21E7}+drag", "Line"),
                            ("\u{2303}+drag", "Rectangle"),
                            ("\u{2325}+drag", "Ellipse"),
                            ("\u{2303}\u{21E7}+drag", "Arrow"),
                        ])
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                        .padding(.horizontal, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        shortcutSection("Colors & Text", shortcuts: [
                            ("R/G/B/Y/O/P", "Pen color"),
                            ("\u{21E7}+color", "Highlight"),
                            ("X", "Blur"),
                            ("W / K / E", "Wht/Blk/Erase"),
                            ("T / \u{21E7}T", "Text L/R"),
                        ])

                        shortcutSection("Actions", shortcuts: [
                            ("\u{2303}Z", "Undo"),
                            ("\u{2303}C / \u{2303}S", "Copy / Save"),
                        ])
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Timer Tab

    private var timerTab: some View {
        @Bindable var appState = appState
        return Form {
            Section {
                HotkeyRecorderView(
                    label: "Timer shortcut",
                    keyCode: $appState.timerHotkeyKeyCode,
                    modifiers: $appState.timerHotkeyModifiers,
                    onStartRecording: {
                        appState.hotkeyManager.unregister(id: AppState.timerHotkeyID)
                    }
                ) {
                    appState.saveSettings()
                    appState.registerTimerHotkey()
                }
            } header: {
                Text("Activation")
            } footer: {
                Text("Full-screen countdown timer for breaks and presentations.")
            }

            Section("Keyboard Shortcuts") {
                VStack(alignment: .leading, spacing: 10) {
                    shortcutSection(nil, shortcuts: [
                        ("Scroll / \u{2191}\u{2193}", "\u{00B1}10s"),
                        ("\u{2303}+Scroll", "\u{00B1}30s"),
                        ("Escape", "Dismiss"),
                        ("Lose focus", "Minimize"),
                        ("Hotkey", "Restore"),
                    ])
                }
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutSection(_ title: String?, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, item in
                shortcutRow(key: item.0, description: item.1)
            }
        }
    }

    private func shortcutRow(key: String, description: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .frame(width: 85, alignment: .trailing)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)

            Text("ZoomThis")
                .font(.title.bold())
                .padding(.top, 12)

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text("Screen zoom, annotation, and break timer tool for macOS.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            Spacer()

            Form {
                Section {
                    Toggle("Show Settings on Launch", isOn: Binding(
                        get: { appState.showSettingsOnLaunch },
                        set: { newValue in
                            appState.showSettingsOnLaunch = newValue
                            appState.saveSettings()
                        }
                    ))
                    .toggleStyle(.switch)

                    Toggle("Launch at Login", isOn: Binding(
                        get: { appState.isLaunchAtLoginEnabled },
                        set: { _ in appState.toggleLaunchAtLogin() }
                    ))
                    .toggleStyle(.switch)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Shortcut Display Helpers

func shortcutString(keyCode: UInt32, modifiers: UInt32) -> String {
    carbonModifiersToString(modifiers) + keyCodeToString(keyCode)
}

func carbonModifiersToString(_ modifiers: UInt32) -> String {
    var result = ""
    if modifiers & UInt32(controlKey) != 0 { result += "\u{2303}" }
    if modifiers & UInt32(optionKey) != 0 { result += "\u{2325}" }
    if modifiers & UInt32(shiftKey) != 0 { result += "\u{21E7}" }
    if modifiers & UInt32(cmdKey) != 0 { result += "\u{2318}" }
    return result
}

func cocoaToCarbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var carbon: UInt32 = 0
    if flags.contains(.control) { carbon |= UInt32(controlKey) }
    if flags.contains(.option) { carbon |= UInt32(optionKey) }
    if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
    if flags.contains(.command) { carbon |= UInt32(cmdKey) }
    return carbon
}

func keyCodeToString(_ keyCode: UInt32) -> String {
    switch keyCode {
    case 0: return "A"
    case 1: return "S"
    case 2: return "D"
    case 3: return "F"
    case 4: return "H"
    case 5: return "G"
    case 6: return "Z"
    case 7: return "X"
    case 8: return "C"
    case 9: return "V"
    case 11: return "B"
    case 12: return "Q"
    case 13: return "W"
    case 14: return "E"
    case 15: return "R"
    case 16: return "Y"
    case 17: return "T"
    case 18: return "1"
    case 19: return "2"
    case 20: return "3"
    case 21: return "4"
    case 22: return "6"
    case 23: return "5"
    case 24: return "="
    case 25: return "9"
    case 26: return "7"
    case 27: return "-"
    case 28: return "8"
    case 29: return "0"
    case 30: return "]"
    case 31: return "O"
    case 32: return "U"
    case 33: return "["
    case 34: return "I"
    case 35: return "P"
    case 36: return "\u{21A9}"
    case 37: return "L"
    case 38: return "J"
    case 39: return "'"
    case 40: return "K"
    case 41: return ";"
    case 42: return "\\"
    case 43: return ","
    case 44: return "/"
    case 45: return "N"
    case 46: return "M"
    case 47: return "."
    case 48: return "\u{21E5}"
    case 49: return "Space"
    case 50: return "`"
    case 51: return "\u{232B}"
    case 53: return "\u{238B}"
    default: return "Key\(keyCode)"
    }
}
