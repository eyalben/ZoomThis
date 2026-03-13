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

- macOS 15 Sequoia or later
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

Both hotkeys are fully customizable in Settings.

**Launch at Login** can be toggled from the status bar at the bottom of the Settings window.


## License

MIT
