#!/usr/bin/env node

const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const rootDir = __dirname;
const dataDir = path.join(rootDir, "data");
const filesDir = path.join(dataDir, "files");
const dbPath = path.join(dataDir, "wallpapers.json");
const port = Number(process.env.PORT || 8787);
const host = process.env.HOST || "127.0.0.1";
const maxUploadMegabytes = Number(process.env.MAX_UPLOAD_MB || 250);
const maxUploadBytes = maxUploadMegabytes * 1024 * 1024;
const maxUserStorageMegabytes = Number(process.env.MAX_USER_STORAGE_MB || 1024);
const maxUserStorageBytes = maxUserStorageMegabytes * 1024 * 1024;
const moderationMode = process.env.MODERATION_MODE === "manual" ? "manual" : "auto";
const moderationAdminToken = process.env.MODERATION_ADMIN_TOKEN || "";
const defaultModerationStatus = moderationMode === "manual" ? "pending" : "approved";
const moderationStatuses = new Set(["pending", "approved", "rejected"]);
const supportedVideoExtensions = new Set([".mp4", ".m4v", ".mov"]);
const supportedGIFExtensions = new Set([".gif"]);
const supportedUploadExtensions = new Set([
  ...supportedVideoExtensions,
  ...supportedGIFExtensions
]);

fs.mkdirSync(filesDir, { recursive: true });
if (!fs.existsSync(dbPath)) {
  fs.writeFileSync(dbPath, "[]\n");
}

const mimeTypes = {
  ".gif": "image/gif",
  ".mp4": "video/mp4",
  ".m4v": "video/x-m4v",
  ".mov": "video/quicktime"
};

function readDB() {
  try {
    return JSON.parse(fs.readFileSync(dbPath, "utf8"));
  } catch {
    return [];
  }
}

function writeDB(items) {
  fs.writeFileSync(dbPath, JSON.stringify(items, null, 2) + "\n");
}

function sendJSON(response, status, payload) {
  const body = JSON.stringify(payload);
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Access-Control-Allow-Origin": "*"
  });
  response.end(body);
}

function sendError(response, status, message) {
  sendJSON(response, status, { error: message });
}

function safeName(name) {
  return path.basename(name || "wallpaper").replace(/[^a-zA-Z0-9._-]/g, "_");
}

function cleanText(value, fallback, maxLength = 80) {
  const text = String(value || "")
    .replace(/\s+/g, " ")
    .trim();
  return text ? text.slice(0, maxLength) : fallback;
}

function inferKind(filename, explicitKind) {
  const ext = path.extname(filename).toLowerCase();
  if (supportedGIFExtensions.has(ext)) {
    return !explicitKind || explicitKind === "gif" ? "gif" : null;
  }
  if (supportedVideoExtensions.has(ext)) {
    return !explicitKind || explicitKind === "video" ? "video" : null;
  }
  return null;
}

function normalizedUploaderID(value) {
  return cleanText(value, "anonymous", 120);
}

function storageUsedByUploader(items, uploaderID) {
  const key = normalizedUploaderID(uploaderID);
  return items.reduce((total, item) => {
    const itemUploaderID = normalizedUploaderID(item.uploader_id || item.uploaderID);
    if (itemUploaderID !== key) {
      return total;
    }
    return total + Number(item.size || 0);
  }, 0);
}

function moderationStatus(value) {
  const status = String(value || "").toLowerCase();
  return moderationStatuses.has(status) ? status : "approved";
}

function isAdminRequest(request, url) {
  if (!moderationAdminToken) {
    return false;
  }
  const header = request.headers.authorization || "";
  return header === `Bearer ${moderationAdminToken}`
    || url.searchParams.get("adminToken") === moderationAdminToken;
}

function visibleItems(items, request, url) {
  if (isAdminRequest(request, url) && url.searchParams.get("include") === "all") {
    return items;
  }
  return items.filter((item) => moderationStatus(item.moderationStatus) === "approved");
}

