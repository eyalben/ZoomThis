# ZoomThis — App Store Screenshot Capture Guide

The Mac App Store requires **at least one** screenshot, allows up to **ten**, and orders them by upload sequence. The first three matter most — they're what's visible above the fold on every Mac that opens your listing.

This guide gives you a 6-shot plan that tells a complete story: what the app does → who it's for → why it's good. Each shot has the setup, the exact key sequence to capture it, and the caption to overlay.

---

## Required dimensions

The Mac App Store accepts these sizes (PNG or JPEG, RGB, no alpha):

- **2880 × 1800** (Retina 16:10) — recommended, what modern MacBooks render at
- **2560 × 1600** (also accepted)
- **1280 × 800** (1× equivalent, also accepted)

Upload Retina (`2880×1800`). All six shots must be the **same** dimension.

---

## Pre-capture setup (one-time)

Before you start, set the stage so every screenshot looks consistent and intentional:

1. **Display resolution** — System Settings → Displays → set your built-in display to "Default" or the resolution that maps to **1440×900 points** (which renders at 2880×1800 px Retina). This is the canonical MacBook resolution Apple uses in marketing.
2. **Wallpaper** — pick a clean, low-contrast wallpaper that won't fight the UI. The default macOS Sequoia/Tahoe wallpaper, or a solid muted color, work well.
3. **Menu bar** — temporarily hide menu bar items you don't need (use Bartender, Hidden Bar, or just disable extras in System Settings) so the menu bar is clean.
4. **Dock** — hide it (System Settings → Desktop & Dock → Automatically hide and show the Dock). ZoomThis is a menu-bar app so the dock isn't relevant.
5. **Time & battery** — optional, but Apple's marketing tradition is **9:41 AM** with full battery. Not required, but it photographs well.
6. **Theme** — Light mode reads better in the App Store; capture all six in Light mode for visual consistency.
7. **Demo content** — open one or two believable "stage" apps. Recommended:
   - **Keynote** with a chart slide (for shots 1, 2, 3)
   - **Safari** on a Wikipedia article with a diagram (for shot 4)
   - **Xcode or VS Code** with code visible (for shot 5, optional)

---

## Capture command

Use macOS's built-in screenshot tool — not ZoomThis's own export, since you want the whole screen including the menu bar:

```bash
# Captures the full screen to ~/Desktop with a 5-second delay
# (gives you time to set up the zoom overlay first)
screencapture -T 5 -t png ~/Desktop/zoomthis-shot-01.png
```

Or use **Cmd+Shift+3** for a no-delay full-screen capture. For the shots that need the zoom overlay active, the timer flag is friendlier — start the capture, hit Ctrl+1, position the zoom, wait for the click.

---

## The 6-shot plan

> **Captioning:** add a 1-line headline in big type (~80–100pt) and a 1-line subhead (~36pt) above each screenshot. Use Figma, Sketch, or Keynote to lay them out. Apple-style screenshots typically have ~20% of the canvas devoted to caption text above a slightly inset device image. You can also just upload the raw screenshot with no overlay — both work, captioned looks more professional.

---

### Shot 1 — The hero shot (most important)

**What it shows:** The zoomed overlay in action with a red arrow pointing at a chart on a Keynote slide.

**Setup:**
1. Open Keynote with a slide containing a bar chart (or any data viz)
2. Press `Ctrl+1` to enter zoom
3. Scroll up to ~3× zoom, center on the tallest bar
4. Press `R` to switch to red, then `Ctrl+Shift` and drag from off-screen toward the bar to draw an arrow
5. Capture full screen

**Headline:** `Zoom in. Point. Done.`
**Subhead:** `One hotkey to magnify and annotate anything on your screen.`

---

### Shot 2 — Live drawing on a real app

**What it shows:** A freehand red circle around something specific in a real app (a button in an interface, a paragraph, a UI element).

**Setup:**
1. Open Safari to a real-looking page (a product detail page, dashboard, or article)
2. `Ctrl+1` → zoom to ~2.5×
3. `R` for red, then click-drag to circle a specific UI element
4. Optionally hit `T` and type a short label like "this is the bug"

**Headline:** `Annotate live during demos.`
**Subhead:** `Freehand, lines, arrows, ellipses, blur, and text — keyboard-driven, no toolbar.`

---

### Shot 3 — The whiteboard mode

**What it shows:** ZoomThis as a clean whiteboard with a quick sketched diagram in two colors.

**Setup:**
1. `Ctrl+1` to zoom (anywhere — content gets replaced)
2. Press `W` for whiteboard
3. Draw a simple architecture diagram: 3 boxes connected by arrows, a couple of labels in different colors (`R`, `B`, `G`)
4. Capture

**Headline:** `A whiteboard, one keystroke away.`
**Subhead:** `Press W mid-call to sketch on a clean surface — no app-switching, no setup.`

---

### Shot 4 — Blur / redact for screen recordings

**What it shows:** A real-looking app (email, dashboard, code) with sensitive info visibly blurred out by the X-tool.

**Setup:**
1. Open Mail with an inbox visible (use a test account or compose a fake email so no real names show)
2. `Ctrl+1` → zoom in
3. Press `X` and drag-paint over names, email addresses, or the subject line
4. Capture

**Headline:** `Redact before you record.`
**Subhead:** `Blur names, emails, and any sensitive pixels before sharing.`

---

### Shot 5 — The break timer

**What it shows:** The full-screen black countdown timer at a believable mid-break time like `04:32`.

**Setup:**
1. Press `Ctrl+3`
2. Scroll to set the timer to ~5:00
3. Wait until it reads ~04:32 or similar (avoid round numbers — looks more real)
4. Capture

**Headline:** `Force the break.`
**Subhead:** `A focused, distraction-free countdown between sessions.`

---

### Shot 6 — Settings / power-user proof

**What it shows:** The Settings window open on the Zoom or Timer tab, showing the customizable hotkey and the breadth of options. This signals "polished, configurable, real product."

**Setup:**
1. Click the menu bar icon → Settings
2. Click the **Zoom** tab
3. Resize the window so it's centered and not gigantic
4. Capture

**Headline:** `Tuned to your workflow.`
**Subhead:** `Customize hotkeys, zoom levels, animation, and tool defaults.`

---

## Caption layout template (recommended)

Use this layout in Figma/Sketch for every shot:

```
┌──────────────────────────────────────────────┐
│                                              │
│   HEADLINE (80–100pt, bold, dark)            │  ← top 25% of canvas
│   Subhead (36pt, regular, 60% opacity)       │
│                                              │
├──────────────────────────────────────────────┤
│                                              │
│                                              │
│         [ Screenshot, slightly inset ]       │  ← bottom 75%
│                                              │
│                                              │
└──────────────────────────────────────────────┘
```

Keep the typography consistent across all six. SF Pro or Inter both look native on Mac.

---

## Quick polish checklist before uploading

- [ ] All six screenshots are exactly `2880 × 1800` pixels
- [ ] Same wallpaper, same time-of-day on the menu bar across all six
- [ ] No personal info visible (email addresses, names in browser tabs, etc.)
- [ ] No notification badges visible in the menu bar
- [ ] No browser tab clutter — at most 2–3 tabs visible
- [ ] Mouse cursor either consistently shown or consistently hidden (cursor-on-target works for shot 1; hide it elsewhere — Cmd+Shift+5 has a "Show cursor" toggle)
- [ ] PNG format, no alpha channel
- [ ] First three shots tell the strongest story — those are the ones above the fold
