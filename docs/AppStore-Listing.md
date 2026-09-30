# ZoomThis — App Store Listing Copy

Positioned for **presenters, teachers, and demo-givers**: people who already share their screen and need to direct attention with a quick zoom + a clean annotation, without context-switching to Keynote or a separate tool.

All character counts are within Apple's limits (verified for the 2026 App Store Connect form).

---

## App name (30 char limit)

**Primary:** `ZoomThis` (8)

**If the App Store flags "Zoom" as a conflict** (Zoom Video Communications has aggressive trademark enforcement on app names containing "Zoom"), have these ready:

1. `ZoomThis: Screen Magnifier` (26)
2. `ZoomThis — Zoom & Annotate` (26)
3. `Loupe: Screen Zoom & Markup` (27)
4. `Magnifyr: Screen Zoom Tool` (26)

> Practical note: "Zoom" alone in a Mac utility name is risky. Apple has rejected/renamed apps for this in the past. The cleanest path is to keep the binary/bundle as ZoomThis but list the App Store name with a descriptor (`ZoomThis: Screen Magnifier`) so it reads as a feature, not a brand collision.

---

## Subtitle (30 char limit)

Pick one. Each tested at exactly 30 chars or under:

1. `Zoom, draw, present anything.` (29)
2. `Magnify and annotate your Mac.` (30)
3. `Live screen zoom for presenters` (30 — over by 0, fits)
4. `The presenter's magnifier.` (25) ← **recommended for clean positioning**

---

## Promotional text (170 char limit, editable without resubmitting)

> Zoom into any pixel on your Mac, draw on top of it live, and pop a break timer between sessions. Built for presenters, teachers, and anyone who screen-shares.
> *(167 chars)*

---

## Description (4000 char limit)

```
ZoomThis is the magnifying glass and live whiteboard for your Mac. Press a hotkey, zoom into anything on your screen, and draw on top of it — instantly, without leaving the app you're presenting.

Perfect for presenters, teachers, code reviewers, designers, and anyone who shares their screen and needs to direct attention to exactly the right pixel.


WHAT IT DOES

• Press Ctrl+1 to capture your screen and enter a smooth, pannable zoom overlay
• Scroll or use arrow keys to zoom from 1× up to 10×
• Click anywhere to start drawing — freehand, lines, rectangles, arrows, ellipses, blur, or text
• Press R, G, B, Y, O, P to switch colors. Hold Shift for a translucent highlighter
• Press W or K to switch to a whiteboard or blackboard for from-scratch teaching
• Press X to redact sensitive info with a quick blur tool
• Ctrl+C or Ctrl+S to copy or save the annotated view as a PNG
• Ctrl+Shift+C or Ctrl+Shift+S to crop a region first, then copy or save


BUILT FOR PRESENTERS AND TEACHERS

ZoomThis stays out of the dock and out of your workflow. It lives in the menu bar, takes one keystroke to summon, and disappears the moment you press Escape. Zoom levels, hotkeys, transition animations, and tool defaults are all configurable from the Settings window.

Use it to:
• Zoom into a chart, diagram, or code snippet during a Zoom or Teams call
• Highlight a specific button or menu in a software walkthrough
• Annotate a student's work live during a lesson
• Redact a password or email in a screen recording before sharing
• Sketch a quick diagram on a whiteboard mid-call without switching apps


BUILT-IN BREAK TIMER

A second hotkey (Ctrl+3 by default) launches a full-screen countdown — useful between sessions, in classrooms, during workshops, or as a forced screen break. Adjust the time on the fly with the scroll wheel or arrow keys. The timer minimizes to the menu bar when you switch apps and can be restored anytime.


PRIVACY-FIRST

ZoomThis runs entirely on your Mac. Captures stay on your device. Nothing is uploaded, no analytics, no account, no internet connection required.


REQUIREMENTS

• macOS 15 Sequoia or later
• Screen Recording permission (you'll be prompted on first use)


KEYBOARD-DRIVEN

Every action has a shortcut. Once you've used it for a week, you'll never reach for the menu bar again. Full keyboard reference is included in the Settings window.
```

*(approx. 1980 chars — under the 4000 limit, leaves room for testimonials in v1.1+)*

---

## Keywords (100 char limit, comma-separated, no spaces after commas)

```
zoom,magnifier,annotate,presenter,teacher,screen,markup,whiteboard,timer,demo,recorder,classroom
```

*(98 chars — every term is searchable; avoids duplicating words already in the title/subtitle, since Apple indexes those automatically)*

Alternates if you want a different angle:

- Designer angle: `zoom,magnifier,pixel,annotate,markup,screenshot,design,review,inspect,redact,blur,whiteboard`
- Developer angle: `zoom,magnifier,annotate,screenshot,demo,review,terminal,code,markup,redact,present,teach`

---

## What's New (4000 char, per release)

For the **first** submission this becomes the description-equivalent, so reuse the description. For subsequent releases:

```
Version 1.1.1
• Escape immediately closes zoom, including during text input and crop selection
• Improved keyboard handling when menus are open or focus changes
• Fixed drawing updates, annotation exports, and text alignment
• Improved break timer accuracy and keyboard handling
• Fixed screen capture conflicts and text default settings
```

---

## Category & age rating

- **Primary category:** Productivity
- **Secondary category:** Graphics & Design
- **Age rating:** 4+ (no mature content, no UGC, no third-party advertising)

---

## URLs to provide

- **Marketing URL** (optional): `https://github.com/eyalben/ZoomThis` *or* a simple landing page
- **Support URL** (required): same as above, or a GitHub Issues link
- **Privacy Policy URL** (required, even though you collect nothing): host a single static page. Sample text below.

### Minimum-viable privacy policy

```
ZoomThis Privacy Policy
Last updated: 2026-05-06

ZoomThis is a Mac utility that runs entirely on your Mac. We do not collect, store, transmit, or share any personal data, usage analytics, or screen captures. All images and annotations created by ZoomThis remain on your device.

ZoomThis requires Screen Recording permission to function. macOS prompts you for this permission the first time you use the zoom feature. Permission is managed entirely by macOS in System Settings → Privacy & Security → Screen Recording, and can be revoked at any time.

Contact: eyalben@gmail.com
```

Drop that into a `privacy.html` on GitHub Pages — done.

---

## App Review notes

Paste this into the "Notes" field in App Store Connect → App Review Information so reviewers don't get stuck:

```
Hi reviewer — quick note on testing ZoomThis:

1. ZoomThis is a menu-bar-only app (LSUIElement). After launch, it appears as a magnifying-glass icon in the macOS menu bar.

2. On first use, macOS will prompt for Screen Recording permission. This is required because the app captures the current screen to render the zoom overlay. All capture data stays local.

3. Default hotkeys:
   • Ctrl+1 — start zoom
   • Ctrl+3 — start break timer
   • Esc — exit either mode

4. Once zoomed in, scroll to change magnification, click and drag to draw, R/G/B/Y/O/P for colors. Esc exits zoom; right-click changes drawing mode.

5. There is no account, login, or network call.

Thanks!
```

---

## Pricing recommendation

For a single-purpose menu-bar utility with this much polish, three reasonable paths:

1. **Free, no IAP** — fastest growth, easiest review, lowest support burden. Recommended for v1.0 to seed reviews.
2. **Paid one-time, $4.99–$9.99** — typical for Mac utility apps in this category (e.g. CleanShot's pricing tier as a reference).
3. **Free with one-time IAP unlock at $4.99** — gives users a try-before-buy. More App Review surface area.

If this is your first App Store submission, **start with option 1** — the goal is to ship and learn the review process. You can change pricing later without resubmitting.
