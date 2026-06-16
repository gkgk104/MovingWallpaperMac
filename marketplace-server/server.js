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
const maxUploadBytes = Number(process.env.MAX_UPLOAD_MB || 250) * 1024 * 1024;

fs.mkdirSync(filesDir, { recursive: true });
if (!fs.existsSync(dbPath)) {
  fs.writeFileSync(dbPath, "[]\n");
}

const mimeTypes = {
  ".gif": "image/gif",
  ".mp4": "video/mp4",
  ".m4v": "video/x-m4v",
  ".mov": "video/quicktime",
  ".webm": "video/webm",
  ".avi": "video/x-msvideo"
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
  if (explicitKind === "gif" || ext === ".gif") return "gif";
  if (explicitKind === "video" || [".mp4", ".m4v", ".mov", ".webm", ".avi"].includes(ext)) return "video";
  return null;
}

function publicItem(item) {
  return {
    id: item.id,
    title: item.title,
    kind: item.kind,
    filename: item.filename,
    size: item.size,
    createdAt: item.createdAt,
    downloadURL: `/files/${encodeURIComponent(item.storedName)}`,
    uploaderName: item.uploaderName || "Unknown",
    uploaderID: item.uploaderID || ""
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
        reject(new Error(`Upload exceeds ${Math.floor(maxUploadBytes / 1024 / 1024)} MB`));
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
  const kind = inferKind(originalName, fields.get("kind"));
  if (!kind) {
    sendError(response, 400, "Only GIF and common video files are supported");
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
    uploaderID: cleanText(fields.get("uploaderID"), "", 120)
  };

  const items = readDB();
  items.unshift(item);
  writeDB(items);
  sendJSON(response, 201, publicItem(item));
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
      "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type"
    });
    response.end();
    return;
  }

  if (request.method === "GET" && url.pathname === "/api/wallpapers") {
    sendJSON(response, 200, readDB().map(publicItem));
    return;
  }

  if (request.method === "POST" && url.pathname === "/api/wallpapers") {
    await handleUpload(request, response);
    return;
  }

  if (request.method === "GET" && url.pathname.startsWith("/files/")) {
    handleDownload(request, response, url.pathname);
    return;
  }

  if (request.method === "GET" && url.pathname === "/") {
    sendJSON(response, 200, {
      name: "MotionDock Marketplace",
      endpoints: ["/api/wallpapers", "/files/:storedName"]
    });
    return;
  }

  sendError(response, 404, "Not found");
});

server.listen(port, host, () => {
  console.log(`MotionDock Marketplace running at http://${host}:${port}`);
});
