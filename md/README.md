# MotionDock

Live wallpapers, made native for macOS.

MotionDock is a native macOS live wallpaper manager with a local library, MP4/MOV/GIF import, web wallpapers, display controls, performance policies, Supabase-backed profiles, favorites, and a marketplace.

macOS does not expose a public API for setting animated system wallpapers directly. MotionDock renders behind desktop icons with desktop-level windows, so live wallpapers stay active while the app is running.

## Build

```bash
cd /Users/leehyunbin/codes/MotionDock
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

The app bundle and ZIP package are created at:

```text
dist/MotionDock.app
dist/MotionDock.zip
```

For a Developer ID distribution build, provide signing and notarization settings:

```bash
MOTIONDOCK_BUNDLE_IDENTIFIER="com.motiondock.app" \
MOTIONDOCK_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
MOTIONDOCK_NOTARIZE=1 \
MOTIONDOCK_NOTARY_PROFILE="motiondock-notary" \
./scripts/build-app.sh
```

Without `MOTIONDOCK_SIGN_IDENTITY`, the script uses ad-hoc signing for local testing. Set `MOTIONDOCK_VERIFY_SPCTL=1` to run Gatekeeper verification after packaging.

## Run

Open the app bundle:

```bash
open "/Users/leehyunbin/codes/MotionDock/dist/MotionDock.app"
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

## Marketplace

When Supabase is configured, MotionDock uses Supabase Auth, a `profiles` table, a `wallpapers` table, and a `wallpapers` Storage bucket. The required SQL is in:

```text
docs/supabase-schema.sql
```

Set credentials in MotionDock from Settings -> MotionDock 계정, or from Profiles when the app shows the Supabase configuration prompt. MotionDock saves them to:

```text
~/Library/Application Support/MotionDock/Supabase.plist
```

You can also set credentials with environment variables or create the plist manually. See:

```text
Sources/MovingWallpaperMac/Resources/Supabase.example.plist
```

Google login uses Supabase OAuth with this app redirect URL:

```text
motiondock://auth-callback
```

Add that URL to the Supabase Auth redirect URL allow list. In Google Cloud Console, the OAuth authorized redirect URI should point to Supabase:

```text
https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback
```

Marketplace uploads are limited to MP4, MOV, M4V, and GIF files up to 250 MB.
Each signed-in uploader is limited to 1 GB of marketplace storage.
Production marketplace uploads can use the moderation workflow in `docs/marketplace-moderation-workflow.md`.

## Local Marketplace Server

If Supabase is not configured, MotionDock can fall back to the local marketplace server:

```bash
cd /Users/leehyunbin/codes/MotionDock
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
- Supabase marketplace policies in `docs/supabase-schema.sql` are a starting point; production scanning still needs backend work.
- The local marketplace server is a development fallback. It does not include production account auth, moderation, payment, malware scanning, HTTPS, or backups.
- Public beta builds should treat the marketplace as experimental until Supabase Auth, upload, download, moderation, and quota behavior are verified against the production project.

## Beta QA

- Manual beta QA checklist: `docs/beta-qa-checklist.md`
- Beta known issues: `docs/beta-known-issues.md`

See `USER_GUIDE.md` for detailed usage.
