# MotionDock User Guide

## Overview

MotionDock is a native macOS live wallpaper manager.

Tagline:

```text
Live wallpapers, made native for macOS.
```

It supports built-in motion wallpapers, local MP4/MOV/GIF files, web URL wallpapers, favorites, profiles, multi-display playback, performance policies, and a local self-hosted marketplace server.

## Launch

1. Open `dist/MotionDock.app`.
2. If macOS blocks the local build, open it from Finder with Right Click -> Open.
3. Select a wallpaper from Library.
4. Press `Start Wallpaper` in the inspector.
5. Press `Stop` to stop the live wallpaper.

## Main Layout

MotionDock uses a three-column layout.

### Sidebar

- `Library`: all available wallpapers.
- `Collections`: built-in motion collections.
- `Favorites`: wallpapers marked as favorites.
- `Recently Added`: imported wallpapers.
- `Discover`: placeholder for curated wallpapers.
- `Profiles`: local profile used for upload attribution.
- `Settings`: playback, performance, and marketplace settings.

### Center Grid

The center area shows large wallpaper cards with:

- Thumbnail
- Title
- File type badge
- Resolution badge
- Running indicator
- Hover animation
- Selected state

Use the search field to filter visible wallpapers.

### Inspector

The right inspector shows:

- Large preview image
- Title
- Status
- Resolution
- Duration
- File type
- File name

Actions:

- `Start Wallpaper`
- `Stop`
- `Reveal in Finder`
- `Add to Favorites`
- `Remove from Library` for user-imported items

## Import Wallpaper

Use `Import Wallpaper` in the Library header.

Supported local formats:

- MP4
- MOV
- GIF

The `URL` button next to `Import Wallpaper` opens URL import for web wallpapers. The URL field is only shown when URL import is selected.

## Discover

The Discover page currently shows:

```text
Discover curated motion wallpapers soon.
```

## Profiles

Profiles are local to this Mac for now.

1. Open `Profiles`.
2. Enter a display name.
3. Optionally enter a handle.
4. Press `Create Profile`.

Marketplace uploads include the profile display name and profile ID.

## Settings

### Playback

- `Display`: all displays or main display.
- `Audio`: mute video and web wallpapers.
- `Scale`: fill or fit.
- `Playlist`: cycle through wallpapers automatically.

### Performance

- `Quality`: smoother rendering.
- `Balanced`: default.
- `Low Power`: lower animation cost.
- `Always Play`: keep running under other windows.
- `Pause When Covered`: pause when a large foreground window covers the display.
- `Stop When Covered`: release wallpaper windows when covered.

### Self-hosted Marketplace

The marketplace server is an advanced local feature.

Start it:

```bash
cd /Users/leehyunbin/codes/MovingWallpaperMac
./scripts/start-marketplace-server.sh
```

Stop it:

```bash
./scripts/stop-marketplace-server.sh
```

Default URL:

```text
http://127.0.0.1:8787
```

Downloaded files are stored at:

```text
~/Library/Application Support/MotionDock/Marketplace Downloads/
```

## Troubleshooting

### Wallpaper Does Not Start

- Make sure a wallpaper is selected.
- Check that local files still exist.
- Try another MP4, MOV, or GIF.
- Change Settings -> Performance -> Policy to `Always Play` for testing.

### Video Does Not Play

- Confirm the file opens in QuickTime Player.
- Use MP4 or MOV with a codec supported by macOS AVFoundation.

### GIF Does Not Appear

- Confirm the file extension is `.gif`.
- Check that Finder Preview or Safari can open the GIF.

### Dock Click Does Not Restore the Window

MotionDock tracks its main control window separately from wallpaper render windows. If Dock restore ever fails after a rebuild, quit MotionDock and open `dist/MotionDock.app` again.

### Battery Use Is High

- Use `Low Power`.
- Use `Pause When Covered`.
- Prefer 1080p video over 4K or 60fps video.
- Use Main Display instead of All Displays on battery.

## Limits

- MotionDock renders live wallpaper windows; it does not permanently replace the macOS system wallpaper file.
- Full-screen Spaces and Mission Control can change how desktop-level windows are presented.
- The marketplace server is not production-ready authentication infrastructure.