function publicItem(item) {
  const uploaderID = item.uploader_id || item.uploaderID || "";
  return {
    id: item.id,
    title: item.title,
    kind: item.kind,
    filename: item.filename,
    size: item.size,
    createdAt: item.createdAt,
    downloadURL: `/files/${encodeURIComponent(item.storedName)}`,
    uploaderName: item.uploaderName || "Unknown",
    uploader_id: uploaderID,
    uploaderID,
    moderation_status: moderationStatus(item.moderationStatus),
    moderationStatus: moderationStatus(item.moderationStatus),
    reviewed_at: item.reviewedAt || null,
    reviewedAt: item.reviewedAt || null,
    rejection_reason: item.rejectionReason || null,
    rejectionReason: item.rejectionReason || null
  };
}

function collectBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;

    request.on("data", (chunk) => {
      total += chunk.length;
      if (total > maxUploadBytes) {
        request.destroy();
        reject(new Error(`Upload exceeds ${maxUploadMegabytes} MB`));
        return;
      }
      chunks.push(chunk);
    });

    request.on("end", () => resolve(Buffer.concat(chunks)));
    request.on("error", reject);
  });
}

function parseMultipart(body, contentType) {
  const boundaryMatch = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(contentType || "");
  if (!boundaryMatch) {
    throw new Error("Missing multipart boundary");
  }

  const boundary = Buffer.from(`--${boundaryMatch[1] || boundaryMatch[2]}`);
  const parts = [];
  let cursor = body.indexOf(boundary);

  while (cursor !== -1) {
    cursor += boundary.length;
    if (body.slice(cursor, cursor + 2).toString() === "--") break;
    if (body.slice(cursor, cursor + 2).toString() === "\r\n") cursor += 2;

    const headerEnd = body.indexOf(Buffer.from("\r\n\r\n"), cursor);
    if (headerEnd === -1) break;

    const headerText = body.slice(cursor, headerEnd).toString("utf8");
    const nextBoundary = body.indexOf(boundary, headerEnd + 4);
    if (nextBoundary === -1) break;

    let content = body.slice(headerEnd + 4, nextBoundary);
    if (content.slice(-2).toString() === "\r\n") {
      content = content.slice(0, -2);
    }

    const disposition = /content-disposition:\s*form-data;\s*([^\r\n]+)/i.exec(headerText);
    const nameMatch = disposition && /name="([^"]+)"/i.exec(disposition[1]);
    const filenameMatch = disposition && /filename="([^"]*)"/i.exec(disposition[1]);

    if (nameMatch) {
      parts.push({
        name: nameMatch[1],
        filename: filenameMatch ? filenameMatch[1] : null,
        content
      });
    }

    cursor = nextBoundary;
  }

  return parts;
}

async function handleUpload(request, response) {
  const contentType = request.headers["content-type"] || "";
  if (!contentType.toLowerCase().startsWith("multipart/form-data")) {
    sendError(response, 415, "Expected multipart/form-data");
    return;
  }

  let body;
  try {
    body = await collectBody(request);
  } catch (error) {
    sendError(response, 413, error.message);
    return;
  }

  let parts;
  try {
    parts = parseMultipart(body, contentType);
  } catch (error) {
    sendError(response, 400, error.message);
    return;
  }

  const fields = new Map();
  let filePart = null;

  for (const part of parts) {
    if (part.filename) {
      filePart = part;
    } else {
      fields.set(part.name, part.content.toString("utf8").trim());
    }
  }

  if (!filePart || filePart.content.length === 0) {
    sendError(response, 400, "Missing file");
    return;
  }

  const originalName = safeName(filePart.filename);
  const originalExtension = path.extname(originalName).toLowerCase();
  if (!supportedUploadExtensions.has(originalExtension)) {
    sendError(response, 400, "Only MP4, MOV, M4V, and GIF files are supported");
    return;
  }
  if (filePart.content.length > maxUploadBytes) {
    sendError(response, 413, `Upload exceeds ${maxUploadMegabytes} MB`);
    return;
  }

  const kind = inferKind(originalName, fields.get("kind"));
  if (!kind) {
    sendError(response, 400, "The uploaded file extension does not match the requested kind");
    return;
  }

  const uploaderID = normalizedUploaderID(fields.get("uploader_id") || fields.get("uploaderID"));
  const items = readDB();
  const currentUserStorageBytes = storageUsedByUploader(items, uploaderID);
  if (currentUserStorageBytes + filePart.content.length > maxUserStorageBytes) {
    sendError(response, 413, `User storage quota exceeds ${maxUserStorageMegabytes} MB`);
    return;
  }

  const id = crypto.randomUUID();
  const storedName = `${id}-${originalName}`;
  const filePath = path.join(filesDir, storedName);
  fs.writeFileSync(filePath, filePart.content);

  const item = {
    id,
    title: cleanText(fields.get("title"), path.parse(originalName).name, 120),
    kind,
    filename: originalName,
    storedName,
    size: filePart.content.length,
    createdAt: new Date().toISOString(),
    uploaderName: cleanText(fields.get("uploaderName"), "Unknown"),
    uploader_id: uploaderID,
    moderationStatus: defaultModerationStatus,
    reviewedAt: defaultModerationStatus === "approved" ? new Date().toISOString() : null,
    rejectionReason: null
  };

  items.unshift(item);
  writeDB(items);
  sendJSON(response, 201, publicItem(item));
}

