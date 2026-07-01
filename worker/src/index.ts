import { AwsClient } from "aws4fetch";

interface Env {
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  SUPABASE_JWT_SECRET?: string;
  R2_BUCKET: string;
  R2_PUBLIC_BASE_URL: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  R2_ENDPOINT: string;
  R2_REGION?: string;
  SUPABASE_JWKS_TTL_SECONDS?: string;
  UPLOAD_URL_TTL_SECONDS?: string;
  MAX_UPLOAD_BYTES?: string;
  CORS_ORIGIN?: string;
}

interface AuthContext {
  userId: string;
  claims: Record<string, unknown>;
}

interface RequestTrace {
  requestId: string;
  phase: string;
}

interface CreateUploadRequest {
  title?: string;
  description?: string;
  category?: string;
  confirmedRights?: boolean;
  videoContentType?: string;
  videoFileSize?: number;
  thumbnailContentType?: string;
}

interface CompleteUploadRequest {
  uploadId?: string;
  videoObjectKey?: string;
  thumbnailObjectKey?: string;
  title?: string;
  description?: string;
  category?: string;
}

interface JWTHeader {
  alg?: string;
  kid?: string;
  typ?: string;
}

interface SupabaseJWK extends JsonWebKey {
  kid?: string;
  alg?: string;
}

interface JWKSResponse {
  keys?: SupabaseJWK[];
}

const ALLOWED_VIDEO_TYPES = new Map<string, string>([
  ["video/mp4", "mp4"],
  ["video/quicktime", "mov"]
]);

const ALLOWED_CATEGORIES = new Set([
  "Cinematic",
  "Nature",
  "Space",
  "Anime",
  "Abstract",
  "Cars",
  "City",
  "Minimal",
  "Game",
  "Other"
]);

const DEFAULT_UPLOAD_TTL_SECONDS = 15 * 60;
const DEFAULT_MAX_UPLOAD_BYTES = 500 * 1024 * 1024;
const DEFAULT_JWKS_CACHE_SECONDS = 5 * 60;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

let cachedSupabaseJWKS: {
  supabaseURL: string;
  keys: SupabaseJWK[];
  expiresAt: number;
} | null = null;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const trace: RequestTrace = {
      requestId: crypto.randomUUID(),
      phase: "request_routing"
    };
    try {
      if (request.method === "OPTIONS") {
        return withCors(new Response(null, { status: 204 }), env);
      }

      const url = new URL(request.url);
      const path = trimTrailingSlash(url.pathname);

      if (request.method === "GET" && path === "/health") {
        return json({ ok: true, service: "motiondock-marketplace-upload-worker" }, env);
      }

      if (request.method === "POST" && path === "/v1/uploads/create") {
        return await handleCreateUpload(request, env, trace);
      }

      if (request.method === "POST" && path === "/v1/uploads/complete") {
        const auth = await requireAuth(request, env);
        return await handleCompleteUpload(request, env, auth);
      }

      const deleteMatch = path.match(/^\/v1\/uploads\/([^/]+)$/);
      if (request.method === "DELETE" && deleteMatch) {
        const auth = await requireAuth(request, env);
        return await handleDeleteUpload(deleteMatch[1], env, auth);
      }

      return json({ error: "Not Found" }, env, 404);
    } catch (error) {
      return errorResponse(error, env, trace);
    }
  }
};

