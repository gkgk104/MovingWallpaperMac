# MotionDock Progress

Last updated: 2026-06-23

## Release Outlook

- Internal test build: ready now. `swift build -c release` and `./scripts/build-app.sh` both pass, and `dist/MotionDock.app` launches without an immediate startup crash.
- External test build target: 2026-06-20 to 2026-06-21, if Apple Developer signing assets are available.
- Public beta target: 2026-06-26 to 2026-07-03, if marketplace is kept as beta or experimental.
- Full marketplace release target: 2026-07-10 to 2026-07-24, after production backend, moderation, quota, and QA work.

## Current Release Decision

Ship the first public beta with the local wallpaper manager as the primary product surface:

- Library import for MP4, MOV, GIF, and web URL wallpapers.
- Start, stop, restore, favorites, display controls, and performance policy settings.
- Menu bar app behavior.
- Supabase profile sign-in only after real project verification.
- Marketplace marked as beta or hidden unless production backend readiness is complete.

## Completed

- Basic app structure
- Sidebar implementation
- Sidebar click target area expanded
- Collections sidebar entry is hidden for beta while the underlying Collections data and routing code remain preserved for a post-launch revisit
- Detail Panel layout improvements
- Library cards now act as the preset selector for built-in MotionDock wallpapers; Scene/Palette controls, file type badges, and internal File Type/Path detail rows were removed from the Library inspector
- Dock icon behavior investigation
- Logo concept finalized
- Wave and reflection design direction established
- Settings Account section with Google sign-in and logout
- In-app Supabase configuration for Google sign-in
- Release build verification
- Local app bundle generation at `dist/MotionDock.app`
- Local ZIP package generation at `dist/MotionDock.zip`
- Basic launch smoke check
- Production bundle identifier default set to `com.motiondock.app`
- Build script supports Developer ID signing, hardened runtime, notarization, stapling, ZIP packaging, and optional `spctl` verification
- Manual beta QA checklist added at `docs/beta-qa-checklist.md`
- Beta known issues list added at `docs/beta-known-issues.md`
- Google Sign-In enabled for beta; Apple Sign-In is deferred until Apple Developer Program enrollment
- Brand asset catalog consolidated under `Sources/MovingWallpaperMac/Resources/Assets.xcassets`
- Placeholder logo assets removed; final logo, wordmark, menu bar icon, and AppIcon variants are in use
- Menu bar `Quit MotionDock`, Dock `Quit`, and `Cmd+Q` now perform a full app shutdown while the window close button still only hides the control window
- Main window close now follows a macOS-style policy: normal windows hide on red close, while fullscreen windows only exit fullscreen and remain visible without alpha/content hiding workarounds
- First launch now shows the main window by default; hidden startup only applies to explicit background/login launch markers and launch/show/hide/reopen decisions are logged
- Main content now defaults to Library on first launch/relaunch, ignores the initial Settings request publisher value, and falls back to Library for hidden beta sections like Collections
- Wallpaper windows now reapply desktop-level placement and recover playback after Space changes, fullscreen app transitions, display changes, and wake/session resume events
- Marketplace settings now show explicit loading, empty, and error states
- Marketplace upload validation now limits uploads to MP4, MOV, M4V, and GIF files up to 250 MB in the app and local server
- Marketplace uploads now enforce a 1 GB per-user storage quota in Supabase upload flow, local server upload flow, and the Supabase schema reference
- Legacy marketplace moderation workflow was documented; Discover production flow now favors uploader responsibility consent plus report-based hiding instead of pre-screening
- Build script supports ad-hoc local signing without restricted auth entitlements
- Google login now uses Supabase OAuth with the `motiondock://auth-callback` URL scheme and keeps profile upsert plus uploader attribution intact
- Google OAuth now opens the provider flow with `motiondock://auth-callback` and completes the PKCE callback through the macOS URL open handler instead of falling back to localhost
- Google OAuth callback handling now ignores non-OAuth test callbacks without a `code` parameter and reports callback/session exchange errors in-app instead of terminating
- OAuth URL handling now separates duplicate-instance termination from real app quit and logs callback URL, query items, code extraction, and session exchange success/failure
- Google OAuth now requests the Google account chooser through Supabase authorize query params with `prompt=select_account`, avoids the problematic `access_type=offline` option, and Profiles includes a "Use another Google account" action that signs out before reopening OAuth
- Discover now reads public marketplace wallpapers from Supabase `public.wallpapers`, shows loading/empty/error states, renders title/category/likes/downloads cards, and displays selected marketplace details in the right panel without requiring login
- Discover Download/Add to Library now downloads from `video_url`, saves into MotionDock marketplace downloads storage, adds or updates the Library item, shows loading/error state, and increments the Supabase `downloads` counter
- Marketplace upload now uses Cloudflare R2 for file storage via `CloudflareR2StorageService`, inserts uploaded metadata into Supabase `public.wallpapers`, and refreshes Discover after successful upload
- Discover now shows a fixed top-level Upload button next to Refresh so marketplace uploads are reachable even when the marketplace is empty
- Discover marketplace uploads now generate a video thumbnail, upload it to Cloudflare R2 under `thumbnails/<uuid>.jpg`, save `thumbnail_url` in Supabase, and keep a single Add to Library action with duplicate-download protection
- Discover marketplace now joins uploader profiles and shows display name, handle, or email instead of exposing uploader UUIDs in cards and detail views
- Discover marketplace now supports signed-in user likes through Supabase `toggle_wallpaper_like`, optimistic heart toggles, atomic `wallpaper_likes` and `likes_count` updates, and persisted liked state on refresh/relaunch
- Discover marketplace uploads now open a metadata form before file selection and capture title, category, description, and required upload terms consent while uploader naming comes from the signed-in profile
- Profiles now lets signed-in users edit `profiles.display_name`; Discover and My Uploads refresh after saving so uploader attribution updates without exposing uploader UUIDs
- Discover marketplace cards now remove redundant motion/video badges, keep category labels, and show readable relative upload times shared with the detail panel
- Discover detail panels now hide internal report counts, storage URLs, thumbnails URLs, and uploader IDs while keeping title, category, likes, downloads, uploader, upload time, description, Like, Add to Library, and Report actions
- Discover marketplace now supports All/Latest/Most Downloaded/Liked sorting, category filtering, and atomic `downloads` increments through Supabase `increment_wallpaper_downloads`
- Profiles now includes My Uploads management with owner-scoped upload listing, metadata edit, confirmed delete, R2 asset deletion, `wallpaper_likes` cleanup, and Discover refresh after changes
- Discover marketplace now has local search across title, description, category, and uploader display name, with clear action and selection reset when the selected card leaves the visible result set
- Marketplace uploads now require explicit uploader responsibility consent through centralized Upload Terms copy before R2/Supabase insertion
- Discover marketplace now supports signed-in wallpaper reports with reason/details capture, duplicate-report prevention, `report_count` updates, and automatic hiding after 3 reports
- Discover report RPC calls now always send `p_wallpaper_id`, `p_reason`, and `p_details`, and log the RPC name plus parameter keys on failures

