import http from "node:http";
import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { readFile } from "node:fs/promises";
import { createNextcloudWebDavClient, joinDavPath, safeDavPath } from "./nextcloud-webdav.mjs";

const driveSessionCookieName = "nas_drive_session";
const driveSessionTtlMs = 1000 * 60 * 60 * 12;
const fallbackDriveSessionSecret = randomBytes(32).toString("hex");

const defaultServiceTokens = {
  "replace-with-long-random-lms-token": {
    name: "Example LMS integration",
    root: "LMS",
    permissions: ["read", "write"],
  },
};

export function createIntegrationGatewayServer(options = {}) {
  const config = {
    tokens: normalizeTokens(options.tokens || loadTokensFromEnv()),
    webdav: options.webdavClient || createNextcloudWebDavClient({
      baseUrl: options.nextcloudBaseUrl || process.env.NEXTCLOUD_BASE_URL,
      username: options.nextcloudUsername || process.env.NEXTCLOUD_USERNAME,
      appPassword: options.nextcloudAppPassword || process.env.NEXTCLOUD_APP_PASSWORD,
      fetch: options.fetch,
    }),
    maxUploadBytes: Number(options.maxUploadBytes || process.env.NAS_GATEWAY_MAX_UPLOAD_BYTES || 1024 * 1024 * 1024),
    drivePassword: String(options.drivePassword ?? process.env.NAS_DRIVE_PASSWORD ?? ""),
    driveSessionSecret: String(options.driveSessionSecret ?? process.env.NAS_DRIVE_SESSION_SECRET ?? fallbackDriveSessionSecret),
  };

  return http.createServer(async (req, res) => {
    try {
      await route(req, res, config);
    } catch (error) {
      if (!error.status || error.status >= 500) {
        console.error(error);
      }
      sendJson(res, error.status || 500, {
        error: error.code || "internal_error",
        message: error.status ? error.message : "Integration gateway internal error",
      });
    }
  });
}

async function route(req, res, config) {
  setSecurityHeaders(res);
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);

  if ((req.method === "GET" || req.method === "HEAD") && url.pathname === "/health") {
    const health = {
      ok: true,
      integrations: Object.values(config.tokens).map((token) => ({
        name: token.name,
        root: token.root,
        permissions: token.permissions,
      })),
    };

    if (req.method === "HEAD") {
      res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
      res.end();
      return;
    }

    sendJson(res, 200, health);
    return;
  }

  if (req.method === "GET" && (url.pathname === "/drive" || url.pathname === "/drive/")) {
    await sendDriveUi(res);
    return;
  }

  if (url.pathname === "/drive/session") {
    await routeDriveSession(req, res, config);
    return;
  }

  if (url.pathname.startsWith("/drive/api/")) {
    await routeDriveApi(req, res, config, url);
    return;
  }

  if (req.method === "POST" && url.pathname === "/files/upload") {
    await routeCompatibleUpload(req, res, config);
    return;
  }

  if (req.method === "GET" && url.pathname === "/files/download") {
    await routeCompatibleDownload(req, res, config, url);
    return;
  }

  if (!url.pathname.startsWith("/api/cloud/")) {
    sendJson(res, 404, { error: "not_found" });
    return;
  }

  const token = requireGatewayToken(req, config.tokens);

  if (req.method === "GET" && url.pathname === "/api/cloud/list") {
    requirePermission(token, "read");
    const target = tokenPath(token, url.searchParams.get("path") || "");
    const entries = await config.webdav.list(target);
    sendJson(res, 200, { root: token.root, path: safeDavPath(url.searchParams.get("path") || "", { allowEmpty: true }), entries });
    return;
  }

  if (req.method === "PUT" && url.pathname === "/api/cloud/file") {
    requirePermission(token, "write");
    const relativePath = url.searchParams.get("path") || "";
    const target = tokenPath(token, relativePath);
    const body = await readRawBody(req, config.maxUploadBytes);
    const result = await config.webdav.upload(target, body, req.headers["content-type"] || "application/octet-stream");
    sendJson(res, 201, { root: token.root, path: safeDavPath(relativePath), upstreamStatus: result.status });
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/cloud/directory") {
    requirePermission(token, "write");
    const { path = "" } = await readJsonBody(req, config.maxUploadBytes);
    const relativePath = safeDavPath(path);
    await config.webdav.ensureDirectory(tokenPath(token, relativePath));
    sendJson(res, 201, { root: token.root, path: relativePath, created: true });
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/cloud/file") {
    requirePermission(token, "read");
    const target = tokenPath(token, url.searchParams.get("path") || "");
    const result = await config.webdav.download(target);
    const body = Buffer.from(await result.arrayBuffer());
    res.writeHead(200, {
      "content-type": result.contentType,
      "content-length": body.length,
    });
    res.end(body);
    return;
  }

  if (req.method === "DELETE" && url.pathname === "/api/cloud/file") {
    requirePermission(token, "delete");
    const relativePath = url.searchParams.get("path") || "";
    const result = await config.webdav.delete(tokenPath(token, relativePath));
    sendJson(res, 200, { root: token.root, path: safeDavPath(relativePath), deleted: result.deleted });
    return;
  }

  sendJson(res, 404, { error: "not_found" });
}

async function routeDriveSession(req, res, config) {
  if (req.method === "GET") {
    const authenticated = Boolean(readDriveSession(req, config));
    sendJson(res, 200, { authenticated, roots: authenticated ? driveRoots(config.tokens) : [] });
    return;
  }

  if (req.method === "POST") {
    if (!config.drivePassword) {
      throw httpError(503, "Drive password is not configured.", "drive_auth_not_configured");
    }

    const { password = "" } = await readJsonBody(req, config.maxUploadBytes);
    if (!constantTimeEqual(String(password), config.drivePassword)) {
      throw httpError(401, "Invalid drive password.", "unauthorized");
    }

    res.setHeader("set-cookie", buildDriveSessionCookie(signDriveSession(config)));
    sendJson(res, 200, { ok: true, roots: driveRoots(config.tokens) });
    return;
  }

  if (req.method === "DELETE") {
    res.setHeader("set-cookie", buildExpiredDriveSessionCookie());
    sendJson(res, 200, { ok: true });
    return;
  }

  sendJson(res, 405, { error: "method_not_allowed" });
}

async function routeDriveApi(req, res, config, url) {
  requireDriveSession(req, config);

  if (req.method === "GET" && url.pathname === "/drive/api/list") {
    const root = safeDavPath(url.searchParams.get("root") || "");
    requireRootToken(config.tokens, root, "read");
    const relativePath = safeDavPath(url.searchParams.get("path") || "", { allowEmpty: true });
    const entries = await config.webdav.list(joinDavPath(root, relativePath));
    sendJson(res, 200, { root, path: relativePath, entries });
    return;
  }

  if (req.method === "POST" && url.pathname === "/drive/api/directory") {
    const { root = "", path = "" } = await readJsonBody(req, config.maxUploadBytes);
    const safeRoot = safeDavPath(root);
    requireRootToken(config.tokens, safeRoot, "write");
    const relativePath = safeDavPath(path);
    await config.webdav.ensureDirectory(joinDavPath(safeRoot, relativePath));
    sendJson(res, 201, { root: safeRoot, path: relativePath, created: true });
    return;
  }

  if (req.method === "POST" && url.pathname === "/drive/api/upload") {
    await routeDriveUpload(req, res, config);
    return;
  }

  sendJson(res, 404, { error: "not_found" });
}

async function routeDriveUpload(req, res, config) {
  const form = parseMultipartForm(
    req.headers["content-type"] || "",
    await readRawBody(req, config.maxUploadBytes),
  );
  const root = safeDavPath(requiredFormField(form, "root"));
  requireRootToken(config.tokens, root, "write");

  const file = form.files.file;
  if (!file) {
    throw httpError(400, "Multipart field 'file' is required.", "bad_request");
  }

  const targetDirectory = safeDavPath(form.fields.targetDirectory || form.fields.documentPath || "", { allowEmpty: true });
  const filename = safeFilename(file.filename || "upload.bin");
  const relativePath = joinDavPath(targetDirectory, filename);
  const result = await config.webdav.upload(joinDavPath(root, relativePath), file.content, file.contentType || "application/octet-stream");

  sendJson(res, 201, {
    root,
    path: relativePath,
    downloadUrl: `/files/download?root=${encodeURIComponent(root)}&path=${encodeURIComponent(relativePath)}`,
    size: file.content.length,
    mimeType: file.contentType || "application/octet-stream",
    ...(result.etag ? { etag: result.etag } : {}),
  });
}

async function routeCompatibleUpload(req, res, config) {
  const form = parseMultipartForm(
    req.headers["content-type"] || "",
    await readRawBody(req, config.maxUploadBytes),
  );
  const root = safeDavPath(requiredFormField(form, "root"));
  const token = requireGatewayToken(req, config.tokens);
  requirePermission(token, "write");
  if (token.root !== root) {
    throw httpError(403, `Token is not scoped to ${root}.`, "forbidden");
  }

  const file = form.files.file;
  if (!file) {
    throw httpError(400, "Multipart field 'file' is required.", "bad_request");
  }

  const targetDirectory = safeDavPath(form.fields.targetDirectory || form.fields.documentPath || "", { allowEmpty: true });
  const filename = safeFilename(file.filename || "upload.bin");
  const relativePath = joinDavPath(targetDirectory, filename);
  const result = await config.webdav.upload(joinDavPath(root, relativePath), file.content, file.contentType || "application/octet-stream");

  sendJson(res, 201, {
    root,
    path: relativePath,
    downloadUrl: `/files/download?root=${encodeURIComponent(root)}&path=${encodeURIComponent(relativePath)}`,
    size: file.content.length,
    mimeType: file.contentType || "application/octet-stream",
    ...(result.etag ? { etag: result.etag } : {}),
  });
}

async function routeCompatibleDownload(req, res, config, url) {
  const root = safeDavPath(url.searchParams.get("root") || "");
  resolveRootAccess(req, config.tokens, root, "read");
  const relativePath = safeDavPath(url.searchParams.get("path") || "");
  const result = await config.webdav.download(joinDavPath(root, relativePath));
  const body = Buffer.from(await result.arrayBuffer());

  res.writeHead(200, {
    "content-type": result.contentType,
    "content-length": body.length,
  });
  res.end(body);
}

export async function loadTokensFile(path) {
  const content = await readFile(path, "utf8");
  return normalizeTokens(JSON.parse(content.replace(/^\uFEFF/, "")));
}

export function normalizeTokens(raw) {
  const source = raw && Object.keys(raw).length ? raw : defaultServiceTokens;
  const result = {};

  for (const [plainToken, value] of Object.entries(source)) {
    if (!plainToken || plainToken.length < 16) {
      throw new Error("Gateway tokens must be at least 16 characters.");
    }

    result[plainToken] = {
      name: String(value.name || "integration"),
      root: safeDavPath(value.root || "", { allowEmpty: false }),
      permissions: normalizePermissions(value.permissions),
    };
  }

  return result;
}

export async function loadGatewayTokensFromEnvironment() {
  const file = process.env.NAS_GATEWAY_TOKENS_FILE;
  if (file) return loadTokensFile(file);
  return normalizeTokens(loadTokensFromEnv());
}

function loadTokensFromEnv() {
  if (process.env.NAS_GATEWAY_TOKENS_JSON) {
    return JSON.parse(process.env.NAS_GATEWAY_TOKENS_JSON);
  }
  return defaultServiceTokens;
}

function requireGatewayToken(req, tokens) {
  const auth = req.headers.authorization || "";
  const plainToken = auth.startsWith("Bearer ") ? auth.slice("Bearer ".length).trim() : "";
  const token = tokens[plainToken];
  if (!token) {
    throw httpError(401, "Missing or invalid gateway token.", "unauthorized");
  }
  return token;
}

function resolveRootAccess(req, tokens, root, permission) {
  const auth = req.headers.authorization || "";
  if (auth.startsWith("Bearer ")) {
    const token = requireGatewayToken(req, tokens);
    requirePermission(token, permission);
    if (token.root !== root) {
      throw httpError(403, `Token is not scoped to ${root}.`, "forbidden");
    }
    return token;
  }

  const matchingToken = Object.values(tokens).find((token) => token.root === root && token.permissions.includes(permission));
  if (!matchingToken) {
    throw httpError(403, `Root ${root} is not configured for ${permission}.`, "forbidden");
  }
  return matchingToken;
}

function requireRootToken(tokens, root, permission) {
  const token = Object.values(tokens).find((candidate) => candidate.root === root && candidate.permissions.includes(permission));
  if (!token) {
    throw httpError(403, `Root ${root} is not configured for ${permission}.`, "forbidden");
  }
  return token;
}

function requirePermission(token, permission) {
  if (!token.permissions.includes(permission)) {
    throw httpError(403, `Token does not allow ${permission}.`, "forbidden");
  }
}

function driveRoots(tokens) {
  return [...new Set(Object.values(tokens)
    .filter((token) => token.permissions.includes("read"))
    .map((token) => token.root))]
    .sort((left, right) => left.localeCompare(right));
}

function requireDriveSession(req, config) {
  if (!readDriveSession(req, config)) {
    throw httpError(401, "Drive login is required.", "unauthorized");
  }
}

function readDriveSession(req, config) {
  const value = parseCookie(req.headers.cookie || "")[driveSessionCookieName];
  if (!value) return null;

  const [encodedPayload, signature] = value.split(".");
  if (!encodedPayload || !signature) return null;

  const expectedSignature = signValue(encodedPayload, config.driveSessionSecret);
  if (!constantTimeEqual(signature, expectedSignature)) return null;

  try {
    const payload = JSON.parse(Buffer.from(encodedPayload, "base64url").toString("utf8"));
    if (Number(payload.exp) < Date.now()) return null;
    return payload;
  } catch {
    return null;
  }
}

function signDriveSession(config) {
  const payload = {
    exp: Date.now() + driveSessionTtlMs,
  };
  const encodedPayload = Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
  return `${encodedPayload}.${signValue(encodedPayload, config.driveSessionSecret)}`;
}

function signValue(value, secret) {
  return createHmac("sha256", secret).update(value).digest("base64url");
}

function parseCookie(header) {
  const result = {};
  for (const part of String(header || "").split(";")) {
    const index = part.indexOf("=");
    if (index === -1) continue;
    const name = part.slice(0, index).trim();
    const value = part.slice(index + 1).trim();
    if (name) result[name] = value;
  }
  return result;
}

function buildDriveSessionCookie(value) {
  return [
    `${driveSessionCookieName}=${value}`,
    "Path=/",
    "HttpOnly",
    "SameSite=Lax",
    "Max-Age=43200",
  ].join("; ");
}

function buildExpiredDriveSessionCookie() {
  return [
    `${driveSessionCookieName}=`,
    "Path=/",
    "HttpOnly",
    "SameSite=Lax",
    "Max-Age=0",
  ].join("; ");
}

function constantTimeEqual(left, right) {
  const leftBuffer = Buffer.from(String(left));
  const rightBuffer = Buffer.from(String(right));
  if (leftBuffer.length !== rightBuffer.length) return false;
  return timingSafeEqual(leftBuffer, rightBuffer);
}

function tokenPath(token, relativePath) {
  return joinDavPath(token.root, relativePath || "");
}

function normalizePermissions(value) {
  const permissions = Array.isArray(value) ? value : ["read", "write"];
  const allowed = new Set(["read", "write", "delete"]);
  const result = [...new Set(permissions.map((item) => String(item).trim()))];
  if (result.length === 0 || result.some((item) => !allowed.has(item))) {
    throw new Error("Gateway token permissions must be read, write, or delete.");
  }
  return result;
}

async function readRawBody(req, maxBytes) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > maxBytes) {
      throw httpError(413, "Upload exceeds gateway max upload size.", "payload_too_large");
    }
    chunks.push(chunk);
  }
  if (total === 0) {
    throw httpError(400, "Upload body is required.", "bad_request");
  }
  return Buffer.concat(chunks);
}

async function readJsonBody(req, maxBytes) {
  const body = await readRawBody(req, maxBytes);
  try {
    return JSON.parse(body.toString("utf8"));
  } catch {
    throw httpError(400, "Request body must be valid JSON.", "bad_request");
  }
}

function parseMultipartForm(contentType, body) {
  const boundary = contentType.match(/boundary=(?:"([^"]+)"|([^;]+))/i)?.[1] || contentType.match(/boundary=(?:"([^"]+)"|([^;]+))/i)?.[2];
  if (!boundary) {
    throw httpError(400, "multipart/form-data boundary is required.", "bad_request");
  }

  const result = { fields: {}, files: {} };
  const raw = body.toString("latin1");
  const sections = raw.split(`--${boundary}`);

  for (let section of sections) {
    section = section.replace(/^\r?\n/, "");
    if (!section || section === "--" || section.startsWith("--")) continue;

    const headerEnd = section.indexOf("\r\n\r\n");
    if (headerEnd === -1) continue;

    const headerText = section.slice(0, headerEnd);
    let contentText = section.slice(headerEnd + 4);
    contentText = contentText.replace(/\r?\n$/, "");

    const disposition = headerText.match(/content-disposition:\s*form-data;([^\r\n]+)/i)?.[1] || "";
    const name = disposition.match(/name="([^"]+)"/i)?.[1];
    if (!name) continue;

    const filename = disposition.match(/filename="([^"]*)"/i)?.[1];
    const content = Buffer.from(contentText, "latin1");
    const contentTypeHeader = headerText.match(/content-type:\s*([^\r\n]+)/i)?.[1]?.trim();

    if (filename !== undefined) {
      result.files[name] = {
        filename,
        content,
        contentType: contentTypeHeader || "application/octet-stream",
      };
    } else {
      result.fields[name] = content.toString("utf8");
    }
  }

  return result;
}

function requiredFormField(form, name) {
  const value = form.fields[name];
  if (!value) {
    throw httpError(400, `Multipart field '${name}' is required.`, "bad_request");
  }
  return value;
}

function safeFilename(value) {
  const name = String(value || "").replaceAll("\\", "/").split("/").filter(Boolean).at(-1) || "";
  return safeDavPath(name);
}

function sendJson(res, status, data) {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(data, null, 2));
}

async function sendDriveUi(res) {
  const html = await readFile(new URL("../public/drive.html", import.meta.url), "utf8");
  res.writeHead(200, {
    "content-type": "text/html; charset=utf-8",
    "cache-control": "no-store",
  });
  res.end(html);
}

function setSecurityHeaders(res) {
  res.setHeader("x-content-type-options", "nosniff");
  res.setHeader("referrer-policy", "no-referrer");
}

function httpError(status, message, code) {
  const error = new Error(message);
  error.status = status;
  error.code = code;
  return error;
}