async function handleCreateUpload(request: Request, env: Env, trace: RequestTrace): Promise<Response> {
  logUploadPhase(trace, "request_received");

  const auth = await runUploadAwait(trace, "jwt_verification", async () => requireAuth(request, env));
  console.info(`[Marketplace Upload Worker] requestId=${trace.requestId} jwt verified success`);
  console.info(`[Marketplace Upload Worker] requestId=${trace.requestId} user extracted userId=${auth.userId}`);

  runUploadStep(trace, "env_validation", () => {
    assertRequiredEnv(env);
    // The Worker uses S3-compatible credentials rather than a Workers R2 binding.
    console.info(
      `[Marketplace Upload Worker] requestId=${trace.requestId} env validation `
      + `SUPABASE_URL=${Boolean(env.SUPABASE_URL?.trim())} `
      + `SUPABASE_SERVICE_ROLE_KEY=${Boolean(env.SUPABASE_SERVICE_ROLE_KEY?.trim())} `
      + `R2_BUCKET=${Boolean(env.R2_BUCKET?.trim())} `
      + `R2_ENDPOINT=${Boolean(env.R2_ENDPOINT?.trim())}`
    );
  });

  runUploadStep(trace, "supabase_client_initialization", () => {
    new URL(env.SUPABASE_URL);
    if (!env.SUPABASE_SERVICE_ROLE_KEY.trim()) {
      throw new HttpError(500, "Worker is not configured. Missing: SUPABASE_SERVICE_ROLE_KEY.");
    }
    console.info(`[Marketplace Upload Worker] requestId=${trace.requestId} supabase client initialized`);
  });

  runUploadStep(trace, "r2_binding_check", () => {
    if (!env.R2_BUCKET.trim()) {
      throw new HttpError(500, "Worker is not configured. Missing: R2_BUCKET.");
    }
    console.info(`[Marketplace Upload Worker] requestId=${trace.requestId} R2 binding check success`);
  });

  const body = await runUploadAwait(trace, "request_body_parsing", async () => readJson<CreateUploadRequest>(request));
  const validated = runUploadStep(trace, "request_validation", () => {
    const title = requireNonEmptyString(body.title, "title");
    const category = normalizeCategory(body.category);
    if (body.confirmedRights !== true) {
      throw new HttpError(400, "Upload terms must be accepted.");
    }

    const videoContentType = requireNonEmptyString(body.videoContentType, "videoContentType").toLowerCase();
    const extension = ALLOWED_VIDEO_TYPES.get(videoContentType);
    if (!extension) {
      throw new HttpError(400, "Only video/mp4 and video/quicktime uploads are allowed.");
    }

    const videoFileSize = body.videoFileSize;
    if (!Number.isFinite(videoFileSize) || videoFileSize == null || videoFileSize <= 0) {
      throw new HttpError(400, "videoFileSize must be a positive number.");
    }
    if (videoFileSize > maxUploadBytes(env)) {
      throw new HttpError(413, "Video file is too large.");
    }

    const thumbnailContentType = body.thumbnailContentType?.trim() || "image/jpeg";
    if (thumbnailContentType !== "image/jpeg") {
      throw new HttpError(400, "thumbnailContentType must be image/jpeg.");
    }

    return { title, category, videoContentType, extension, thumbnailContentType };
  });

  const uploadRecord = runUploadStep(trace, "upload_record_creation", () => {
    console.info(`[Marketplace Upload Worker] requestId=${trace.requestId} upload record creation start`);
    const uploadId = crypto.randomUUID();
    const record = {
      uploadId,
      videoObjectKey: `wallpapers/${uploadId}.${validated.extension}`,
      thumbnailObjectKey: `thumbnails/${uploadId}.jpg`
    };
    console.info(`[Marketplace Upload Worker] requestId=${trace.requestId} upload record creation success uploadId=${uploadId}`);
    return record;
  });

  console.info(`[Marketplace Upload Worker] requestId=${trace.requestId} presigned url generation start target=video`);
  const videoUpload = await runUploadAwait(trace, "presigned_url_generation_video", async () => presignR2URL(env, {
    method: "PUT",
    objectKey: uploadRecord.videoObjectKey,
    contentType: validated.videoContentType,
    expiresIn: uploadTTLSeconds(env)
  }));
  console.info(`[Marketplace Upload Worker] requestId=${trace.requestId} presigned url generation success target=video`);

  console.info(`[Marketplace Upload Worker] requestId=${trace.requestId} presigned url generation start target=thumbnail`);
  const thumbnailUpload = await runUploadAwait(trace, "presigned_url_generation_thumbnail", async () => presignR2URL(env, {
    method: "PUT",
    objectKey: uploadRecord.thumbnailObjectKey,
    contentType: validated.thumbnailContentType,
    expiresIn: uploadTTLSeconds(env)
  }));
  console.info(`[Marketplace Upload Worker] requestId=${trace.requestId} presigned url generation success target=thumbnail`);

  return runUploadStep(trace, "response_serialization", () => {
    console.info(`[Marketplace Upload Worker] requestId=${trace.requestId} response serialization`);
    return json({
      uploadId: uploadRecord.uploadId,
      title: validated.title,
      category: validated.category,
      videoObjectKey: uploadRecord.videoObjectKey,
      thumbnailObjectKey: uploadRecord.thumbnailObjectKey,
      videoUploadUrl: videoUpload.url,
      thumbnailUploadUrl: thumbnailUpload.url,
      requiredVideoHeaders: { "Content-Type": validated.videoContentType },
      requiredThumbnailHeaders: { "Content-Type": validated.thumbnailContentType },
      expiresAt: videoUpload.expiresAt
    }, env);
  });
}

