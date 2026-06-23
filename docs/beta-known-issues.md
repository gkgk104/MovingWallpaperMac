# MotionDock Beta Known Issues

This list should be shared with beta testers and updated after every QA pass.

## Distribution

- Developer ID signing and notarization require Apple Developer credentials on the release machine. Local builds may still use ad-hoc signing.
- Gatekeeper acceptance cannot be considered complete until a Developer ID signed and notarized build passes `spctl`.
- The current build output is a ZIP package. DMG packaging is not implemented yet.

## App Behavior

- MotionDock must keep running for live wallpapers to stay active. macOS does not provide a public API for an app to quit while preserving animated wallpapers.
- Full-screen Spaces, Mission Control, Stage Manager, and desktop-management utilities can change how desktop-level wallpaper windows appear.
- Some login-item and Dock visibility behavior may require a real packaged app run, not only a SwiftPM debug launch.

## Media Playback

- Video playback depends on AVFoundation codecs available on the user's Mac.
- Very large 4K or high-frame-rate videos can increase CPU, GPU, memory, and battery use.
- Web URL wallpapers depend on network availability and the behavior of the loaded web page.
- Imported files moved or deleted outside MotionDock may fail until removed and re-imported.

## Authentication

- Public beta uses Google login. Apple Sign-In is deferred until Apple Developer Program enrollment.
- Google login requires a configured Supabase project, Google Auth provider, and `motiondock://auth-callback` in the Supabase redirect URL allow list.

## Marketplace

- Marketplace publishing is experimental until production Supabase Auth, Storage, RLS policies, moderation, and quota behavior are verified.
- Upload file type, file size, and per-user storage quota validation exist in MotionDock and the local marketplace server, but production Supabase storage policy hardening still needs verification.
- Moderation workflow exists, but reviewer access, operational policy, and production scanning are not fully hardened yet.
- Unsafe-content scanning and malware scanning are not implemented.
- Author detail pages and item detail pages are not complete.
- The local marketplace server is a development fallback and should not be treated as production infrastructure.

## Branding And Assets

- Final app icon, logo mark, wordmark, and menu bar icon assets are installed, but final visual review is still required before public beta.
- Some visual polish tasks remain for wave/reflection accents and animations.
