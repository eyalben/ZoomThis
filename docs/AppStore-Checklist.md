# Mac App Store Submission Checklist — ZoomThis

This is the end-to-end punch list to get ZoomThis from its current "Developer ID" state onto the Mac App Store.

Status legend: `[ ]` to do · `[x]` already done in this repo · `[!]` blocker.

---

## 1. Apple Developer & App Store Connect setup

- [x] Paid Apple Developer Program membership (Team ID `M482U8L8HJ`)
- [ ] Create the app record in **App Store Connect**
  - Go to https://appstoreconnect.apple.com → **My Apps** → **+** → **New App**
  - Platform: **macOS**
  - Name: **ZoomThis** (must be globally unique on the App Store; if taken, fall back to `ZoomThis — Screen Zoom & Annotate`)
  - Primary language: English (U.S.)
  - Bundle ID: select **`com.ebs.ZoomThis`** (must already be registered as an App ID in the Developer portal — see next step)
  - SKU: `zoomthis-mac-001` (any unique string)
- [ ] Register the App ID in the Developer portal
  - https://developer.apple.com/account/resources/identifiers → **+** → App IDs → App
  - Bundle ID: `com.ebs.ZoomThis` (explicit)
  - Capabilities: **App Sandbox** (required for App Store)
- [ ] Create a **Mac App Store distribution certificate** (Xcode will offer to do this automatically when archiving with the App Store distribution method, or you can create it manually in the Developer portal: "Mac App Distribution" + "Mac Installer Distribution")

---

## 2. Code signing & entitlements

The current `ZoomThis/ZoomThis.entitlements` enables App Sandbox and user-selected file read/write access:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required for the Mac App Store -->
    <key>com.apple.security.app-sandbox</key>
    <true/>

    <!-- Save annotated PNGs via the user-facing save panel -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

### About ScreenCaptureKit under the sandbox

ScreenCaptureKit works inside the App Sandbox; the user grants access via the Screen Recording privacy prompt (TCC), driven by `NSScreenCaptureUsageDescription`, which you already have. **You do not add a screen-capture entitlement** — that doesn't exist. Just keep the usage description.

> Note: a few sandboxed apps that use older capture APIs need `com.apple.security.temporary-exception.mach-lookup.global-name` for `com.apple.windowserver.active`. ZoomThis uses ScreenCaptureKit, so this should not be required. If you hit "no permission" errors after sandboxing, that's the first thing to check.

### Hardened Runtime

- [x] `ENABLE_HARDENED_RUNTIME = YES` (already set)
- The Mac App Store accepts hardened-runtime apps; no extra entitlements should be needed for ZoomThis given it doesn't load plug-ins, JIT, or unsigned dylibs.

### Sanity check after enabling sandbox

After flipping the sandbox on, build & run from Xcode and re-verify:

1. Zoom hotkey still triggers the overlay
2. Screen recording permission prompt still appears on first run
3. `Ctrl+S` save panel writes a PNG to Desktop / wherever you pick
4. Break timer still works
5. Launch-at-login toggle still works (uses `SMAppService`, sandbox-friendly)

---

## 3. Info.plist — fields to add for the App Store

