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
                .background(.quaternary)
                .cornerRadius(6)

            Button(isRecording ? "Press keys..." : "Record") {
                startRecording()
            }
            .disabled(isRecording)
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
                // Escape: revert to saved values and re-register
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

// MARK: - Settings Tab Enum

private enum SettingsTab: String, CaseIterable {
    case zoom = "Zoom"
    case timer = "Timer"
    case about = "About"
}

// MARK: - Main Settings View

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: SettingsTab = .zoom

    private var showPermissionOverlay: Bool {
        !appState.hasScreenRecordingPermission
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                settingsContent
                    .blur(radius: showPermissionOverlay ? 8 : 0)
                    .allowsHitTesting(!showPermissionOverlay)

                if showPermissionOverlay {
                    permissionOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showPermissionOverlay)
            Divider()
            statusBar
        }
        .frame(width: 640, height: 480)
        .onAppear { appState.startPermissionPolling() }
        .onDisappear { appState.stopPermissionPolling() }
    }

    // MARK: - Settings Content

    private var settingsContent: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            switch selectedTab {
            case .zoom:
                zoomTab
            case .timer:
                timerTab
            case .about:
                aboutTab
            }
        }
    }

    // MARK: - Permission Overlay

    private var permissionOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            VStack(spacing: 20) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                Text("ZoomIt needs Screen Recording")
                    .font(.title2.bold())

                Text("This permission is required to capture and zoom the screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Open System Settings") {
                    appState.permissionManager.openScreenRecordingSettings()
                }
                .controlSize(.large)
            }
            .padding(32)
        }
    }

    // MARK: - Zoom Tab

    private var zoomTab: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 12) {
            // ACTIVATION
            sectionHeader("ACTIVATION")
            VStack(spacing: 8) {
                HotkeyRecorderView(
                    label: "Zoom shortcut:",
                    keyCode: $appState.hotkeyKeyCode,
                    modifiers: $appState.hotkeyModifiers,
                    onStartRecording: {
                        appState.hotkeyManager.unregister(id: AppState.zoomHotkeyID)
                    }
                ) {
                    appState.saveSettings()
                    appState.registerHotkey()
                }

                HStack {
                    Text("Magnification:")
                    Slider(value: $appState.initialZoomFactor, in: 1.25...4.0, step: 0.25)
                    Text(String(format: "%.2fx", appState.initialZoomFactor))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50, alignment: .trailing)
                }
                .onChange(of: appState.initialZoomFactor) { _, _ in appState.saveSettings() }

                Toggle("Animate zoom in/out", isOn: $appState.zoomAnimationEnabled)
                    .onChange(of: appState.zoomAnimationEnabled) { _, _ in appState.saveSettings() }
            }
            .padding(.horizontal, 20)

            // DRAWING
            sectionHeader("DRAWING")
            VStack(spacing: 8) {
                HStack {
                    Text("Pen color:")
                    Spacer()
                    Picker("", selection: $appState.defaultPenColor) {
                        Text("Red").tag("red")
                        Text("Green").tag("green")
                        Text("Blue").tag("blue")
                        Text("Yellow").tag("yellow")
                        Text("Orange").tag("orange")
                        Text("Pink").tag("pink")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }
                .onChange(of: appState.defaultPenColor) { _, _ in appState.saveSettings() }

                HStack {
                    Text("Pen thickness:")
                    Slider(value: $appState.defaultPenThickness, in: 1...30, step: 1)
                    Text(String(format: "%.0f", appState.defaultPenThickness))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 30, alignment: .trailing)
                }
                .onChange(of: appState.defaultPenThickness) { _, _ in appState.saveSettings() }

                HStack {
                    Text("Font size:")
                    Slider(value: $appState.defaultTextFontSize, in: 8...120, step: 2)
                    Text(String(format: "%.0f", appState.defaultTextFontSize))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 30, alignment: .trailing)
                }
                .onChange(of: appState.defaultTextFontSize) { _, _ in appState.saveSettings() }
            }
            .padding(.horizontal, 20)

            // QUICK REFERENCE
            sectionHeader("QUICK REFERENCE")
            quickReferenceCard {
                twoColumnShortcuts([
                    ("Mouse", "Pan viewport"),
                    ("Scroll", "Zoom in/out"),
                    ("Left-click", "Draw freehand"),
                    ("Right-click", "Back to pan"),
                    ("Shift+drag", "Line"),
                    ("Ctrl+drag", "Rectangle"),
                    ("Option+drag", "Ellipse"),
                    ("Ctrl+Shift+drag", "Arrow"),
                    ("R/G/B/Y/O/P", "Pen color"),
                    ("Shift+color", "Highlight"),
                    ("X", "Blur pen"),
                    ("T / Shift+T", "Text L/R"),
                    ("W / K / E", "White/Black/Erase"),
                    ("Ctrl+Z", "Undo"),
                    ("Ctrl+C / Ctrl+S", "Copy / Save"),
                    ("Escape", "Exit zoom"),
                ])
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Timer Tab

    private var timerTab: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 12) {
            // ACTIVATION
            sectionHeader("ACTIVATION")
            VStack(spacing: 8) {
                HotkeyRecorderView(
                    label: "Timer shortcut:",
                    keyCode: $appState.timerHotkeyKeyCode,
                    modifiers: $appState.timerHotkeyModifiers,
                    onStartRecording: {
                        appState.hotkeyManager.unregister(id: AppState.timerHotkeyID)
                    }
                ) {
                    appState.saveSettings()
                    appState.registerTimerHotkey()
                }
            }
            .padding(.horizontal, 20)

            // DEFAULTS
            sectionHeader("DEFAULTS")
            VStack(spacing: 8) {
                HStack {
                    Text("Duration (minutes):")
                    Stepper(
                        value: Binding(
                            get: { Int(appState.defaultTimerDuration / 60) },
                            set: { appState.defaultTimerDuration = TimeInterval($0 * 60) }
                        ),
                        in: 1...120
                    ) {
                        Text("\(Int(appState.defaultTimerDuration / 60))")
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .onChange(of: appState.defaultTimerDuration) { _, _ in appState.saveSettings() }
            }
            .padding(.horizontal, 20)

            // QUICK REFERENCE
            sectionHeader("QUICK REFERENCE")
            quickReferenceCard {
                twoColumnShortcuts([
                    ("Scroll / Up/Down", "+/- 10 seconds"),
                    ("Ctrl+Scroll/arrows", "+/- 30 seconds"),
                    ("Escape", "Dismiss timer"),
                    ("Loses focus", "Minimizes to menu"),
                    ("Hotkey again", "Restore if minimized"),
                ])
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("ZoomIt")
                .font(.title.bold())

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Screen zoom, annotation, and break timer tool for macOS.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.hasScreenRecordingPermission ? .green : .red)
                    .frame(width: 8, height: 8)
                Text("Screen Recording")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onTapGesture {
                if !appState.hasScreenRecordingPermission {
                    appState.permissionManager.openScreenRecordingSettings()
                }
            }

            Spacer()

            Toggle("Launch at Login", isOn: Binding(
                get: { appState.isLaunchAtLoginEnabled },
                set: { _ in appState.toggleLaunchAtLogin() }
            ))
            .toggleStyle(.checkbox)
            .font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 4)
    }

    private func quickReferenceCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .background(.quaternary.opacity(0.5))
            .cornerRadius(8)
            .padding(.horizontal, 20)
    }

    private func twoColumnShortcuts(_ items: [(String, String)]) -> some View {
        let midpoint = (items.count + 1) / 2
        let leftColumn = Array(items.prefix(midpoint))
        let rightColumn = Array(items.suffix(from: midpoint))

        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(leftColumn.enumerated()), id: \.offset) { _, item in
                    dotLeaderRow(key: item.0, desc: item.1)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(rightColumn.enumerated()), id: \.offset) { _, item in
                    dotLeaderRow(key: item.0, desc: item.1)
                }
            }
        }
    }

    private func dotLeaderRow(key: String, desc: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Shortcut Display Helpers

func shortcutString(keyCode: UInt32, modifiers: UInt32) -> String {
    carbonModifiersToString(modifiers) + keyCodeToString(keyCode)
}

func carbonModifiersToString(_ modifiers: UInt32) -> String {
    var result = ""
    if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
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
    case 36: return "↩"
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
    case 48: return "⇥"
    case 49: return "Space"
    case 50: return "`"
    case 51: return "⌫"
    case 53: return "⎋"
    default: return "Key\(keyCode)"
    }
}
