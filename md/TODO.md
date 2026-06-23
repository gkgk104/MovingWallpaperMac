# MotionDock TODO

Last updated: 2026-06-23

## P0 - External Test Build

Target: 2026-06-20 to 2026-06-21

- [x] Confirm release build passes.
- [x] Confirm app bundle generation.
- [x] Confirm basic app launch smoke check.
- [x] Replace `local.codex.motiondock` with production bundle identifier default.
- [x] Add Developer ID Application signing support to build script.
- [x] Enable hardened runtime for distribution build.
- [x] Add notarization and stapling step.
- [x] Package app as ZIP.
- [ ] Provide Developer ID certificate and notarization credentials on release machine.
- [ ] Confirm Gatekeeper acceptance with `spctl`.
- [ ] Commit or intentionally stage current release-related changes.

## P0 - Public Beta

Target: 2026-06-26 to 2026-07-03

- [ ] Run manual QA for MP4 import and playback.
- [ ] Run manual QA for MOV import and playback.
- [ ] Run manual QA for GIF import and playback.
- [ ] Run manual QA for web URL wallpapers.
- [ ] Run manual QA for start, stop, restore, and quit.
- [ ] Run manual QA for multi-display behavior.
- [ ] Run manual QA for close, reopen, duplicate launch, and app restart.
- [ ] Verify start-at-login behavior.
- [ ] Verify Dock visibility setting.
- [ ] Verify menu bar controls.
- [x] Make fullscreen main-window close exit fullscreen only, then hide only after a second close in normal window mode.
- [x] Separate first launch from user-hidden window state so normal launches show the main window.
- [x] Default first launch/relaunch navigation to Library instead of Settings.
- [x] Add automatic wallpaper recovery for Space/fullscreen/display/wake transitions.
- [ ] Verify Supabase Google sign-in with real credentials.
- [x] Add Google account chooser flow for Google account switching.
- [ ] Configure Supabase Google provider and Google Cloud OAuth redirect values.
- [ ] Configure Cloudflare R2 upload environment variables on release machine.
- [ ] Verify Discover marketplace listing with production Supabase credentials.
- [ ] Verify marketplace report-based auto-hide with production Supabase credentials.
- [x] Enable Google Sign-In for beta.
- [x] Defer Apple Sign-In until Apple Developer Program enrollment.
- [x] Replace temporary brand assets with final app icon, logo mark, and wordmark.
- [x] Update README and USER_GUIDE with beta limitations.
- [x] Publish a known-issues list for beta testers.

## P1 - Marketplace Release

Target: 2026-07-10 to 2026-07-24

- [ ] Decide whether marketplace ships as beta, hidden, or production-ready.
- [ ] Finalize Supabase production schema and RLS policies.
- [ ] Verify profile creation and update flow.
- [ ] Verify marketplace upload with production Cloudflare R2 storage.
- [ ] Verify marketplace list, download, and apply flows.
- [x] Add Cloudflare R2 storage provider abstraction for marketplace uploads.
- [x] Add always-visible Discover Upload button for MP4/MOV R2 uploads.
- [x] Add Discover upload metadata form for title, category, description, and profile-managed uploader display name.
- [x] Generate and upload Discover thumbnails to Cloudflare R2.
- [x] Add Supabase Discover marketplace card grid.
- [x] Add Discover marketplace item details in the right panel.
- [x] Add Discover category filters and All/Latest/Most Downloaded/Liked sorting.
- [x] Add Discover local search across title, description, category, and uploader.
- [x] Show uploader profile names instead of UUIDs in Discover.
- [x] Add Profiles My Uploads management for owner edit/delete.
- [x] Add Supabase-backed Discover like/unlike system.
- [x] Wire Discover Download/Add to Library actions to real `video_url` download and apply behavior.
- [x] Collapse Discover Download/Add actions into a single Add to Library flow.
- [x] Add upload file type validation.
- [x] Add upload file size limit.
- [x] Add per-user storage quota.
- [x] Add marketplace moderation/reporting workflow.
- [x] Add required uploader responsibility consent before marketplace uploads.
- [x] Add report-based post-publication response and automatic hiding after 3 reports.
- [ ] Add malware or unsafe-content scanning plan.
- [ ] Add storage backup and recovery plan.
- [ ] Add download_events table for weekly/monthly download rankings after beta.
- [x] Replace client-side `likes_count` updates with an atomic Supabase RPC.
- [x] Replace client-side `downloads` updates with an atomic Supabase RPC.
- [ ] Verify duplicate report prevention and hidden-item filtering end to end.
- [ ] Verify Cloudflare R2 public `video_url` access through production domain.
- [ ] Add author detail view.
- [ ] Add item detail page.
- [x] Improve marketplace empty, loading, and error states.

## P2 - Product Polish

- [x] Expand sidebar click target area.
- [x] Add manual QA checklist for beta testing.
- [x] Remove duplicate Library Scene/Palette controls and file type badges.
- [ ] Collections feature hidden for beta; revisit after launch.
- [ ] Improve Detail Panel spacing.
- [ ] Apply wave/reflection design language throughout the app.
- [ ] Improve animations.
- [x] Organize image resources.
- [x] Add icon variants.
- [x] Create dedicated logo asset folder.
- [x] Split logos into separate PNG files.
- [ ] Add update distribution strategy.
- [ ] Add analytics or minimal release telemetry if required.
