# macOS Release And Update Flow

This is the exact process to ship a new Rocky macOS version and make the in-app updater pick it up.

## Before You Start

- Local app repo: `/Users/anilpal/Desktop/Rocky`
- Updates/releases repo: `Wuiserous/rocky-pet-updates`
- Updater metadata file: `macos/version.json` in the updates repo
- Release assets are uploaded to GitHub Releases

Keep these 4 things in sync for every release:

1. Xcode app version
2. Xcode build number
3. GitHub release tag
4. `macos/version.json`

## Versioning Rule

Recommended pattern:

- Version: `1.2.0`
- Build: `3`
- Release tag: `v1.2.0`
- DMG filename: `Rocky-1.2.0.dmg`

## 1. Bump The App Version

From the Rocky repo:

```bash
cd /Users/anilpal/Desktop/Rocky
```

Edit the Xcode project version values:

```bash
perl -0pi -e 's/MARKETING_VERSION = 1\.1\.1;/MARKETING_VERSION = 1.2.0;/g; s/CURRENT_PROJECT_VERSION = 2;/CURRENT_PROJECT_VERSION = 3;/g' macos/Rocky.xcodeproj/project.pbxproj
```

Adjust the old and new version numbers each release.

## 2. Build The Release App

```bash
cd /Users/anilpal/Desktop/Rocky
xcodebuild -project macos/Rocky.xcodeproj -scheme Rocky -configuration Release build
```

Find the built app:

```bash
find ~/Library/Developer/Xcode/DerivedData -path "*/Build/Products/Release/Rocky.app" | head -n 1
```

Save it into a shell variable:

```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Build/Products/Release/Rocky.app" | head -n 1)
echo "$APP_PATH"
```

Verify the built version:

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist"
```

Expected example output:

- `1.2.0`
- `3`

## 3. Create The DMG

```bash
rm -rf ~/Desktop/rocky-release
mkdir -p ~/Desktop/rocky-release
cp -R "$APP_PATH" ~/Desktop/rocky-release/Rocky.app
ln -s /Applications ~/Desktop/rocky-release/Applications
hdiutil create -volname "Rocky" -srcfolder ~/Desktop/rocky-release -ov -format UDZO ~/Desktop/Rocky-1.2.0.dmg
```

Check the staging folder:

```bash
ls ~/Desktop/rocky-release
```

It should contain:

- `Rocky.app`
- `Applications`

Check the DMG size:

```bash
ls -lh ~/Desktop/Rocky-1.2.0.dmg
```

Test the DMG locally:

```bash
open ~/Desktop/Rocky-1.2.0.dmg
```

It should show:

- `Rocky.app`
- `Applications`

## 4. Create The GitHub Release

Repo:

- `Wuiserous/rocky-pet-updates`

In GitHub:

1. Open `Releases`
2. Click `Draft a new release`
3. Fill these values:

- Tag: `v1.2.0`
- Target: `main`
- Release title: `Rocky macOS v1.2.0`

Release notes template:

```md
Rocky macOS v1.2.0

What's new:
- Describe your main change 1
- Describe your main change 2
- Describe your main change 3

Install:
1. Download Rocky-1.2.0.dmg
2. Open the DMG
3. Drag Rocky into Applications
4. Open Rocky from Applications

Note:
If macOS blocks Rocky on first launch, right-click Rocky and choose Open.
```

Upload this asset:

- `Rocky-1.2.0.dmg`

Publish the release.

After publishing, verify the asset URL opens:

```text
https://github.com/Wuiserous/rocky-pet-updates/releases/download/v1.2.0/Rocky-1.2.0.dmg
```

## 5. Update The Updater Metadata

Update `macos/version.json` in the `rocky-pet-updates` repo.

Template:

```json
{
  "version": "1.2.0",
  "build": "3",
  "download_url": "https://github.com/Wuiserous/rocky-pet-updates/releases/download/v1.2.0/Rocky-1.2.0.dmg",
  "key_note": "Rocky macOS v1.2.0 is available.",
  "whats_new": [
    "Describe your main change 1",
    "Describe your main change 2",
    "Describe your main change 3"
  ]
}
```

Important:

- `version` must match the app version
- `build` must match the app build
- `download_url` must match the exact uploaded asset name

Push the updated file to `main`.

## 6. Test The Updater

From the already installed older Rocky app:

1. Open Rocky
2. Open Control Center
3. Click `Check for Updates`

Expected behavior:

1. Rocky downloads the new DMG
2. Rocky installs the update
3. Rocky quits
4. Rocky relaunches

Then test again:

1. Open Control Center
2. Click `Check for Updates`

Expected result:

- `You're already on the latest Rocky version.`

## 7. If The Updater Downloads Again By Mistake

Check these first:

1. App version in Rocky UI
2. App build in Rocky UI
3. `macos/version.json`
4. GitHub release asset filename

They must all match exactly.

Example of a mismatch that causes redownloads:

- App: `1.1 (1)`
- Manifest: `1.1 (2)`

That always looks like a newer update.

## 8. If macOS Blocks The App On First Launch

This is expected until notarization is added.

Tell users:

1. Move Rocky into `Applications`
2. Right-click `Rocky`
3. Click `Open`

If needed:

1. Open `System Settings`
2. Go to `Privacy & Security`
3. Click `Open Anyway`

## 9. Current Updater Behavior

Rocky currently:

- checks `macos/version.json` from GitHub
- cache-busts the request on each manual update check
- downloads the DMG from GitHub Releases
- installs over the existing app in `Applications`
- relaunches itself

## Quick Checklist

```text
1. Bump app version/build
2. Build Release app
3. Create and test DMG
4. Create GitHub release and upload DMG
5. Update macos/version.json
6. Push version.json
7. Test updater from older installed app
8. Test updater again to confirm "already on latest version"
```
