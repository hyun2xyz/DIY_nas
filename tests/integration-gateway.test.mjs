import { after, before, describe, it } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { createIntegrationGatewayServer } from "../src/integration-gateway.mjs";

let server;
let baseUrl;
let calls;

const lmsToken = "lms-test-token-0000000000000001";
const publishReadOnlyToken = "publish-read-token-000000000001";
const wikiToken = "wiki-test-token-0000000000000001";

before(async () => {
  calls = [];
  const webdavClient = createMockWebDavClient(calls);
  server = createIntegrationGatewayServer({
    webdavClient,
    tokens: {
      [lmsToken]: {
        name: "Example LMS integration",
        root: "LMS",
        permissions: ["read", "write", "delete"],
      },
      [publishReadOnlyToken]: {
        name: "Publishing read only",
        root: "Publishing",
        permissions: ["read"],
      },
      [wikiToken]: {
        name: "Wiki automation",
        root: "Wiki",
        permissions: ["read", "write"],
      },
    },
    maxUploadBytes: 1024 * 1024,
    drivePassword: "drive-password-for-tests",
    driveSessionSecret: "drive-session-secret-for-tests-000000000000",
  });

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  baseUrl = `http://127.0.0.1:${port}`;
});

after(async () => {
  await new Promise((resolve) => server.close(resolve));
});