Your current `ZoomThis/Info.plist` only has the screen-capture usage string and copyright. Add these (Xcode auto-generates many of them via `GENERATE_INFOPLIST_FILE = YES`, but it's worth verifying the final built `Info.plist` contains them):

| Key | Value | Why |
|---|---|---|
| `LSApplicationCategoryType` | `public.app-category.productivity` | App Store category. **Required.** |
| `LSMinimumSystemVersion` | `15.0` | Matches `MACOSX_DEPLOYMENT_TARGET`. Verify the final built `Info.plist` matches the deployment target. |
| `LSUIElement` | `true` | Menu-bar-only app, no dock icon. Already set in the built Info.plist. |
| `NSScreenCaptureUsageDescription` | (your existing string) | TCC prompt copy. Already present. |
| `NSHumanReadableCopyright` | `Copyright © 2026 Eyal Ben-Simon. All rights reserved.` | Already present. |
| `CFBundleShortVersionString` | `1.1.1` (drives the App Store-visible version) | Matches `MARKETING_VERSION`. |
| `CFBundleVersion` | `3` (incremented for every upload) | Internal build number. Bump on every upload. |

**Tip:** sharpen the screen-capture prompt — TCC dialogs are the user's first impression. Suggested copy:

> ZoomThis uses screen recording to capture a snapshot of your screen so you can zoom in, annotate, and share it. Captures stay on your Mac.

---

## 4. Privacy manifest

- [x] `PrivacyInfo.xcprivacy` exists in the project
- [ ] Verify its contents declare:
  - `NSPrivacyTracking` → `false`
  - `NSPrivacyCollectedDataTypes` → empty array (you don't collect anything)
  - `NSPrivacyAccessedAPITypes` → include any required-reason API categories you actually use. ZoomThis is unlikely to need any beyond user defaults (`NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1`).

If the file was scaffolded but empty, populate it now — App Review will reject silent, empty manifests inconsistently.

---

## 5. App icon

Current state: `Assets.xcassets/AppIcon.appiconset/` contains a single `AppIcon-1024.png` (1024×1024, RGBA). That is a valid modern asset-catalog setup — Xcode generates the smaller representations automatically.

**Recommended audit (manual, in any image editor):**

- [ ] Open `AppIcon.svg` (the source) at 1024×1024 and verify it matches Apple's macOS icon "squircle" template — the radius is `~22.37%` of the side (≈229px on a 1024 canvas) and the artwork sits **inset by ~100px on each side** of the canvas, not edge-to-bleed. macOS does **not** auto-mask icons (unlike iOS), so the rounded corners must be baked in to the correct shape.
- [ ] Confirm the PNG has no shadow baked in (macOS adds the system shadow itself).
- [ ] At 16×16 / 32×32 (Quick Look it in Finder after building), the magnifying glass should still read clearly. If the lens detail vanishes at 16px, simplify the small-size art with a separate icon size.
- [ ] Optional: add a layered (Sonoma+) icon by exporting an `.icon` document from Icon Composer, but this is not required.

The icon you have looks on-style. The two things to double-check are (a) the corner radius matches the system squircle and (b) artwork is not bleeding into the corners.

---

## 6. Build settings to verify before archiving

Open Xcode → ZoomThis target → **Signing & Capabilities**:

- [ ] **Signing**: switch the "Release" configuration to use the **Mac App Store** distribution profile (Xcode-managed signing handles this when you choose "App Store Connect" at archive time)
- [ ] **Capabilities → App Sandbox** is on, with "User Selected File · Read/Write" checked
- [ ] **Capabilities → Hardened Runtime** is on (already set in build settings)
- [ ] No "Increment build number on every build" trick that would cause `CFBundleVersion` collisions; you bump it manually

Build settings sanity check (already correct):

- `MACOSX_DEPLOYMENT_TARGET = 15.0`
- `MARKETING_VERSION = 1.1.1`
- `CURRENT_PROJECT_VERSION = 3` (bump this every upload)
- `ENABLE_HARDENED_RUNTIME = YES`
- `PRODUCT_BUNDLE_IDENTIFIER = com.ebs.ZoomThis`

---

## 7. Archive & upload

Xcode UI flow (easiest):

1. Xcode → **Product → Destination → Any Mac (Apple Silicon, Intel)**
2. **Product → Archive**
3. In Organizer, pick the new archive → **Distribute App**
4. Choose **App Store Connect** → **Upload**
5. Let Xcode manage signing → **Upload**

Command-line flow (if you want to keep `build/` scripts):

Create `build/AppStoreExportOptions.plist` (separate from your existing Developer ID one):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>M482U8L8HJ</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
```

Then:

```bash
# 1. Archive
xcodebuild -project ZoomThis.xcodeproj -scheme ZoomThis \
    -configuration Release archive \
    -archivePath build/ZoomThis-AppStore.xcarchive

# 2. Export a signed .pkg for upload
xcodebuild -exportArchive \
    -archivePath build/ZoomThis-AppStore.xcarchive \
    -exportPath build/appstore \
    -exportOptionsPlist build/AppStoreExportOptions.plist

# 3. Upload via Transporter (or `altool` / `notarytool`)
xcrun altool --upload-app \
    --type osx \
    --file build/appstore/ZoomThis.pkg \
    --apiKey "$APP_STORE_CONNECT_KEY_ID" \
    --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
```

Easiest upload tool of all: download **Transporter** from the Mac App Store, drag the `.pkg` in, hit Deliver.

---

## 8. App Store Connect listing

Use the copy from `docs/AppStore-Listing.md`. You'll need:

- App name, subtitle (30 chars), promotional text (170 chars), description (4000 chars), keywords (100 chars)
- Support URL, Marketing URL (optional), Privacy Policy URL (**required**)
- Screenshots — see `docs/AppStore-Screenshots.md` for the shot list
- App icon (App Store Connect pulls the 1024×1024 from your build automatically)
- Age rating questionnaire (all "no" for ZoomThis → 4+)
- Pricing — Free (or paid; pick a tier)
- App Review notes — mention that screen recording permission is required and explain why

### Privacy policy

Even a free app with no data collection needs a privacy policy URL. Host a single page somewhere (GitHub Pages works fine) that says:

> ZoomThis does not collect, store, or transmit any personal data. All screen captures and annotations remain on your Mac and are never sent off-device.

---

## 9. Submit for review

- [ ] Attach the uploaded build to the version
- [ ] Fill out the **App Privacy** questionnaire (Data Not Collected)
- [ ] Fill out **App Review Information**: provide the demo flow ("Launch the app, click the menu bar magnifying glass, choose Zoom; the screen capture permission prompt will appear — approve it; press Ctrl+1 to zoom").
- [ ] Submit

Mac App Store review usually takes 24–72 hours. Most rejections for a utility like this come from:

- Missing privacy policy URL
- Sandbox entitlement missing → app crashes when reviewer launches
- Screen recording usage description too vague
- App icon shape/transparency issues
- Trademark on the name (be ready to rename if Zoom Video Communications objects to "Zoom" in the title — see `AppStore-Listing.md` for fallbacks)