## In Progress

- UI polishing
- Application behavior improvements
- Supabase Google Auth verification with real project credentials
- Cloudflare R2 production credential verification
- Release signing and notarization credential setup

## Release Blockers

- Provide Developer ID Application certificate and notarization credentials on the release machine.
- Verify Gatekeeper acceptance after packaging.
- Verify Supabase Google Auth, profiles, wallpaper upload, wallpaper download, report-based hiding, and quota behavior against the real production project.
- Decide production marketplace scope: beta/hidden for June beta, or hardened backend for July release.

## Target Checklist

### Before External Test Build

- [x] Confirm release build compiles.
- [x] Confirm `dist/MotionDock.app` is generated.
- [x] Confirm basic launch does not crash immediately.
- [x] Set production bundle identifier default.
- [x] Add Developer ID signing path to the build script.
- [x] Add notarization and stapling commands.
- [x] Package the app as ZIP.
- [ ] Provide Developer ID certificate and notarization credentials.
- [ ] Confirm `spctl` accepts the packaged app.

### Before Public Beta

- [ ] Verify import and playback for MP4, MOV, GIF, and web URL wallpapers.
- [ ] Verify start, stop, restore last wallpaper, and quit behavior.
- [ ] Verify multi-display behavior.
- [ ] Verify start-at-login and Dock visibility settings.
- [ ] Verify menu bar controls.
- [ ] Verify app behavior across close, reopen, duplicate launch, and restart.
- [x] Make fullscreen main-window close exit fullscreen only, then require a second close to hide the normal window.
- [x] Add automatic wallpaper window recovery for Space/fullscreen/display/wake transitions.
- [ ] Verify Supabase Google sign-in with real project credentials.
- [x] Add Google account chooser flow for account switching after logout.
- [ ] Configure Supabase Google provider and Google Cloud OAuth redirect values.
- [ ] Configure Cloudflare R2 upload environment variables on the release machine.
- [ ] Verify marketplace 1 GB per-user quota with production Supabase credentials.
- [ ] Verify marketplace report-based hiding workflow with production Supabase credentials.
- [ ] Verify Discover marketplace listing against production Supabase credentials.
- [x] Enable Google Sign-In and defer Apple Sign-In.
- [x] Replace temporary brand assets.
- [x] Update README and user guide with beta limitations.
- [x] Record known issues for beta testers.

### Before Full Marketplace Release

- [ ] Finalize production Supabase schema and policies.
- [x] Add Cloudflare R2 storage provider abstraction for marketplace uploads.
- [x] Add production moderation workflow.
- [x] Add upload file type and file size enforcement.
- [x] Add per-user storage quota enforcement.
- [ ] Add malware or unsafe-content scanning plan.
- [ ] Add backup and recovery plan for marketplace storage.
- [x] Add Cloudflare R2-backed marketplace upload path.
- [ ] Verify Cloudflare R2 public `video_url` access through production domain.
- [ ] Verify upload, list, download, and apply flows end to end.
- [x] Wire Discover Download/Add to Library actions to the real `video_url` download/apply flow.
- [x] Add Discover upload metadata form with title, category, description, and profile-managed uploader display name.
- [x] Add Discover category filters and All/Latest/Most Downloaded/Liked sorting.
- [x] Add Discover local search across title, description, category, and uploader.
- [x] Replace client-side `downloads` updates with an atomic Supabase RPC.
- [x] Add required uploader responsibility consent before Discover uploads.
- [x] Add report-based post-publication hiding with Supabase `report_wallpaper`.
- [ ] Verify duplicate report prevention and 3-report auto-hide against production Supabase credentials.
- [x] Add Profiles My Uploads management for edit/delete of uploaded wallpapers.
- [x] Improve marketplace empty, loading, and error states.
- [ ] Add analytics or minimal release telemetry if required.
- [ ] Add update distribution strategy.

## Notes

Follow AGENTS.md rules for every task.
Build only after all edits are complete.
Keep changes small and isolated.
