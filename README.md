# ZoomThis

A lightweight macOS menu bar app for zooming into your screen, annotating live, and running a break timer — built for presenters, teachers, and anyone who needs to highlight what's on screen.

## Features

### Screen Zoom
- Captures a screenshot and displays a smooth, pannable, zoomable overlay
- Animated zoom in/out transition (optional)
- Configurable initial magnification (1.25×–4×)
- Zoom range from 1× to 10× during use

### Drawing & Annotation
Draw on top of the zoomed view with a full set of tools:

| Tool | How to activate |
|------|----------------|
| Freehand | Left-drag |
| Line | Shift+drag |
| Rectangle | Ctrl+drag |
| Ellipse | Option+drag |
| Arrow | Ctrl+Shift+drag |
| Text | `T` (left-aligned) / `Shift+T` (right-aligned) |
| Blur/redact | `X` then drag |

**Colors:** `R` Red · `G` Green · `B` Blue · `Y` Yellow · `O` Orange · `P` Pink
Add `Shift` to any color key for a semi-transparent **highlight** variant.

**Board modes:** `W` Whiteboard · `K` Blackboard · `E` Erase all annotations

### Export
- `Ctrl+C` — copy current zoomed view to clipboard
- `Ctrl+S` — save current zoomed view as PNG
- `Ctrl+Shift+C` — drag to select a crop region, copy to clipboard
- `Ctrl+Shift+S` — drag to select a crop region, save as PNG

### Break Timer
Full-screen countdown timer for structured breaks. Minimizes to the menu bar when it loses focus and can be restored with the hotkey or menu.

## Keyboard Shortcuts

### Zoom Mode (Panning)
| Key | Action |
|-----|--------|
| Mouse move | Pan viewport |
| Scroll wheel | Zoom in/out |
| ↑ / ↓ arrow | Zoom in/out by step |
| Left-click | Enter drawing mode |
| Right-click / Esc | Exit zoom |

### Zoom Mode (Drawing)
| Key | Action |
|-----|--------|
| Right-click | Return to pan mode |
| Esc | Exit zoom |
| `Ctrl+Z` / `Cmd+Z` | Undo last stroke |
| Space | Center cursor |
| ↑ / ↓ arrow | Zoom in/out |
| `Ctrl` + ↑/↓ | Increase/decrease line width |
| `Ctrl` + scroll | Adjust line width |

### Break Timer
| Key | Action |
|-----|--------|
| Scroll / ↑↓ | ±10 seconds |
| Ctrl+Scroll / Ctrl+↑↓ | ±30 seconds |
| Esc | Dismiss timer |

## Requirements

- macOS 13 Ventura or later
- Screen Recording permission (prompted on first use)

## Installation

1. Clone the repository
2. Open `ZoomThis.xcodeproj` in Xcode
3. Build and run (`⌘R`)
4. ZoomThis appears in the menu bar as a magnifying glass icon
5. Grant Screen Recording permission when prompted

### Default Hotkeys
- **Zoom:** `Ctrl+1`
- **Break Timer:** `Ctrl+3`

Both hotkeys are fully customizable in Settings (`⌘,`).

## Settings

Open Settings from the menu bar icon or press `⌘,`:

- **Zoom tab** — hotkey, initial magnification, animation toggle, default pen color/thickness/font size, quick reference card
- **Timer tab** — hotkey, default duration (1–120 minutes), quick reference card
- **About tab** — version info

**Launch at Login** can be toggled from the status bar at the bottom of the Settings window.

## Architecture

The app is a pure SwiftUI/AppKit hybrid macOS app with no external dependencies.

| File | Responsibility |
|------|---------------|
| `ZoomThisApp.swift` | App entry point, menu bar extra, window scene |
| `AppState.swift` | Observable app state, settings persistence, hotkey registration |
| `ZoomOverlayController.swift` | Zoom overlay lifecycle; panning/drawing/text-input state machine |
| `ZoomOverlayView.swift` | NSView that renders the zoomed screenshot and all annotations |
| `DrawingAction.swift` | Value-type enum of renderable drawing actions (CoreGraphics) |
| `DrawingState.swift` | Mutable drawing session state (actions, current tool, color, width) |
| `BreakTimerController.swift` | Break timer window lifecycle and countdown logic |
| `BreakTimerView.swift` | Full-screen timer NSView |
| `HotkeyManager.swift` | Carbon `RegisterEventHotKey` wrapper |
| `ScreenCaptureManager.swift` | ScreenCaptureKit screenshot capture |
| `PermissionManager.swift` | Screen recording permission check and settings deep-link |
| `OverlayPanel.swift` | NSPanel subclass that stays above full-screen content |
| `ToolTipHUD.swift` | Floating HUD for tool/color feedback |
| `SettingsView.swift` | SwiftUI settings UI with hotkey recorder |

## License

MIT
