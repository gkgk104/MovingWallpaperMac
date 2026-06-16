# MotionDock Marketplace Server

Small self-hosted marketplace server for MotionDock. It uses only Node.js built-in modules.

## Run

From the project root:

```bash
cd /Users/leehyunbin/codes/MovingWallpaperMac
./scripts/start-marketplace-server.sh
```

Stop with `Control-C`, or run:

```bash
./scripts/stop-marketplace-server.sh
```

Direct run:

```bash
cd /Users/leehyunbin/codes/MovingWallpaperMac/marketplace-server
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
2. Open MotionDock -> Profiles and create a local profile.
3. Open MotionDock -> Settings -> Self-hosted Marketplace.
4. Enter `http://127.0.0.1:8787`.
5. Use `Refresh`, `Upload Selected`, `Download`, or `Apply`.

Uploads include the local profile display name and profile ID.

## Storage

- Metadata: `data/wallpapers.json`
- Uploaded files: `data/files/`

## API

- `GET /api/wallpapers`: list uploaded wallpapers
- `POST /api/wallpapers`: multipart upload
  - `title`: title
  - `kind`: `video` or `gif`
  - `uploaderName`: uploader display name
  - `uploaderID`: uploader ID
  - `file`: `.mp4`, `.mov`, `.m4v`, `.webm`, `.avi`, `.gif`
- `GET /files/:storedName`: download file

## Warning

This is a development/local-network sample. It does not include production authentication, authorization, moderation, malware scanning, HTTPS, storage quotas, or backups.