async function handleCompleteUpload(request: Request, env: Env, auth: AuthContext): Promise<Response> {
  assertRequiredEnv(env);
  const body = await readJson<CompleteUploadRequest>(request);
  const uploadId = requireValidUUID(body.uploadId, "uploadId");
  const videoObjectKey = requireNonEmptyString(body.videoObjectKey, "videoObjectKey");
  const thumbnailObjectKey = requireNonEmptyString(body.thumbnailObjectKey, "thumbnailObjectKey");
  const title = requireNonEmptyString(body.title, "title");
  const description = body.description?.trim() || null;
  const category = normalizeCategory(body.category);

  validateVideoObjectKey(uploadId, videoObjectKey);
  validateThumbnailObjectKey(uploadId, thumbnailObjectKey);

  await assertR2ObjectExists(env, videoObjectKey);
  await assertR2ObjectExists(env, thumbnailObjectKey);

  const videoURL = publicURL(env, videoObjectKey);
  const thumbnailURL = publicURL(env, thumbnailObjectKey);
  const wallpaper = await insertWallpaper(env, {
    id: uploadId,
    title,
    description,
    category,
    uploader_id: auth.userId,
    video_url: videoURL,
    thumbnail_url: thumbnailURL
  });

  return json({ wallpaper }, env);
}

async function handleDeleteUpload(wallpaperId: string, env: Env, auth: AuthContext): Promise<Response> {
  assertRequiredEnv(env);
  const id = requireValidUUID(wallpaperId, "wallpaperId");
  const wallpaper = await getWallpaperForDelete(env, id);
  if (!wallpaper) {
    throw new HttpError(404, "Wallpaper not found.");
  }
  if (wallpaper.uploader_id !== auth.userId) {
    throw new HttpError(403, "You can only delete wallpapers uploaded by your account.");
  }

  const objectKeys = new Set<string>();
  const videoKey = objectKeyFromPublicURL(env, wallpaper.video_url);
  if (videoKey) objectKeys.add(videoKey);
  const thumbnailKey = objectKeyFromPublicURL(env, wallpaper.thumbnail_url);
  if (thumbnailKey) objectKeys.add(thumbnailKey);

  for (const objectKey of objectKeys) {
    await deleteR2Object(env, objectKey);
  }

  await deleteWallpaperRow(env, id);
  return json({ deleted: true }, env);
}