describe("Nextcloud integration gateway", () => {
  it("reports configured integrations without exposing token values", async () => {
    const response = await getJson("/health");

    assert.equal(response.status, 200);
    assert.equal(response.body.ok, true);
    assert.equal(response.body.integrations[0].name, "Example LMS integration");
    assert.doesNotMatch(JSON.stringify(response.body), /lms-test-token/);
  });

  it("serves the Drive browser UI", async () => {
    const response = await fetch(`${baseUrl}/drive`);
    const html = await response.text();

    assert.equal(response.status, 200);
    assert.match(response.headers.get("content-type"), /text\/html/);
    assert.match(html, /NAS Drive/);
    assert.match(html, /Drive password/);
    assert.doesNotMatch(html, /Gateway token/);
  });

  it("creates an http-only drive session with the drive password", async () => {
    const rejected = await postJson("/drive/session", { password: "wrong" });
    assert.equal(rejected.status, 401);

    const response = await fetch(`${baseUrl}/drive/session`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ password: "drive-password-for-tests" }),
    });
    const json = await response.json();
    const cookie = response.headers.get("set-cookie");

    assert.equal(response.status, 200);
    assert.equal(json.ok, true);
    assert.deepEqual(json.roots, ["LMS", "Publishing", "Wiki"]);
    assert.match(cookie, /nas_drive_session=/);
    assert.match(cookie, /HttpOnly/);
    assert.match(cookie, /SameSite=Lax/);
  });

  it("lists files through a drive session without a bearer token", async () => {
    const cookie = await createDriveSessionCookie();
    const response = await getJson("/drive/api/list?root=LMS&path=lessons", { cookie });

    assert.equal(response.status, 200);
    assert.equal(response.body.root, "LMS");
    assert.equal(response.body.path, "lessons");
    assert.deepEqual(response.body.entries, [
      { name: "intro.txt", type: "file", size: 9, modifiedAt: "mock" },
    ]);
    assert.deepEqual(calls.at(-1), { method: "list", path: "LMS/lessons" });
  });

  it("uploads files through a drive session without exposing a gateway token", async () => {
    const cookie = await createDriveSessionCookie();
    const body = new FormData();
    body.set("root", "Wiki");
    body.set("targetDirectory", "SmokeTests/Drive");
    body.set("file", new Blob(["hello from drive"], { type: "text/plain" }), "drive.txt");

    const response = await fetch(`${baseUrl}/drive/api/upload`, {
      method: "POST",
      headers: { cookie },
      body,
    });
    const json = await response.json();

    assert.equal(response.status, 201);
    assert.deepEqual(json, {
      root: "Wiki",
      path: "SmokeTests/Drive/drive.txt",
      downloadUrl: "/files/download?root=Wiki&path=SmokeTests%2FDrive%2Fdrive.txt",
      size: 16,
      mimeType: "text/plain",
      etag: "mock-etag",
    });
    assert.deepEqual(calls.at(-1), {
      method: "upload",
      path: "Wiki/SmokeTests/Drive/drive.txt",
      content: "hello from drive",
      contentType: "text/plain",
    });
  });

  it("requires a bearer token for cloud routes", async () => {
    const response = await getJson("/api/cloud/list");
    assert.equal(response.status, 401);
  });

  it("uploads binary content under the token service root", async () => {
    const response = await putBinary(
      "/api/cloud/file?path=lessons/intro.txt",
      "hello lms",
      { bearer: lmsToken, contentType: "text/plain" },
    );

    assert.equal(response.status, 201);
    assert.equal(response.body.root, "LMS");
    assert.equal(response.body.path, "lessons/intro.txt");
    assert.deepEqual(calls.at(-1), {
      method: "upload",
      path: "LMS/lessons/intro.txt",
      content: "hello lms",
      contentType: "text/plain",
    });
  });

  it("lists files through the mapped service root", async () => {
    const response = await getJson("/api/cloud/list?path=lessons", { bearer: lmsToken });

    assert.equal(response.status, 200);
    assert.equal(response.body.root, "LMS");
    assert.equal(response.body.path, "lessons");
    assert.deepEqual(response.body.entries, [
      { name: "intro.txt", type: "file", size: 9, modifiedAt: "mock" },
    ]);
    assert.deepEqual(calls.at(-1), { method: "list", path: "LMS/lessons" });
  });

  it("creates directories through the mapped service root", async () => {
    const response = await postJson(
      "/api/cloud/directory",
      { path: "lessons/new-folder" },
      { bearer: lmsToken },
    );

    assert.equal(response.status, 201);
    assert.deepEqual(response.body, {
      root: "LMS",
      path: "lessons/new-folder",
      created: true,
    });
    assert.deepEqual(calls.at(-1), { method: "ensureDirectory", path: "LMS/lessons/new-folder" });
  });

  it("downloads binary content from the mapped service root", async () => {
    const response = await fetch(`${baseUrl}/api/cloud/file?path=lessons/intro.txt`, {
      headers: { authorization: `Bearer ${lmsToken}` },
    });

    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "text/plain");
    assert.equal(await response.text(), "hello lms");
    assert.deepEqual(calls.at(-1), { method: "download", path: "LMS/lessons/intro.txt" });
  });

  it("blocks writes for read-only tokens", async () => {
    const response = await putBinary(
      "/api/cloud/file?path=draft.txt",
      "draft",
      { bearer: publishReadOnlyToken },
    );

    assert.equal(response.status, 403);
  });

  it("blocks path traversal before WebDAV is called", async () => {
    const beforeCount = calls.length;
    const response = await getJson("/api/cloud/list?path=../private", { bearer: lmsToken });

    assert.equal(response.status, 400);
    assert.equal(calls.length, beforeCount);
  });

  it("deletes only when the token has delete permission", async () => {
    const response = await deleteJson("/api/cloud/file?path=lessons/intro.txt", { bearer: lmsToken });

    assert.equal(response.status, 200);
    assert.equal(response.body.deleted, true);
    assert.deepEqual(calls.at(-1), { method: "delete", path: "LMS/lessons/intro.txt" });
  });

  it("accepts Mac-compatible multipart uploads and returns relative file metadata", async () => {
    const body = new FormData();
    body.set("root", "Wiki");
    body.set("documentPath", "SmokeTests/Mac");
    body.set("targetDirectory", "SmokeTests/Mac/attachments");
    body.set("metadata", JSON.stringify({ source: "mac-codex-smoke" }));
    body.set("file", new Blob(["hello from gateway"], { type: "text/plain" }), "test.txt");

    const response = await fetch(`${baseUrl}/files/upload`, {
      method: "POST",
      headers: { authorization: `Bearer ${wikiToken}` },
      body,
    });
    const json = await response.json();

    assert.equal(response.status, 201);
    assert.deepEqual(json, {
      root: "Wiki",
      path: "SmokeTests/Mac/attachments/test.txt",
      downloadUrl: "/files/download?root=Wiki&path=SmokeTests%2FMac%2Fattachments%2Ftest.txt",
      size: 18,
      mimeType: "text/plain",
      etag: "mock-etag",
    });
    assert.deepEqual(calls.at(-1), {
      method: "upload",
      path: "Wiki/SmokeTests/Mac/attachments/test.txt",
      content: "hello from gateway",
      contentType: "text/plain",
    });
  });

  it("requires a write token for Mac-compatible uploads", async () => {
    const body = new FormData();
    body.set("root", "Wiki");
    body.set("targetDirectory", "SmokeTests/Mac/attachments");
    body.set("file", new Blob(["blocked"], { type: "text/plain" }), "blocked.txt");

    const response = await fetch(`${baseUrl}/files/upload`, {
      method: "POST",
      body,
    });
    const json = await response.json();

    assert.equal(response.status, 401);
    assert.equal(json.error, "unauthorized");
  });

  it("downloads Mac-compatible files by root and relative path", async () => {
    const response = await fetch(`${baseUrl}/files/download?root=Wiki&path=SmokeTests/Mac/attachments/test.txt`);

    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "text/plain");
    assert.equal(await response.text(), "hello from gateway");
    assert.deepEqual(calls.at(-1), { method: "download", path: "Wiki/SmokeTests/Mac/attachments/test.txt" });
  });
});

