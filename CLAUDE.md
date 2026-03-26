# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a pure Swift/AppKit macOS app with no external dependencies (no SPM packages, no CocoaPods). Build exclusively through Xcode:

```bash
# Build from command line
xcodebuild -project ZoomThis.xcodeproj -scheme ZoomThis -configuration Release build

# Archive + export (signed .app in build/export/)
xcodebuild -project ZoomThis.xcodeproj -scheme ZoomThis -configuration Release archive -archivePath build/ZoomThis.xcarchive
xcodebuild -exportArchive -archivePath build/ZoomThis.xcarchive -exportPath build/export -exportOptionsPlist build/ExportOptions.plist
```

There are no tests, no linter, and no CI pipeline. The app requires macOS 15.0+ (Sequoia) and Screen Recording permission at runtime.

Bundle ID: `com.ebs.ZoomThis`. The app is sandboxed (`com.apple.security.app-sandbox`) with user-selected file read-write access.

## Architecture

ZoomThis is a **menu bar app** (no dock icon) with two full-screen overlay modes: **Zoom** and **Break Timer**. Both modes capture the full screen and display content in a borderless `NSPanel` at `.screenSaver` window level.

### Core flow

`ZoomThisApp` (SwiftUI `@main`) creates a `MenuBarExtra` and a settings `Window`. All state lives in a single `@Observable` class:

- **`AppState`** — central coordinator. Owns the five manager/controller objects, persists settings to `UserDefaults`, and gates activation (zoom and timer are mutually exclusive).

### Zoom overlay

The zoom pipeline is: `ScreenCaptureManager` (captures via ScreenCaptureKit) → `ZoomOverlayController` (event routing + state machine) → `ZoomOverlayView` (CoreGraphics rendering).

**`ZoomOverlayController`** implements a three-mode state machine: **Panning → Drawing → TextInput**. All keyboard/mouse events flow through `handleEvent()` which dispatches to the current mode's handler. Mode transitions are documented in the class's doc comment. Key design details:

- Events are intercepted via `NSEvent.addLocalMonitorForEvents` + a global monitor for Escape
- Drawing tool selection is modifier-key-based (Shift=line, Ctrl=rect, Option=ellipse, Ctrl+Shift=arrow)
- Coordinates convert between screen space, view space, and image space via `imagePoint(from:)` / `viewPoint(from:)`
- Export (copy/save) renders the current view including annotations; crop export uses a drag-to-select interaction

**`ZoomOverlayView`** is an `NSView` that renders via `draw(_:)` using CoreGraphics directly (no SwiftUI). It maintains a **committed drawing layer cache** (`CGImage`) that is invalidated when actions are added/undone, avoiding re-rendering all strokes every frame.

**`DrawingAction`** is an enum where each case knows how to `render(in:imageSize:sourceImage:)` into a `CGContext`. All drawing happens in image-space coordinates with a Y-down flipped context. The blur tool works by rendering a pixelated version of the source image clipped to the stroke path.

### Break timer

`BreakTimerController` manages a simple countdown in a full-screen black window. `BreakTimerView` renders the MM:SS display via CoreGraphics text drawing. The timer auto-minimizes when the app loses focus and can be restored from the menu bar.

### Supporting types

- **`HotkeyManager`** — registers global/local keyboard shortcuts via `NSEvent` monitors (not Carbon `RegisterEventHotKey`). Converts between Cocoa `NSEvent.ModifierFlags` and Carbon modifier constants.
- **`ModifierUtils`** — standalone functions for modifier/keycode string conversion (used in settings UI and hotkey display).
- **`OverlayPanel`** — trivial `NSPanel` subclass that returns `true` for `canBecomeKey`/`canBecomeMain`.
- **`ToolTipHUD`** — ephemeral bottom-left tooltip panel showing active color/tool with auto-fade.
- **`DrawingState`** — mutable bag holding the action list, current color, line width, and in-progress points.
- **`PermissionManager`** — thin wrapper around `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`.

### Settings

`SettingsView` is SwiftUI with three tabs (About, Zoom, Timer). `HotkeyRecorderView` is a reusable component that temporarily unregisters the hotkey, captures a keypress, then re-registers. Settings are persisted via `AppState.saveSettings()` → `UserDefaults`.

## Conventions

- **No SwiftUI for overlays** — the zoom and timer overlays use AppKit `NSView` + CoreGraphics for performance and precise event control. SwiftUI is only used for the settings window and menu bar.
- **Coordinate systems** — image coordinates are Y-down (CGImage convention). View coordinates are Y-up (AppKit convention). The `ZoomOverlayView` handles conversion. Drawing contexts are explicitly flipped to Y-down before rendering.
- **No Carbon framework import** — modifier constants are defined locally in `ModifierUtils.swift` to maintain sandbox compatibility.
- **Logging** — uses `os.log` (`Logger`) instead of `print`/`NSLog`.
