# DMG Distribution Guide

## Prerequisites

1. **Notarized app** — Export from Xcode Organizer using "Developer ID" distribution (not App Store). Xcode will notarize automatically. The exported `.app` is typically saved to `~/Downloads/ZoomThis.app`.
2. **Terminal with Full Disk Access** — `hdiutil` needs access to read signed app bundles. Grant Full Disk Access to your terminal in System Settings > Privacy & Security > Full Disk Access.
3. **Version** — Update `MARKETING_VERSION` in the Xcode project before archiving.

## Step 1: Archive and Export

```bash
# Archive
xcodebuild -project ZoomThis.xcodeproj -scheme ZoomThis -configuration Release \
  archive -archivePath build/ZoomThis.xcarchive

# Export with Developer ID (for direct distribution, not App Store)
xcodebuild -exportArchive \
  -archivePath build/ZoomThis.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist build/ExportOptions.plist
```

Or use Xcode GUI: Open the archive in Organizer > Distribute App > Developer ID > Export.

## Step 2: Verify Notarization

```bash
spctl --assess --verbose=2 ~/Downloads/ZoomThis.app
# Expected: "accepted source=Notarized Developer ID"
```

## Step 3: Create the DMG

```bash
VERSION=1.1.1  # Update this to match the current version

rm -rf build/dmg_staging build/ZoomThis-${VERSION}.dmg
mkdir -p build/dmg_staging
cp -R ~/Downloads/ZoomThis.app build/dmg_staging/
ln -s /Applications build/dmg_staging/Applications
hdiutil create -volname "ZoomThis" \
  -srcfolder build/dmg_staging \
  -ov -format UDZO \
  build/ZoomThis-${VERSION}.dmg
```

This creates a compressed DMG with:
- `ZoomThis.app` — the notarized application
- `Applications` symlink — so users can drag-to-install

## Step 4: Upload to GitHub Release

```bash
VERSION=1.1.1

# Verify DMG was created
ls -lh build/ZoomThis-${VERSION}.dmg

# Upload to existing release (--clobber replaces if already uploaded)
gh release upload v${VERSION} build/ZoomThis-${VERSION}.dmg --clobber
```

## DMG Background Image

There is currently no custom DMG background image. The DMG uses the default Finder view. To add a custom background in the future:

1. Create a background image (typically 600x400 or similar)
2. Save it to `docs/dmg-background.png`
3. Use a tool like [`create-dmg`](https://github.com/create-dmg/create-dmg) for styled DMGs:
   ```bash
   create-dmg \
     --volname "ZoomThis" \
     --background "docs/dmg-background.png" \
     --window-size 600 400 \
     --icon-size 100 \
     --icon "ZoomThis.app" 150 200 \
     --app-drop-link 450 200 \
     build/ZoomThis-${VERSION}.dmg \
     build/dmg_staging/ZoomThis.app
   ```

## Cleanup

```bash
rm -rf build/dmg_staging
```
