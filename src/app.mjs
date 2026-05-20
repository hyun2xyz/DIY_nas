import http from "node:http";
import { createReadStream } from "node:fs";
import {
  mkdir,
  readFile,
  readdir,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { createHash, pbkdf2Sync, randomBytes, timingSafeEqual } from "node:crypto";
import { basename, dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = fileURLToPath(new URL("..", import.meta.url));
const publicDir = join(projectRoot, "public");
const defaultQuotaBytes = 50n * 1024n * 1024n * 1024n;

export function createPilotCloudServer(options = {}) {
  const config = {
    dataDir: options.dataDir || join(process.env.USERPROFILE || process.cwd(), "nas-pilot-data"),
    quotaBytes: BigInt(options.quotaBytes || process.env.NAS_PILOT_QUOTA_BYTES || defaultQuotaBytes),
    adminUsername: options.adminUsername || process.env.NAS_PILOT_ADMIN_USER || "admin",
    adminPassword: options.adminPassword || process.env.NAS_PILOT_ADMIN_PASSWORD || "",
  };

  const paths = {
    db: join(config.dataDir, "db"),
    files: join(config.dataDir, "files"),
    audit: join(config.dataDir, "audit"),
    bootstrapAdmin: join(config.dataDir, "bootstrap-admin.txt"),
  };

  const state = {
    initialized: false,
    sessions: new Map(),
  };

  return http.createServer(async (req, res) => {
    try {
      await ensureInitialized(config, paths, state);
      await route(req, res, config, paths, state);
    } catch (error) {
      if (Number(error.status) >= 500 || !error.status) {
        console.error(error);
      }

      sendJson(res, error.status || 500, {
        error: error.code || "internal_error",
        message: error.status ? error.message : "NAS pilot internal error",
      });
    }
  });
}

async function ensureInitialized(config, paths, state) {
  if (state.initialized) return;

  await mkdir(paths.db, { recursive: true });
  await mkdir(paths.files, { recursive: true });
  await mkdir(paths.audit, { recursive: true });

  const users = await readJsonFile(usersPath(paths), []);
  if (users.length === 0) {
    const password = config.adminPassword || randomBytes(18).toString("base64url");
    users.push({
      username: config.adminUsername,
      role: "admin",
      passwordHash: hashPassword(password),
      createdAt: new Date().toISOString(),
    });
    await writeJsonFile(usersPath(paths), users);

    if (!config.adminPassword) {
      await writeFile(
        paths.bootstrapAdmin,
        `username=${config.adminUsername}\npassword=${password}\n`,
        "utf8",
      );
    }
  }

  await writeJsonFile(tokensPath(paths), await readJsonFile(tokensPath(paths), []));
  state.initialized = true;
}

async function route(req, res, config, paths, state) {
  setSecurityHeaders(res);
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);

  if (req.method === "GET" && url.pathname === "/health") {
    sendJson(res, 200, {
      ok: true,
      quotaBytes: config.quotaBytes.toString(),
      dataDir: config.dataDir,
    });
    return;
  }

  if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/cloud")) {
    await serveStatic(res, "index.html");
    return;
  }

  if (req.method === "GET" && url.pathname.startsWith("/public/")) {
    await serveStatic(res, url.pathname.replace("/public/", ""));
    return;
  }

  if (req.method === "POST" && (url.pathname === "/api/login" || url.pathname === "/api/auth/login")) {
    const body = await readJson(req);
    const user = await findUser(paths, body.username);
    if (!user || !verifyPassword(body.password || "", user.passwordHash)) {
      throw httpError(401, "Invalid username or password", "unauthorized");
    }

    const sessionId = randomBytes(32).toString("base64url");
    state.sessions.set(sessionId, { username: user.username, role: user.role });
    await audit(paths, "login", { actor: user.username, role: user.role });
    res.setHeader("set-cookie", cookieHeader(sessionId));
    sendJson(res, 200, { user: publicUser(user) });
    return;
  }

  if (req.method === "POST" && (url.pathname === "/api/logout" || url.pathname === "/api/auth/logout")) {
    const sessionId = parseCookies(req).nas_pilot_session;
    if (sessionId) state.sessions.delete(sessionId);
    res.setHeader("set-cookie", "nas_pilot_session=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0");
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === "GET" && (url.pathname === "/api/me" || url.pathname === "/api/auth/me")) {
    const auth = requireSession(req, state);
    sendJson(res, 200, { user: auth });
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/files") {
    const auth = requireSession(req, state);
    await listFiles(res, paths, auth.username, url.searchParams.get("path") || "");
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/files/upload") {
    const auth = requireSession(req, state);
    const body = await readJson(req);
    await uploadFile(res, paths, config, auth.username, body);
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/files/download") {
    const auth = requireSession(req, state);
    await downloadFile(res, paths, auth.username, url.searchParams.get("path") || "");
    return;
  }

  if (req.method === "DELETE" && url.pathname === "/api/files") {
    const auth = requireSession(req, state);
    await deleteFile(res, paths, auth.username, url.searchParams.get("path") || "");
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/admin/users") {
    requireAdmin(req, state);
    const users = await readJsonFile(usersPath(paths), []);
    sendJson(res, 200, { users: users.map(publicUser) });
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/admin/users") {
    requireAdmin(req, state);
    const body = await readJson(req);
    const user = await createUser(paths, body);
    await audit(paths, "user.create", { actor: requireAdmin(req, state).username, username: user.username, role: user.role });
    sendJson(res, 201, { user: publicUser(user) });
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/admin/tokens") {
    requireAdmin(req, state);
    const body = await readJson(req);
    const token = await createApiToken(paths, body);
    await audit(paths, "token.create", { actor: requireAdmin(req, state).username, owner: token.owner, scopes: token.scopes });
    sendJson(res, 201, token);
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/integration/files") {
    const auth = await requireApiToken(req, paths, "files:read");
    await listFiles(res, paths, auth.owner, url.searchParams.get("path") || "");
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/integration/upload") {
    const auth = await requireApiToken(req, paths, "files:write");
    const body = await readJson(req);
    await uploadFile(res, paths, config, auth.owner, body);
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/integration/download") {
    const auth = await requireApiToken(req, paths, "files:read");
    await downloadFile(res, paths, auth.owner, url.searchParams.get("path") || "");
    return;
  }

  sendJson(res, 404, { error: "not_found" });
}