async function handleModerationUpdate(request, response, url, id) {
  if (!isAdminRequest(request, url)) {
    sendError(response, 403, "Moderation admin token is required");
    return;
  }

  let body;
  try {
    body = await collectBody(request);
  } catch (error) {
    sendError(response, 400, error.message);
    return;
  }

  let payload;
  try {
    payload = JSON.parse(body.toString("utf8") || "{}");
  } catch {
    sendError(response, 400, "Expected JSON body");
    return;
  }

  const nextStatus = moderationStatus(payload.moderationStatus || payload.moderation_status);
  const items = readDB();
  const item = items.find((candidate) => candidate.id === id);
  if (!item) {
    sendError(response, 404, "Wallpaper not found");
    return;
  }

  item.moderationStatus = nextStatus;
  item.reviewedAt = new Date().toISOString();
  item.rejectionReason = nextStatus === "rejected"
    ? cleanText(payload.rejectionReason || payload.rejection_reason, "Rejected", 240)
    : null;

  writeDB(items);
  sendJSON(response, 200, publicItem(item));
}

function handleDownload(request, response, pathname) {
  const storedName = path.basename(decodeURIComponent(pathname.replace(/^\/files\//, "")));
  const filePath = path.join(filesDir, storedName);

  if (!fs.existsSync(filePath)) {
    sendError(response, 404, "File not found");
    return;
  }

  const stat = fs.statSync(filePath);
  const ext = path.extname(filePath).toLowerCase();
  response.writeHead(200, {
    "Content-Type": mimeTypes[ext] || "application/octet-stream",
    "Content-Length": stat.size,
    "Content-Disposition": `attachment; filename="${storedName.replace(/^[0-9a-f-]+-/, "")}"`,
    "Access-Control-Allow-Origin": "*"
  });
  fs.createReadStream(filePath).pipe(response);
}

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, `http://${request.headers.host || `${host}:${port}`}`);

  if (request.method === "OPTIONS") {
    response.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,POST,PATCH,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization"
    });
    response.end();
    return;
  }

  if (request.method === "GET" && url.pathname === "/api/wallpapers") {
    sendJSON(response, 200, visibleItems(readDB(), request, url).map(publicItem));
    return;
  }

  if (request.method === "POST" && url.pathname === "/api/wallpapers") {
    await handleUpload(request, response);
    return;
  }

  const moderationMatch = /^\/api\/wallpapers\/([^/]+)\/moderation$/.exec(url.pathname);
  if (request.method === "PATCH" && moderationMatch) {
    await handleModerationUpdate(request, response, url, decodeURIComponent(moderationMatch[1]));
    return;
  }

  if (request.method === "GET" && url.pathname.startsWith("/files/")) {
    handleDownload(request, response, url.pathname);
    return;
  }

  if (request.method === "GET" && url.pathname === "/") {
    sendJSON(response, 200, {
      name: "MotionDock Marketplace",
      endpoints: ["/api/wallpapers", "/api/wallpapers/:id/moderation", "/files/:storedName"],
      moderationMode
    });
    return;
  }

  sendError(response, 404, "Not found");
});

server.listen(port, host, () => {
  console.log(`MotionDock Marketplace running at http://${host}:${port}`);
});
