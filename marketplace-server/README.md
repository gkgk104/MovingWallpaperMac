# MotionDock Marketplace Server

Small self-hosted marketplace server for MotionDock. It uses only Node.js built-in modules.

## Run

From the project root:

```bash
cd /Users/leehyunbin/codes/MotionDock
./scripts/start-marketplace-server.sh
```

Stop with `Control-C`, or run:

```bash
./scripts/stop-marketplace-server.sh
```

Direct run:

```bash
cd /Users/leehyunbin/codes/MotionDock/marketplace-server
node server.js
```

Default URL:

```text
http://127.0.0.1:8787
```

To expose it to devices on the same network:

```bash
HOST=0.0.0.0 PORT=8787 node server.js
```

## Use from MotionDock

1. Start the server.
2. Open MotionDock -> Profiles and sign in.
3. Open MotionDock -> Settings -> Marketplace.
4. Enter `http://127.0.0.1:8787`.
5. Use `Refresh`, `Upload Selected`, `Download`, or `Apply`.

Uploads include the signed-in profile display name and Supabase `uploader_id`.

Uploads are limited to MP4, MOV, M4V, and GIF files. The default maximum upload size is 250 MB. Override it for local testing with:

```bash
MAX_UPLOAD_MB=100 node server.js
```

Each uploader is limited to 1 GB of stored marketplace files by default. Override it for local testing with:

```bash
MAX_USER_STORAGE_MB=2048 node server.js
```

## Moderation

The local server defaults to automatic approval so uploads remain visible during development.

To test manual moderation:

```bash
MODERATION_MODE=manual MODERATION_ADMIN_TOKEN=dev-token node server.js
```

When manual mode is enabled, uploads start as `pending`. Public lists only return `approved` items. Admin review can use:

```bash
curl -X PATCH "http://127.0.0.1:8787/api/wallpapers/WALLPAPER_ID/moderation" \
  -H "Authorization: Bearer dev-token" \
  -H "Content-Type: application/json" \
  -d '{"moderationStatus":"approved"}'
```

See `../docs/marketplace-moderation-workflow.md` for the full workflow.

## Storage

- Metadata: `data/wallpapers.json`
- Uploaded files: `data/files/`

## API

- `GET /api/wallpapers`: list uploaded wallpapers
- `POST /api/wallpapers`: multipart upload
  - `title`: title
  - `kind`: `video` or `gif`
  - `uploaderName`: uploader display name
  - `uploader_id`: Supabase user ID
  - `file`: `.mp4`, `.mov`, `.m4v`, `.gif`
- `PATCH /api/wallpapers/:id/moderation`: update moderation status with `MODERATION_ADMIN_TOKEN`
- `GET /files/:storedName`: download file

## Warning

This is a development/local-network sample. It does not include production authentication, authorization, malware scanning, HTTPS, or backups.
