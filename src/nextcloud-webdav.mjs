import { Buffer } from "node:buffer";

export function createNextcloudWebDavClient(options = {}) {
  const baseUrl = normalizeBaseUrl(required(options.baseUrl, "baseUrl"));
  const username = required(options.username, "username");
  const appPassword = required(options.appPassword, "appPassword");
  const fetchImpl = options.fetch || globalThis.fetch;

  if (typeof fetchImpl !== "function") {
    throw new Error("A fetch implementation is required.");
  }

  const authHeader = `Basic ${Buffer.from(`${username}:${appPassword}`).toString("base64")}`;

  async function request(method, path, requestOptions = {}) {
    const response = await fetchImpl(davUrl(baseUrl, username, path), {
      method,
      headers: {
        authorization: authHeader,
        ...requestOptions.headers,
      },
      body: requestOptions.body,
    });

    if (requestOptions.allowStatuses?.includes(response.status)) {
      return response;
    }

    if (!response.ok && response.status !== 207) {
      const text = await response.text().catch(() => "");
      const error = new Error(`Nextcloud WebDAV ${method} ${path} failed with HTTP ${response.status}${text ? `: ${text.slice(0, 300)}` : ""}`);
      error.status = response.status;
      throw error;
    }

    return response;
  }

  return {
    async list(path = "") {
      const safePath = safeDavPath(path, { allowEmpty: true });
      const response = await request("PROPFIND", safePath, {
        headers: { depth: "1" },
      });
      const xml = await response.text();
      return parseWebDavList(xml, safePath);
    },

    async ensureDirectory(path = "") {
      const safePath = safeDavPath(path, { allowEmpty: true });
      if (!safePath) return;

      let current = "";
      for (const part of safePath.split("/").filter(Boolean)) {
        current = current ? `${current}/${part}` : part;
        await request("MKCOL", current, {
          allowStatuses: [201, 405],
        });
      }
    },

    async upload(path, content, contentType = "application/octet-stream") {
      const safePath = safeDavPath(path);
      const parent = parentPath(safePath);
      await this.ensureDirectory(parent);
      const response = await request("PUT", safePath, {
        headers: { "content-type": contentType },
        body: content,
        allowStatuses: [200, 201, 204],
      });
      return { path: safePath, status: response.status, etag: cleanEtag(response.headers.get("etag")) };
    },

    async download(path) {
      const safePath = safeDavPath(path);
      const response = await request("GET", safePath);
      return {
        path: safePath,
        status: response.status,
        contentType: response.headers.get("content-type") || "application/octet-stream",
        contentLength: Number(response.headers.get("content-length") || 0),
        body: response.body,
        arrayBuffer: () => response.arrayBuffer(),
      };
    },

    async delete(path) {
      const safePath = safeDavPath(path);
      const response = await request("DELETE", safePath, {
        allowStatuses: [200, 202, 204, 404],
      });
      return { path: safePath, status: response.status, deleted: response.status !== 404 };
    },
  };
}

export function davUrl(baseUrl, username, path = "") {
  const encodedUser = encodeURIComponent(username);
  const encodedPath = safeDavPath(path, { allowEmpty: true })
    .split("/")
    .filter(Boolean)
    .map(encodeURIComponent)
    .join("/");
  const suffix = encodedPath ? `/${encodedPath}` : "";
  return `${baseUrl}/remote.php/dav/files/${encodedUser}${suffix}`;
}

export function safeDavPath(value, options = {}) {
  const text = String(value || "").replaceAll("\\", "/").trim();
  if (!text) {
    if (options.allowEmpty) return "";
    throw pathError("Path is required.");
  }
  if (text.startsWith("/") || text.includes("\0")) {
    throw pathError("Absolute or invalid paths are not allowed.");
  }

  const parts = text.split("/").filter(Boolean);
  if (parts.some((part) => part === "." || part === "..")) {
    throw pathError("Path traversal is not allowed.");
  }

  return parts.join("/");
}

export function joinDavPath(root, path = "") {
  const safeRoot = safeDavPath(root, { allowEmpty: true });
  const safePath = safeDavPath(path, { allowEmpty: true });
  return [safeRoot, safePath].filter(Boolean).join("/");
}

export function parseWebDavList(xml, requestedPath = "") {
  const responses = [...xml.matchAll(/<[^:>]*:?response\b[\s\S]*?<\/[^:>]*:?response>/gi)].map((match) => match[0]);
  const requested = normalizeComparablePath(requestedPath);
  const entries = [];

  for (const response of responses) {
    const href = decodeXml(extractFirst(response, "href"));
    if (!href) continue;

    const name = decodeURIComponent(href.replace(/\/$/, "").split("/").pop() || "");
    const comparable = normalizeComparablePath(name);
    if (!name || comparable === requested || href.endsWith(`/${requestedPath}/`)) continue;

    const contentLength = Number(decodeXml(extractFirst(response, "getcontentlength")) || 0);
    const modifiedAt = decodeXml(extractFirst(response, "getlastmodified")) || null;
    const isDirectory = /<[^:>]*:?collection\s*\/?>/i.test(response);

    entries.push({
      name,
      type: isDirectory ? "directory" : "file",
      size: isDirectory ? 0 : contentLength,
      modifiedAt,
    });
  }

  entries.sort((left, right) => left.name.localeCompare(right.name));
  return entries;
}

function parentPath(path) {
  const parts = safeDavPath(path).split("/");
  parts.pop();
  return parts.join("/");
}

function extractFirst(xml, localName) {
  const pattern = new RegExp(`<[^:>]*:?${localName}\\b[^>]*>([\\s\\S]*?)<\\/[^:>]*:?${localName}>`, "i");
  return xml.match(pattern)?.[1] || "";
}

function decodeXml(value) {
  return String(value || "")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&apos;", "'")
    .replaceAll("&amp;", "&")
    .trim();
}

function normalizeBaseUrl(value) {
  return String(value || "").replace(/\/+$/, "");
}

function normalizeComparablePath(value) {
  return String(value || "").replace(/^\/+|\/+$/g, "");
}

function required(value, name) {
  if (!value) throw new Error(`Nextcloud WebDAV ${name} is required.`);
  return value;
}

function cleanEtag(value) {
  return value ? String(value).replace(/^W\//, "").replace(/^"|"$/g, "") : undefined;
}

function pathError(message) {
  const error = new Error(message);
  error.code = "bad_path";
  error.status = 400;
  return error;
}