async function requireAuth(request: Request, env: Env): Promise<AuthContext> {
  const authorization = request.headers.get("Authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw new HttpError(401, "Missing bearer token.");
  }

  const token = match[1];
  const [encodedHeader, encodedPayload, encodedSignature] = token.split(".");
  if (!encodedHeader || !encodedPayload || !encodedSignature) {
    throw new HttpError(401, "Invalid bearer token.");
  }

  const header = decodeJWTJSON<JWTHeader>(encodedHeader, "header");
  await verifyJWTSignature(env, header, encodedHeader, encodedPayload, encodedSignature);

  const claims = decodeJWTJSON<Record<string, unknown>>(encodedPayload, "payload");
  const now = Math.floor(Date.now() / 1000);
  if (typeof claims.exp === "number" && claims.exp <= now) {
    throw new HttpError(401, "Token has expired.");
  }
  if (typeof claims.nbf === "number" && claims.nbf > now) {
    throw new HttpError(401, "Token is not active yet.");
  }
  if (typeof claims.sub !== "string" || !claims.sub.trim()) {
    throw new HttpError(401, "Token is missing subject.");
  }

  return { userId: claims.sub, claims };
}

async function verifyJWTSignature(
  env: Env,
  header: JWTHeader,
  encodedHeader: string,
  encodedPayload: string,
  encodedSignature: string
): Promise<void> {
  const algorithm = header.alg || "";
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  console.info(`[Marketplace Upload Worker] verifying Supabase JWT alg=${algorithm || "missing"} kid=${header.kid || "none"}`);

  if (algorithm === "HS256") {
    await verifyHS256JWT(env, signingInput, encodedSignature);
    return;
  }

  if (algorithm === "RS256" || algorithm === "ES256") {
    await verifyJWKSJWT(env, header, signingInput, encodedSignature);
    return;
  }

  throw new HttpError(401, `Unsupported token algorithm: ${algorithm || "missing"}.`);
}