async function listFiles(res, paths, username, relativePath) {
  const dir = userPath(paths, username, relativePath);
  await mkdir(dir, { recursive: true });
  const entries = await readdir(dir, { withFileTypes: true });
  const result = [];

  for (const entry of entries) {
    const entryPath = join(dir, entry.name);
    const info = await stat(entryPath);
    result.push({
      name: entry.name,
      type: entry.isDirectory() ? "directory" : "file",
      size: entry.isDirectory() ? 0 : info.size,
      modifiedAt: info.mtime.toISOString(),
    });
  }

  result.sort((left, right) => left.name.localeCompare(right.name));
  sendJson(res, 200, { entries: result });
}

async function uploadFile(res, paths, config, username, body) {
  const directory = userPath(paths, username, body.path || "");
  const filename = safeFilename(body.filename);
  const content = decodeBase64(body.contentBase64);
  const currentSize = await directorySize(userRoot(paths, username));

  if (currentSize + BigInt(content.length) > config.quotaBytes) {
    throw httpError(413, "Storage quota exceeded", "quota_exceeded");
  }

  await mkdir(directory, { recursive: true });
  const filePath = safeJoin(directory, filename, directory);
  await writeFile(filePath, content);
  await audit(paths, "file.upload", { actor: username, path: joinSafeWebPath(body.path || "", filename), size: content.length });

  sendJson(res, 201, {
    file: {
      name: filename,
      path: joinSafeWebPath(body.path || "", filename),
      size: content.length,
    },
  });
}

async function downloadFile(res, paths, username, relativePath) {
  const filePath = userPath(paths, username, relativePath);
  const info = await stat(filePath).catch(() => null);
  if (!info || !info.isFile()) {
    throw httpError(404, "File not found", "not_found");
  }

  res.writeHead(200, {
    "content-type": "application/octet-stream",
    "content-length": info.size,
    "content-disposition": `attachment; filename="${basename(filePath).replaceAll('"', "")}"`,
  });
  createReadStream(filePath).pipe(res);
}

async function deleteFile(res, paths, username, relativePath) {
  const target = userPath(paths, username, relativePath);
  if (target === userRoot(paths, username)) {
    throw httpError(400, "Refusing to delete user root", "bad_request");
  }

  await rm(target, { recursive: true, force: true });
  await audit(paths, "file.delete", { actor: username, path: safeRelativePath(relativePath) });
  sendJson(res, 200, { ok: true });
}

async function createUser(paths, body) {
  const username = safeUsername(body.username);
  const role = body.role === "admin" ? "admin" : "user";
  if (!body.password || String(body.password).length < 8) {
    throw httpError(400, "Password must be at least 8 characters", "bad_request");
  }

  const users = await readJsonFile(usersPath(paths), []);
  if (users.some((user) => user.username === username)) {
    throw httpError(409, "Username already exists", "conflict");
  }

  const user = {
    username,
    role,
    passwordHash: hashPassword(String(body.password)),
    createdAt: new Date().toISOString(),
  };
  users.push(user);
  await writeJsonFile(usersPath(paths), users);
  await mkdir(userRoot(paths, username), { recursive: true });
  return user;
}

async function createApiToken(paths, body) {
  const owner = safeUsername(body.owner || "admin");
  const user = await findUser(paths, owner);
  if (!user) {
    throw httpError(400, "Token owner does not exist", "bad_request");
  }

  const plainToken = `npc_${randomBytes(32).toString("base64url")}`;
  const scopes = normalizeScopes(body.scopes);
  const tokens = await readJsonFile(tokensPath(paths), []);
  tokens.push({
    id: randomBytes(8).toString("hex"),
    name: String(body.name || "integration"),
    owner,
    scopes,
    tokenHash: sha256(plainToken),
    createdAt: new Date().toISOString(),
  });
  await writeJsonFile(tokensPath(paths), tokens);
  return { token: plainToken, owner, scopes };
}

async function requireApiToken(req, paths, requiredScope) {
  const auth = req.headers.authorization || "";
  const token = auth.startsWith("Bearer ") ? auth.slice("Bearer ".length) : "";
  if (!token) {
    throw httpError(401, "Missing bearer token", "unauthorized");
  }

  const tokenHash = sha256(token);
  const tokens = await readJsonFile(tokensPath(paths), []);
  const match = tokens.find((entry) => safeEqual(entry.tokenHash, tokenHash));
  if (!match) {
    throw httpError(401, "Invalid bearer token", "unauthorized");
  }

  if (requiredScope && !Array.isArray(match.scopes) || (requiredScope && !match.scopes.includes(requiredScope))) {
    throw httpError(403, "API token scope is not allowed for this operation", "forbidden");
  }

  return { owner: match.owner, scopes: match.scopes || [] };
}

function requireSession(req, state) {
  const sessionId = parseCookies(req).nas_pilot_session;
  const session = sessionId ? state.sessions.get(sessionId) : null;
  if (!session) {
    throw httpError(401, "Login required", "unauthorized");
  }

  return session;
}

function requireAdmin(req, state) {
  const session = requireSession(req, state);
  if (session.role !== "admin") {
    throw httpError(403, "Admin role required", "forbidden");
  }

  return session;
}

async function findUser(paths, username) {
  const users = await readJsonFile(usersPath(paths), []);
  return users.find((user) => user.username === username);
}

function publicUser(user) {
  return {
    username: user.username,
    role: user.role,
    createdAt: user.createdAt,
  };
}

function hashPassword(password) {
  const salt = randomBytes(16).toString("hex");
  const digest = pbkdf2Sync(password, salt, 210000, 32, "sha256").toString("hex");
  return `pbkdf2_sha256$${salt}$${digest}`;
}

function verifyPassword(password, stored) {
  const [algorithm, salt, expected] = String(stored || "").split("$");
  if (algorithm !== "pbkdf2_sha256" || !salt || !expected) return false;
  const actual = pbkdf2Sync(String(password), salt, 210000, 32, "sha256").toString("hex");
  return safeEqual(actual, expected);
}

function sha256(value) {
  return createHash("sha256").update(String(value)).digest("hex");
}

function safeEqual(left, right) {
  const leftBuffer = Buffer.from(String(left || ""));
  const rightBuffer = Buffer.from(String(right || ""));
  if (leftBuffer.length !== rightBuffer.length) return false;
  return timingSafeEqual(leftBuffer, rightBuffer);
}

function safeUsername(value) {
  const username = String(value || "").trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9_-]{2,31}$/.test(username)) {
    throw httpError(400, "Username must be 3-32 lowercase letters, numbers, underscores, or hyphens", "bad_request");
  }

  return username;
}

function safeFilename(value) {
  const filename = basename(String(value || "").trim());
  const stem = filename.split(".")[0].toUpperCase();
  const reserved = new Set(["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]);
  if (
    !filename ||
    filename === "." ||
    filename === ".." ||
    /[<>:"|?*\x00-\x1f]/.test(filename) ||
    filename.endsWith(".") ||
    filename.endsWith(" ") ||
    reserved.has(stem)
  ) {
    throw httpError(400, "Valid filename is required", "bad_request");
  }

  return filename;
}

function normalizeScopes(value) {
  const scopes = Array.isArray(value) && value.length > 0 ? value : ["files:read", "files:write"];
  const allowed = new Set(["files:read", "files:write"]);
  const result = [...new Set(scopes.map((scope) => String(scope).trim()))];
  if (result.some((scope) => !allowed.has(scope))) {
    throw httpError(400, "Unsupported API token scope", "bad_request");
  }
  return result;
}

function userRoot(paths, username) {
  return join(paths.files, safeUsername(username));
}

function userPath(paths, username, relativePath) {
  return safeJoin(userRoot(paths, username), safeRelativePath(relativePath), userRoot(paths, username));
}

function safeRelativePath(value) {
  const text = String(value || "").replaceAll("\\", "/").trim();
  if (!text) return "";
  if (text.startsWith("/") || text.split("/").some((part) => part === "..")) {
    throw httpError(400, "Invalid path", "bad_request");
  }

  return text
    .split("/")
    .filter(Boolean)
    .join("/");
}

function safeJoin(root, relativePath, allowedRoot = root) {
  const resolvedRoot = resolve(allowedRoot);
  const resolved = resolve(root, relativePath);
  if (resolved !== resolvedRoot && !resolved.startsWith(`${resolvedRoot}\\`) && !resolved.startsWith(`${resolvedRoot}/`)) {
    throw httpError(400, "Invalid path", "bad_request");
  }

  return resolved;
}

function joinSafeWebPath(parent, filename) {
  const parts = [safeRelativePath(parent), safeFilename(filename)].filter(Boolean);
  return parts.join("/");
}

function decodeBase64(value) {
  if (typeof value !== "string" || !value) {
    throw httpError(400, "contentBase64 is required", "bad_request");
  }

  return Buffer.from(value, "base64");
}

async function directorySize(path) {
  const info = await stat(path).catch(() => null);
  if (!info) return 0n;
  if (info.isFile()) return BigInt(info.size);
  if (!info.isDirectory()) return 0n;

  let total = 0n;
  for (const entry of await readdir(path, { withFileTypes: true })) {
    total += await directorySize(join(path, entry.name));
  }
  return total;
}

async function serveStatic(res, relativePath) {
  const filePath = safeJoin(publicDir, safeRelativePath(relativePath), publicDir);
  const content = await readFile(filePath);
  res.writeHead(200, { "content-type": mimeType(extname(filePath)) });
  res.end(content);
}

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const raw = Buffer.concat(chunks).toString("utf8");

  try {
    return raw ? JSON.parse(raw) : {};
  } catch {
    throw httpError(400, "Invalid JSON request body", "bad_request");
  }
}

async function readJsonFile(path, fallback) {
  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return fallback;
    throw error;
  }
}

async function writeJsonFile(path, data) {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(data, null, 2)}\n`, "utf8");
}

async function audit(paths, event, data) {
  await mkdir(paths.audit, { recursive: true });
  const safeData = JSON.parse(JSON.stringify(data, (key, value) => {
    if (key.toLowerCase().includes("token")) return "[redacted]";
    return value;
  }));
  const line = JSON.stringify({
    at: new Date().toISOString(),
    event,
    ...safeData,
  });
  await writeFile(join(paths.audit, "events.ndjson"), `${line}\n`, { encoding: "utf8", flag: "a" });
}

function usersPath(paths) {
  return join(paths.db, "users.json");
}

function tokensPath(paths) {
  return join(paths.db, "tokens.json");
}

function parseCookies(req) {
  const result = {};
  for (const chunk of String(req.headers.cookie || "").split(";")) {
    const separator = chunk.indexOf("=");
    if (separator === -1) continue;
    result[chunk.slice(0, separator).trim()] = decodeURIComponent(chunk.slice(separator + 1).trim());
  }
  return result;
}

function cookieHeader(sessionId) {
  return `nas_pilot_session=${encodeURIComponent(sessionId)}; HttpOnly; SameSite=Lax; Path=/; Max-Age=28800`;
}

function sendJson(res, status, data) {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(data, null, 2));
}

function setSecurityHeaders(res) {
  res.setHeader("x-content-type-options", "nosniff");
  res.setHeader("referrer-policy", "no-referrer");
}

function mimeType(ext) {
  return {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
  }[ext] || "application/octet-stream";
}

function httpError(status, message, code) {
  const error = new Error(message);
  error.status = status;
  error.code = code;
  return error;
}
