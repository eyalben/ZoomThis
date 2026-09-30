# App Icon Audit — ZoomThis

Source reviewed: `AppIcon.svg` (the master) and `ZoomThis/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (the export).

**Overall:** the icon is well-made and on-style for macOS. Two changes recommended before App Store submission, plus one optional polish.

---

## What's good

- **Squircle radius is correct.** Your SVG uses `rx="228"` on a 1024 canvas. Apple's macOS app icon template uses a squircle at ~22.37% (≈229px). 228 is within rounding error — perfect.
- **Glass + metal + gradient styling** is consistent with macOS Big Sur+ icon conventions.
- **Concept reads instantly** — magnifying glass with a `+` crosshair literally communicates "zoom" at small sizes.
- **Asset catalog is correctly configured** — single 1024×1024 entry; modern Xcode generates the smaller representations automatically.
- **PNG export is technically correct** — 1024×1024, 8-bit/color RGBA, non-interlaced.

---

## Issues to fix before submitting

### 1. Remove the baked-in drop shadow (recommended)

In `AppIcon.svg`, the magnifying-glass group has `filter="url(#shadow)"` applied (lines 80 + 46–48). macOS automatically renders a system shadow under every app icon. Adding one in the artwork **stacks** the two shadows and produces a heavier-than-stock look that reads as "non-Apple."

**Fix:** remove `filter="url(#shadow)"` from line 80, then re-export the PNG. Apple's macOS HIG explicitly says: "Don't add effects to your macOS app icon's shape — like inner glows, outer glows, or drop shadows. The system applies these effects for you."

### 2. Verify the PNG transparency outside the squircle

The PNG is RGBA, which is correct for macOS (the corners outside the squircle should be transparent so the icon shape reads on any background). Sanity-check by opening `AppIcon-1024.png` in Preview → File → Show Inspector → confirm the four corners outside the rounded square are α=0.

If the corners ended up filled with the blue background instead of transparent (it can happen during SVG → PNG export), the icon will render as a hard rectangle behind the system squircle mask in some contexts.

---

## Optional polish

### 3. Inset the artwork slightly from the squircle edges

Apple's macOS app icon template recommends the artwork **not** bleed all the way to the squircle edge. The standard layout uses ~100px inset on each side of a 1024 canvas — leaving roughly 824×824 of "live area" and 100px of breathing room.

Your current magnifying-glass extends close to the edges. This is a stylistic choice (many indie apps do full-bleed), but compared against Apple's first-party icons (Preview, Calculator, App Store) yours will read as slightly busier at small sizes.

If you want the more polished look, scale the magnifying-glass group down to ~80% and re-center.

### 4. Test at 16×16 in Finder

After re-exporting, build the app and look at it in Finder at `View → as Icons → smallest`. At 16px, only the lens + handle silhouette will read. If the rim becomes a fuzzy gray ring and the handle disappears, you'd benefit from creating a separate simplified variant for small sizes — but for now a single 1024 should pass review.

---

## App Store requirements (already met)

- ✅ 1024×1024 PNG
- ✅ sRGB color space (RGBA is fine for macOS)
- ✅ Squircle shape in artwork (macOS does **not** auto-mask, unlike iOS)
- ✅ No 1× duplicate needed in modern asset catalogs

---

## Quick fix workflow

```bash
# 1. Open AppIcon.svg in your editor
# 2. Remove `filter="url(#shadow)"` from the <g> on line 80
# 3. Optional: wrap the magnifying-glass <g> in <g transform="translate(102, 102) scale(0.8)">
#    to inset the artwork ~10% on each side

# 4. Re-export to PNG (e.g., with rsvg-convert)
rsvg-convert -w 1024 -h 1024 AppIcon.svg -o ZoomThis/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

# 5. Build & inspect in Finder, then archive for the App Store
```

If you don't have `rsvg-convert`, drag the SVG into Figma or Sketch, set the frame to 1024×1024, and export as PNG with no background.