async function verifyHS256JWT(env: Env, signingInput: string, encodedSignature: string): Promise<void> {
  const secret = env.SUPABASE_JWT_SECRET?.trim();
  if (!secret) {
    throw new HttpError(500, "Worker is not configured. Missing: SUPABASE_JWT_SECRET.");
  }

  const signature = base64URLToBytes(encodedSignature);
  const key = await crypto.subtle.importKey(
    "raw",
    utf8Buffer(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"]
  );
  const isValid = await crypto.subtle.verify(
    "HMAC",
    key,
    arrayBuffer(signature),
    utf8Buffer(signingInput)
  );
  if (!isValid) {
    throw new HttpError(401, "Token signature verification failed.");
  }
}

async function verifyJWKSJWT(
  env: Env,
  header: JWTHeader,
  signingInput: string,
  encodedSignature: string
): Promise<void> {
  const algorithm = header.alg || "";
  const jwks = await runWorkerAwait("jwks_fetch", async () => fetchSupabaseJWKS(env));
  const signingKey = selectJWK(jwks, header);
  if (!signingKey) {
    throw new HttpError(401, "Token signing key was not found in Supabase JWKS.");
  }

  console.info(`[Marketplace Upload Worker] crypto.subtle.importKey start alg=${algorithm}`);
  const cryptoKey = await runWorkerAwait("jwt_crypto_import_key", async () => crypto.subtle.importKey(
    "jwk",
    signingKey,
    jwkImportAlgorithm(algorithm),
    false,
    ["verify"]
  ));
  console.info(`[Marketplace Upload Worker] crypto.subtle.importKey success alg=${algorithm}`);

  console.info(`[Marketplace Upload Worker] crypto.subtle.verify start alg=${algorithm}`);
  const isValid = await runWorkerAwait("jwt_crypto_verify", async () => crypto.subtle.verify(
    jwkVerifyAlgorithm(algorithm),
    cryptoKey,
    arrayBuffer(base64URLToBytes(encodedSignature)),
    utf8Buffer(signingInput)
  ));
  console.info(`[Marketplace Upload Worker] crypto.subtle.verify success alg=${algorithm} valid=${isValid}`);
  if (!isValid) {
    throw new HttpError(401, "Token signature verification failed.");
  }
}

function selectJWK(keys: SupabaseJWK[], header: JWTHeader): SupabaseJWK | null {
  const algorithm = header.alg || "";
  if (header.kid) {
    const exact = keys.find((key) => key.kid === header.kid);
    if (exact) return exact;
  }

  const matchingAlgorithm = keys.filter((key) => !key.alg || key.alg === algorithm);
  if (matchingAlgorithm.length === 1) {
    return matchingAlgorithm[0];
  }
  return null;
}

async function fetchSupabaseJWKS(env: Env): Promise<SupabaseJWK[]> {
  const supabaseURL = env.SUPABASE_URL?.replace(/\/+$/, "");
  if (!supabaseURL) {
    throw new HttpError(500, "Worker is not configured. Missing: SUPABASE_URL.");
  }

  const now = Date.now();
  if (cachedSupabaseJWKS && cachedSupabaseJWKS.supabaseURL === supabaseURL && cachedSupabaseJWKS.expiresAt > now) {
    return cachedSupabaseJWKS.keys;
  }

  const response = await runWorkerAwait("jwks_network_request", async () => fetch(
    `${supabaseURL}/auth/v1/.well-known/jwks.json`,
    { headers: { Accept: "application/json" } }
  ));
  if (!response.ok) {
    throw new HttpError(500, `Could not fetch Supabase JWKS: ${response.status}.`);
  }

  const body = await runWorkerAwait("jwks_response_decode", async () => response.json() as Promise<JWKSResponse>);
  if (!Array.isArray(body.keys) || body.keys.length === 0) {
    throw new HttpError(500, "Supabase JWKS did not contain signing keys.");
  }

  cachedSupabaseJWKS = {
    supabaseURL,
    keys: body.keys,
    expiresAt: now + jwksCacheSeconds(env) * 1000
  };
  return body.keys;
}

function jwkImportAlgorithm(algorithm: string): AlgorithmIdentifier | RsaHashedImportParams | EcKeyImportParams {
  if (algorithm === "RS256") {
    return { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" };
  }
  if (algorithm === "ES256") {
    return { name: "ECDSA", namedCurve: "P-256" };
  }
  throw new HttpError(401, `Unsupported token algorithm: ${algorithm || "missing"}.`);
}

function jwkVerifyAlgorithm(algorithm: string): AlgorithmIdentifier | RsaHashedImportParams | EcdsaParams {
  if (algorithm === "RS256") {
    return { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" };
  }
  if (algorithm === "ES256") {
    return { name: "ECDSA", hash: "SHA-256" };
  }
  throw new HttpError(401, `Unsupported token algorithm: ${algorithm || "missing"}.`);
}

async function insertWallpaper(
  env: Env,
  row: {
    id: string;
    title: string;
    description: string | null;
    category: string;
    uploader_id: string;
    video_url: string;
    thumbnail_url: string;
  }
): Promise<unknown> {
  const response = await supabaseFetch(env, "/rest/v1/wallpapers", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Prefer": "return=representation"
    },
    body: JSON.stringify({
      ...row,
      downloads: 0,
      likes_count: 0,
      report_count: 0,
      is_hidden: false,
      uploader_confirmed_rights: true,
      created_at: new Date().toISOString()
    })
  });
  const jsonBody = await response.json() as unknown[];
  return jsonBody[0] ?? null;
}

async function getWallpaperForDelete(env: Env, id: string): Promise<{
  id: string;
  uploader_id: string;
  video_url: string | null;
  thumbnail_url: string | null;
} | null> {
  const query = `/rest/v1/wallpapers?id=eq.${encodeURIComponent(id)}&select=id,uploader_id,video_url,thumbnail_url`;
  const response = await supabaseFetch(env, query, { method: "GET" });
  const rows = await response.json() as Array<{
    id: string;
    uploader_id: string;
    video_url: string | null;
    thumbnail_url: string | null;
  }>;
  return rows[0] ?? null;
}

async function deleteWallpaperRow(env: Env, id: string): Promise<void> {
  await supabaseFetch(env, `/rest/v1/wallpapers?id=eq.${encodeURIComponent(id)}`, {
    method: "DELETE"
  });
}

async function supabaseFetch(env: Env, pathAndQuery: string, init: RequestInit): Promise<Response> {
  const baseURL = env.SUPABASE_URL.replace(/\/+$/, "");
  const response = await fetch(`${baseURL}${pathAndQuery}`, {
    ...init,
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      ...(init.headers || {})
    }
  });

  if (!response.ok) {
    const message = await response.text();
    throw new HttpError(response.status, message || "Supabase request failed.");
  }
  return response;
}

