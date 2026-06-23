# MotionDock Marketplace Moderation Workflow

MotionDock marketplace publishing uses a simple review state machine:

```text
pending -> approved
pending -> rejected
rejected -> pending
```

## Production Supabase Flow

1. A signed-in user uploads an MP4, MOV, M4V, or GIF wallpaper.
2. MotionDock stores the file in Supabase Storage and inserts a `wallpapers` row with `moderation_status = 'pending'`.
3. Public marketplace lists only show `approved` wallpapers.
4. The uploader can still see their own pending row.
5. A moderator account listed in `public.marketplace_moderators` reviews the upload.
6. The moderator updates:
   - `moderation_status` to `approved` or `rejected`
   - `reviewed_by` to the moderator user id
   - `reviewed_at` to the review time
   - `rejection_reason` when rejected
7. Approved wallpapers become publicly readable and downloadable.

Run `docs/supabase-schema.sql` in Supabase to create the moderator table, moderation columns, RLS policies, and Storage read policy.

## Local Server Flow

The local marketplace server defaults to automatic approval so existing local testing stays fast:

```bash
node marketplace-server/server.js
```

To test manual moderation:

```bash
MODERATION_MODE=manual MODERATION_ADMIN_TOKEN=dev-token node marketplace-server/server.js
```

List every item, including pending and rejected:

```bash
curl "http://127.0.0.1:8787/api/wallpapers?include=all&adminToken=dev-token"
```

Approve an item:

```bash
curl -X PATCH "http://127.0.0.1:8787/api/wallpapers/WALLPAPER_ID/moderation" \
  -H "Authorization: Bearer dev-token" \
  -H "Content-Type: application/json" \
  -d '{"moderationStatus":"approved"}'
```

Reject an item:

```bash
curl -X PATCH "http://127.0.0.1:8787/api/wallpapers/WALLPAPER_ID/moderation" \
  -H "Authorization: Bearer dev-token" \
  -H "Content-Type: application/json" \
  -d '{"moderationStatus":"rejected","rejectionReason":"Unsafe or low-quality upload"}'
```

## App Behavior

- Approved items can be downloaded or applied.
- Pending and rejected items show their moderation status.
- Pending and rejected items cannot be downloaded or applied from the public marketplace row.
- Uploads can return `Upload submitted for review.` when the backend is configured for manual review.

## Still Needed Before Production

- Decide who owns moderator access.
- Add operational review guidelines.
- Add unsafe-content and malware scanning before or during moderation.
- Add audit logging if required for production operations.
