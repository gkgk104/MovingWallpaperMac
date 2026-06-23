# MotionDock Beta QA Checklist

Use this checklist before sharing an external beta build.

## Test Environment

- macOS version:
- Mac model and chip:
- Display setup:
- MotionDock version:
- Build path:
- Tester:
- Date:

## Install And Launch

- [ ] `dist/MotionDock.app` opens without an immediate crash.
- [ ] `dist/MotionDock.zip` extracts into a working app bundle.
- [ ] The menu bar icon appears after launch.
- [ ] The main window opens from `Open MotionDock` in the menu bar.
- [ ] Only one MotionDock instance stays active after launching the app twice.
- [ ] Closing the main window hides controls without quitting the app.
- [ ] `Quit MotionDock` from the menu bar fully stops the app.

## Library Import And Playback

- [ ] Built-in motion wallpaper starts.
- [ ] Built-in motion wallpaper stops.
- [ ] MP4 import appears in Library with a thumbnail.
- [ ] MP4 playback starts and stops.
- [ ] MOV import appears in Library with a thumbnail.
- [ ] MOV playback starts and stops.
- [ ] GIF import appears in Library with a thumbnail.
- [ ] GIF playback starts and stops.
- [ ] Web URL wallpaper can be added.
- [ ] Web URL wallpaper starts and stops.
- [ ] Invalid or missing files show a visible error instead of crashing.

## Wallpaper Controls

- [ ] `Start Wallpaper` starts the selected wallpaper.
- [ ] `Stop` stops the active wallpaper.
- [ ] `Restore Last Wallpaper` restores the last valid wallpaper from the menu bar.
- [ ] `Reveal in Finder` opens imported local files.
- [ ] `Add to Favorites` and Favorites filtering work.
- [ ] Recently Added shows imported wallpapers.
- [ ] Remove from Library only appears for user-imported wallpapers.

## Layout And UI

- [ ] Sidebar rows are clickable across the full row width.
- [ ] Library cards keep consistent thumbnail ratios for built-in and imported wallpapers.
- [ ] Right detail panel content stays inside the panel.
- [ ] Long titles and filenames truncate instead of pushing layout.
- [ ] Settings does not overlap with the detail panel.
- [ ] Window resize keeps the main content usable.
- [ ] Empty states render correctly in Library, Discover, Profiles, and search results.

## Settings

- [ ] Display setting switches between All Displays and Main Display.
- [ ] Mute setting updates video and web wallpaper audio behavior.
- [ ] Scale setting switches between Fill and Fit.
- [ ] Performance profile changes do not crash playback.
- [ ] Performance policy can pause or stop wallpaper when covered.
- [ ] Start at login toggle persists after app restart.
- [ ] Show in Dock toggle immediately shows or hides Dock/Cmd+Tab presence.

## Menu Bar Behavior

- [ ] Open MotionDock shows and focuses the main window.
- [ ] Start Wallpaper works from the menu bar.
- [ ] Stop Wallpaper works from the menu bar.
- [ ] Restore Last Wallpaper works from the menu bar.
- [ ] Settings opens the Settings screen.
- [ ] Quit MotionDock fully terminates wallpaper windows and app process.

## Authentication And Marketplace

- [ ] Supabase URL and anon key can be saved from Profiles.
- [ ] Supabase URL and anon key can be saved from Settings.
- [ ] Sign in with Google starts the Supabase Google OAuth flow when Supabase is configured.
- [ ] Signed-in account information appears in Profiles and Settings.
- [ ] Logout clears the visible account state.
- [ ] Upload is blocked while signed out.
- [ ] Upload includes the signed-in uploader id when signed in.
- [ ] Unsupported upload extensions are rejected before upload.
- [ ] Uploads larger than 250 MB are rejected before upload.
- [ ] Uploads that exceed the 1 GB per-user marketplace storage quota are rejected.
- [ ] Pending or rejected marketplace items show moderation status and cannot be downloaded or applied.
- [ ] Marketplace list loads from Supabase when configured.
- [ ] Marketplace download adds the wallpaper to Library.
- [ ] Marketplace apply downloads and starts the wallpaper.

## Distribution Checks

- [ ] `./scripts/build-app.sh` completes successfully.
- [ ] `dist/MotionDock.app` exists.
- [ ] `dist/MotionDock.zip` exists.
- [ ] App bundle identifier is `com.motiondock.app` or the expected release identifier.
- [ ] Developer ID signing is present for external release builds.
- [ ] Hardened runtime is enabled for external release builds.
- [ ] Notarization succeeds for external release builds.
- [ ] `spctl -a -vv --type execute dist/MotionDock.app` accepts the packaged app.

## Failure Log

Record every failed item with:

- Checklist item:
- Reproduction steps:
- Expected result:
- Actual result:
- Screenshot or log path:
- Severity:
- Owner:
