# MotionDock User Guide

## Overview

MotionDock is a native macOS live wallpaper manager.

Tagline:

```text
Live wallpapers, made native for macOS.
```

It supports built-in motion wallpapers, local MP4/MOV/GIF files, web URL wallpapers, favorites, Supabase-backed profiles, multi-display playback, performance policies, and a marketplace.

## Launch

1. Open `dist/MotionDock.app`.
2. If macOS blocks the local build, open it from Finder with Right Click -> Open.
3. Select a wallpaper from Library.
4. Press `Start Wallpaper` in the inspector.
5. Press `Stop` to stop the live wallpaper.

MotionDock is a menu bar app. It stays out of the Dock and Cmd+Tab. Use the menu bar icon to open the main window, restore the last wallpaper, open Settings, or choose `Quit MotionDock`.

## Main Layout

MotionDock uses a three-column layout.

### Sidebar

- `Library`: all available wallpapers.
- `Favorites`: wallpapers marked as favorites.
- `Recently Added`: imported wallpapers.
- `Discover`: placeholder for curated wallpapers.
- `Profiles`: Supabase account used for upload attribution.
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

Profiles are backed by Supabase Auth.

1. Open `Profiles` or `Settings`.
2. If MotionDock says Supabase is not configured, enter your Supabase project URL and anon key.
3. Press `Save Supabase Settings`.
4. Press `Sign in with Google`.
5. After sign-in, MotionDock syncs your user id, display name, email, and avatar URL to the Supabase `profiles` table.

For Google login, configure Supabase Auth with:

- Provider: Google
- Supabase redirect URL allow list: `motiondock://auth-callback`
- Google Cloud OAuth authorized redirect URI: `https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback`

Marketplace uploads include your Supabase `uploader_id` so uploaded wallpapers can be attributed to the right account.

Marketplace uploads support MP4, MOV, M4V, and GIF files up to 250 MB.
Each signed-in uploader can publish up to 1 GB of marketplace files.
Marketplace uploads may require moderator approval before they become downloadable.

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

### System

- `Start MotionDock when I log in`: registers MotionDock as a macOS Login Item.
- When MotionDock starts from login, it stays hidden in the menu bar and restores the last wallpaper automatically if one was saved.

### Marketplace

When Supabase is configured, MotionDock uses the Supabase `wallpapers` table and `wallpapers` Storage bucket.

Configure Supabase from Settings -> MotionDock 계정, or from Profiles when MotionDock shows the configuration prompt. MotionDock saves the configuration to:

```text
~/Library/Application Support/MotionDock/Supabase.plist
```

You can also configure Supabase with environment variables:

```bash
export MOTIONDOCK_SUPABASE_URL="https://YOUR_PROJECT_REF.supabase.co"
export MOTIONDOCK_SUPABASE_ANON_KEY="YOUR_SUPABASE_ANON_KEY"
```

or create the plist manually:

```text
~/Library/Application Support/MotionDock/Supabase.plist
```

The plist format is shown in:

```text
Sources/MovingWallpaperMac/Resources/Supabase.example.plist
```

Create the required Supabase tables and Storage policies with:

```text
docs/supabase-schema.sql
```

If Supabase is not configured, MotionDock can still use the advanced local self-hosted marketplace server.

Start it:

```bash
cd /Users/leehyunbin/codes/MotionDock
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

Downloaded marketplace files are stored at:

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

### Main Window Does Not Reopen

MotionDock is hidden from the Dock by design. Use the menu bar icon and choose `Open MotionDock`. If reopen ever fails after a rebuild, choose `Quit MotionDock` from the menu bar and open `dist/MotionDock.app` again.

### Battery Use Is High

- Use `Low Power`.
- Use `Pause When Covered`.
- Prefer 1080p video over 4K or 60fps video.
- Use Main Display instead of All Displays on battery.

## Limits

- MotionDock renders live wallpaper windows; it does not permanently replace the macOS system wallpaper file.
- Full-screen Spaces and Mission Control can change how desktop-level windows are presented.
- The local marketplace server is a fallback development tool, not production authentication infrastructure.
- Marketplace publishing is experimental for beta builds until the production Supabase project and upload/download QA are complete.

Before sharing a beta build, use `docs/beta-qa-checklist.md` and update `docs/beta-known-issues.md`.