async function assertR2ObjectExists(env: Env, objectKey: string): Promise<void> {
  const signed = await presignR2URL(env, {
    method: "HEAD",
    objectKey,
    expiresIn: 120
  });
  const response = await fetch(signed.url, { method: "HEAD" });
  if (!response.ok) {
    throw new HttpError(400, `Uploaded object is missing: ${objectKey}`);
  }
}

async function deleteR2Object(env: Env, objectKey: string): Promise<void> {
  const signed = await presignR2URL(env, {
    method: "DELETE",
    objectKey,
    expiresIn: 120
  });
  const response = await fetch(signed.url, { method: "DELETE" });
  if (![200, 202, 204, 404].includes(response.status)) {
    throw new HttpError(response.status, `Could not delete R2 object: ${objectKey}`);
  }
}

async function presignR2URL(
  env: Env,
  input: {
    method: "PUT" | "HEAD" | "DELETE";
    objectKey: string;
    contentType?: string;
    expiresIn: number;
  }
): Promise<{ url: string; expiresAt: string }> {
  const now = new Date();
  const endpointURL = r2ObjectURL(env, input.objectKey);
  endpointURL.searchParams.set("X-Amz-Expires", String(input.expiresIn));
  const headers = new Headers();
  if (input.contentType) {
    headers.set("Content-Type", input.contentType);
  }

  const client = new AwsClient({
    service: "s3",
    region: env.R2_REGION?.trim() || "auto",
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY
  });
  console.info(
    `[Marketplace Upload Worker] presign target method=${input.method} `
    + `bucket=${env.R2_BUCKET} objectKey=${input.objectKey} `
    + `contentType=${input.contentType || "none"}`
  );
  const signedRequest = await runWorkerAwait("r2_aws4_presign", async () => client.sign(
    new Request(endpointURL, {
      method: input.method,
      headers
    }),
    { aws: { signQuery: true, allHeaders: true } }
  ));
  const signedURL = new URL(signedRequest.url);
  console.info(
    `[Marketplace Upload Worker] signed url host=${signedURL.host} path=${signedURL.pathname} `
    + `signedHeaders=${signedURL.searchParams.get("X-Amz-SignedHeaders") || "missing"}`
  );

  return {
    url: signedRequest.url,
    expiresAt: new Date(now.getTime() + input.expiresIn * 1000).toISOString()
  };
}

function r2ObjectURL(env: Env, objectKey: string): URL {
  const endpoint = new URL(env.R2_ENDPOINT);
  const baseSegments = endpoint.pathname.split("/").filter(Boolean);
  const segments = [
    ...baseSegments,
    env.R2_BUCKET,
    ...objectKey.split("/").filter(Boolean)
  ];
  endpoint.pathname = `/${segments.map(awsPercentEncode).join("/")}`;
  endpoint.search = "";
  return endpoint;
}

