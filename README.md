# MotionDock

Live wallpapers, made native for macOS.

MotionDock is a native macOS live wallpaper manager with a local library, MP4/MOV/GIF import, web wallpapers, display controls, performance policies, profiles, favorites, and a lightweight self-hosted marketplace server.

macOS does not expose a public API for setting animated system wallpapers directly. MotionDock renders behind desktop icons with desktop-level windows, so live wallpapers stay active while the app is running.

## Build

```bash
cd /Users/leehyunbin/codes/MovingWallpaperMac
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

The app bundle is created at:

```text
dist/MotionDock.app
```

## Run

Open the app bundle:

```bash
open "/Users/leehyunbin/codes/MovingWallpaperMac/dist/MotionDock.app"
```

If macOS shows a security warning for the locally signed build, open it from Finder with Right Click -> Open.

MotionDock runs as a menu bar app. It does not appear in the Dock or Cmd+Tab. Use the menu bar icon to open the main window, start or stop the wallpaper, restore the last wallpaper, open Settings, or quit MotionDock.

## Product UI

- Three-column native macOS layout
- Sidebar navigation: Library, Favorites, Recently Added, Discover, Profiles, Settings
- Responsive wallpaper card grid
- Right inspector with preview, metadata, status, and actions
- Import Wallpaper flow for local files and URL import
- Discover placeholder: "Discover curated motion wallpapers soon."
- Premium dark color system inspired by modern macOS software

## Supported Formats

- MP4
- MOV
- GIF
- Web URL import with `http://` or `https://`

Video decoding depends on codecs supported by macOS AVFoundation.

## Actions

- Start Wallpaper
- Stop
- Reveal in Finder
- Add to Favorites
- Import Wallpaper

## Marketplace Server

Start the local marketplace server:

```bash
cd /Users/leehyunbin/codes/MovingWallpaperMac
./scripts/start-marketplace-server.sh
```

Stop it with `Control-C`, or run:

```bash
./scripts/stop-marketplace-server.sh
```

The default server URL is:

```text
http://127.0.0.1:8787
```

Marketplace downloads are stored under:

```text
~/Library/Application Support/MotionDock/Marketplace Downloads/
```

## Notes

- MotionDock must remain open for live wallpapers to continue running. Closing the main window only hides the controls; wallpapers keep running until you choose `Quit MotionDock` from the menu bar.
- Full-screen Spaces and some desktop-management tools may affect visibility because of macOS window-level behavior.
- The marketplace server is a local/development sample. It does not include production account auth, moderation, payment, malware scanning, HTTPS, or storage quotas.

See `USER_GUIDE.md` for detailed usage.