function createMockWebDavClient(log) {
  const files = new Map();
  files.set("LMS/lessons/intro.txt", Buffer.from("hello lms"));

  return {
    async list(path) {
      log.push({ method: "list", path });
      const prefix = path ? `${path.replace(/\/$/, "")}/` : "";
      return [...files.entries()]
        .filter(([key]) => key.startsWith(prefix))
        .map(([key, value]) => ({
          name: key.slice(prefix.length).split("/")[0],
          type: "file",
          size: value.length,
          modifiedAt: "mock",
        }));
    },

    async upload(path, content, contentType) {
      const buffer = Buffer.from(content);
      files.set(path, buffer);
      log.push({ method: "upload", path, content: buffer.toString("utf8"), contentType });
      return { path, status: 201, etag: "mock-etag" };
    },

    async ensureDirectory(path) {
      log.push({ method: "ensureDirectory", path });
    },

    async download(path) {
      log.push({ method: "download", path });
      const buffer = files.get(path);
      if (!buffer) {
        const error = new Error("not found");
        error.status = 404;
        throw error;
      }
      return {
        path,
        contentType: "text/plain",
        contentLength: buffer.length,
        arrayBuffer: async () => buffer,
      };
    },

    async delete(path) {
      log.push({ method: "delete", path });
      const deleted = files.delete(path);
      return { path, status: deleted ? 204 : 404, deleted };
    },
  };
}

async function getJson(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    headers: requestHeaders(options),
  });
  return parseJsonResponse(response);
}

async function putBinary(path, body, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method: "PUT",
    headers: {
      "content-type": options.contentType || "application/octet-stream",
      ...requestHeaders(options),
    },
    body,
  });
  return parseJsonResponse(response);
}

async function postJson(path, body, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...requestHeaders(options),
    },
    body: JSON.stringify(body),
  });
  return parseJsonResponse(response);
}

async function deleteJson(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method: "DELETE",
    headers: requestHeaders(options),
  });
  return parseJsonResponse(response);
}

function requestHeaders({ bearer, cookie } = {}) {
  const headers = {};
  if (bearer) headers.authorization = `Bearer ${bearer}`;
  if (cookie) headers.cookie = cookie;
  return headers;
}

async function createDriveSessionCookie() {
  const response = await fetch(`${baseUrl}/drive/session`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ password: "drive-password-for-tests" }),
  });
  assert.equal(response.status, 200);
  return response.headers.get("set-cookie").split(";")[0];
}

async function parseJsonResponse(response) {
  const text = await response.text();
  return {
    status: response.status,
    body: text ? JSON.parse(text) : {},
  };
}