function objectKeyFromPublicURL(env: Env, rawURL: string | null): string | null {
  if (!rawURL) return null;
  const base = new URL(env.R2_PUBLIC_BASE_URL);
  const url = new URL(rawURL);
  if (url.protocol !== base.protocol || url.host !== base.host) {
    throw new HttpError(400, "Wallpaper URL is outside the configured R2 public base URL.");
  }

  const basePath = base.pathname.replace(/^\/+|\/+$/g, "");
  let objectPath = url.pathname.replace(/^\/+|\/+$/g, "");
  if (basePath) {
    if (objectPath !== basePath && !objectPath.startsWith(`${basePath}/`)) {
      throw new HttpError(400, "Wallpaper URL path does not match the configured R2 public base URL.");
    }
    objectPath = objectPath.slice(basePath.length).replace(/^\/+/, "");
  }
  return objectPath ? decodeURIComponent(objectPath) : null;
}

function publicURL(env: Env, objectKey: string): string {
  const base = new URL(env.R2_PUBLIC_BASE_URL);
  const basePath = base.pathname.replace(/\/+$/, "");
  base.pathname = `${basePath}/${objectKey.split("/").map(awsPercentEncode).join("/")}`;
  return base.toString();
}

function validateVideoObjectKey(uploadId: string, objectKey: string): void {
  const pattern = new RegExp(`^wallpapers/${escapeRegExp(uploadId)}\\.(mp4|mov)$`);
  if (!pattern.test(objectKey)) {
    throw new HttpError(400, "Invalid videoObjectKey.");
  }
}

function validateThumbnailObjectKey(uploadId: string, objectKey: string): void {
  if (objectKey !== `thumbnails/${uploadId}.jpg`) {
    throw new HttpError(400, "Invalid thumbnailObjectKey.");
  }
}

function normalizeCategory(value: string | undefined): string {
  const category = value?.trim() || "Other";
  if (!ALLOWED_CATEGORIES.has(category)) {
    throw new HttpError(400, "Invalid category.");
  }
  return category;
}

function requireNonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpError(400, `${field} is required.`);
  }
  return value.trim();
}

function requireValidUUID(value: unknown, field: string): string {
  const id = requireNonEmptyString(value, field).toLowerCase();
  if (!UUID_PATTERN.test(id)) {
    throw new HttpError(400, `${field} must be a UUID.`);
  }
  return id;
}

function maxUploadBytes(env: Env): number {
  const parsed = Number(env.MAX_UPLOAD_BYTES);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_MAX_UPLOAD_BYTES;
}

function uploadTTLSeconds(env: Env): number {
  const parsed = Number(env.UPLOAD_URL_TTL_SECONDS);
  return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : DEFAULT_UPLOAD_TTL_SECONDS;
}

function jwksCacheSeconds(env: Env): number {
  const parsed = Number(env.SUPABASE_JWKS_TTL_SECONDS);
  return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : DEFAULT_JWKS_CACHE_SECONDS;
}

function assertRequiredEnv(env: Env): void {
  const missing = [
    "SUPABASE_URL",
    "SUPABASE_SERVICE_ROLE_KEY",
    "R2_BUCKET",
    "R2_PUBLIC_BASE_URL",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
    "R2_ENDPOINT"
  ].filter((key) => !String(env[key as keyof Env] || "").trim());

  if (missing.length > 0) {
    throw new HttpError(500, `Worker is not configured. Missing: ${missing.join(", ")}.`);
  }
}

async function readJson<T>(request: Request): Promise<T> {
  try {
    return await request.json() as T;
  } catch {
    throw new HttpError(400, "Request body must be valid JSON.");
  }
}

function json(body: unknown, env: Env, status = 200): Response {
  return withCors(new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    }
  }), env);
}

function withCors(response: Response, env: Env): Response {
  const headers = new Headers(response.headers);
  headers.set("Access-Control-Allow-Origin", env.CORS_ORIGIN || "*");
  headers.set("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS");
  headers.set("Access-Control-Allow-Headers", "Authorization,Content-Type");
  headers.set("Access-Control-Max-Age", "86400");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}

function errorResponse(error: unknown, env: Env, trace?: RequestTrace): Response {
  const phaseError = toPhaseError(trace?.phase || "unhandled_request", error);
  console.error(`[Marketplace Upload Worker] request failed phase=${phaseError.phase}`);
  console.error(`[Marketplace Upload Worker] error.name=${phaseError.originalName}`);
  console.error(`[Marketplace Upload Worker] error.message=${phaseError.message}`);
  console.error(`[Marketplace Upload Worker] error.stack=${phaseError.originalStack || "unavailable"}`);
  return json({
    error: phaseError.message,
    phase: phaseError.phase
  }, env, phaseError.status);
}

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = "HttpError";
  }
}

class PhaseError extends Error {
  readonly status: number;
  readonly phase: string;
  readonly originalName: string;
  readonly originalStack?: string;

  constructor(phase: string, error: unknown) {
    const normalized = normalizeError(error);
    super(normalized.message);
    this.name = "PhaseError";
    this.status = error instanceof HttpError ? error.status : 500;
    this.phase = phase;
    this.originalName = normalized.name;
    this.originalStack = normalized.stack;
  }
}

function normalizeError(error: unknown): { name: string; message: string; stack?: string } {
  if (error instanceof Error) {
    return {
      name: error.name || "Error",
      message: error.message || "Unknown error",
      stack: error.stack
    };
  }
  return {
    name: typeof error,
    message: String(error)
  };
}

function toPhaseError(phase: string, error: unknown): PhaseError {
  return error instanceof PhaseError ? error : new PhaseError(phase, error);
}

function logUploadPhase(trace: RequestTrace, phase: string): void {
  trace.phase = phase;
  console.info(`[Marketplace Upload Worker] requestId=${trace.requestId} phase=${phase}`);
}

function runUploadStep<T>(trace: RequestTrace, phase: string, operation: () => T): T {
  logUploadPhase(trace, phase);
  try {
    return operation();
  } catch (error) {
    const phaseError = toPhaseError(phase, error);
    logPhaseFailure(phaseError, trace.requestId);
    throw phaseError;
  }
}

async function runUploadAwait<T>(
  trace: RequestTrace,
  phase: string,
  operation: () => Promise<T>
): Promise<T> {
  logUploadPhase(trace, phase);
  try {
    return await operation();
  } catch (error) {
    const phaseError = toPhaseError(phase, error);
    logPhaseFailure(phaseError, trace.requestId);
    throw phaseError;
  }
}

async function runWorkerAwait<T>(phase: string, operation: () => Promise<T>): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    const phaseError = toPhaseError(phase, error);
    logPhaseFailure(phaseError);
    throw phaseError;
  }
}

function logPhaseFailure(error: PhaseError, requestId?: string): void {
  const requestPart = requestId ? ` requestId=${requestId}` : "";
  console.error(`[Marketplace Upload Worker] phase failure${requestPart} phase=${error.phase}`);
  console.error(`[Marketplace Upload Worker] error.name=${error.originalName}`);
  console.error(`[Marketplace Upload Worker] error.message=${error.message}`);
  console.error(`[Marketplace Upload Worker] error.stack=${error.originalStack || "unavailable"}`);
}

function trimTrailingSlash(path: string): string {
  if (path.length > 1 && path.endsWith("/")) {
    return path.replace(/\/+$/, "");
  }
  return path;
}

function base64URLToBytes(value: string): Uint8Array {
  let normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  normalized += "=".repeat((4 - normalized.length % 4) % 4);
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function decodeJWTJSON<T>(encodedValue: string, label: string): T {
  try {
    return JSON.parse(new TextDecoder().decode(base64URLToBytes(encodedValue))) as T;
  } catch {
    throw new HttpError(401, `Invalid token ${label}.`);
  }
}

function awsPercentEncode(value: string): string {
  return encodeURIComponent(value).replace(/[!'()*]/g, (character) => (
    `%${character.charCodeAt(0).toString(16).toUpperCase()}`
  ));
}

function utf8Buffer(value: string): ArrayBuffer {
  return arrayBuffer(new TextEncoder().encode(value));
}

function arrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
