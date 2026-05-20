import { after, before, describe, it } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createPilotCloudServer } from "../src/app.mjs";

let dataDir;
let server;
let baseUrl;
let adminCookie;
let userCookie;
let apiToken;

before(async () => {
  dataDir = await mkdtemp(join(tmpdir(), "nas-pilot-test-"));
  server = createPilotCloudServer({
    dataDir,
    quotaBytes: 1024 * 1024,
    adminUsername: "admin",
    adminPassword: "admin-pass",
  });

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  baseUrl = `http://127.0.0.1:${port}`;
});

after(async () => {
  await new Promise((resolve) => server.close(resolve));
  await rm(dataDir, { recursive: true, force: true });
});

describe("NAS pilot cloud", () => {
  it("logs in as the bootstrap admin", async () => {
    const response = await postJson("/api/auth/login", {
      username: "admin",
      password: "admin-pass",
    });

    assert.equal(response.status, 200);
    assert.equal(response.body.user.username, "admin");
    assert.equal(response.body.user.role, "admin");
    adminCookie = response.cookie;
    assert.match(adminCookie, /nas_pilot_session=/);
  });

  it("lets an admin create a normal user", async () => {
    const response = await postJson(
      "/api/admin/users",
      { username: "user1", password: "user-pass", role: "user" },
      { cookie: adminCookie },
    );

    assert.equal(response.status, 201);
    assert.equal(response.body.user.username, "user1");
    assert.equal(response.body.user.role, "user");
  });

  it("logs in as a normal user and uploads a file", async () => {
    const login = await postJson("/api/auth/login", {
      username: "user1",
      password: "user-pass",
    });
    assert.equal(login.status, 200);
    userCookie = login.cookie;

    const upload = await postJson(
      "/api/files/upload",
      {
        path: "",
        filename: "hello.txt",
        contentBase64: Buffer.from("hello cloud").toString("base64"),
      },
      { cookie: userCookie },
    );

    assert.equal(upload.status, 201);
    assert.equal(upload.body.file.path, "hello.txt");
  });

  it("keeps user files isolated", async () => {
    const userList = await getJson("/api/files", { cookie: userCookie });
    assert.equal(userList.status, 200);
    assert.deepEqual(
      userList.body.entries.map((entry) => entry.name),
      ["hello.txt"],
    );

    const adminList = await getJson("/api/files", { cookie: adminCookie });
    assert.equal(adminList.status, 200);
    assert.deepEqual(adminList.body.entries, []);
  });

  it("blocks path traversal and quota overflow", async () => {
    const traversal = await postJson(
      "/api/files/upload",
      {
        path: "..",
        filename: "bad.txt",
        contentBase64: Buffer.from("bad").toString("base64"),
      },
      { cookie: userCookie },
    );
    assert.equal(traversal.status, 400);

    const tooLarge = await postJson(
      "/api/files/upload",
      {
        path: "",
        filename: "large.bin",
        contentBase64: Buffer.alloc(1024 * 1024 + 1).toString("base64"),
      },
      { cookie: userCookie },
    );
    assert.equal(tooLarge.status, 413);
  });

  it("blocks Windows reserved filenames", async () => {
    const response = await postJson(
      "/api/files/upload",
      {
        path: "",
        filename: "CON.txt",
        contentBase64: Buffer.from("bad").toString("base64"),
      },
      { cookie: userCookie },
    );

    assert.equal(response.status, 400);
  });

  it("lets an admin create a scoped API token for future hosting-server integration", async () => {
    const response = await postJson(
      "/api/admin/tokens",
      { name: "cafe24-pilot", owner: "user1", scopes: ["files:read", "files:write"] },
      { cookie: adminCookie },
    );

    assert.equal(response.status, 201);
    assert.match(response.body.token, /^npc_/);
    assert.deepEqual(response.body.scopes, ["files:read", "files:write"]);
    apiToken = response.body.token;
  });

  it("rejects write operations with a read-only API token", async () => {
    const tokenResponse = await postJson(
      "/api/admin/tokens",
      { name: "readonly", owner: "user1", scopes: ["files:read"] },
      { cookie: adminCookie },
    );

    const upload = await postJson(
      "/api/integration/upload",
      {
        path: "",
        filename: "readonly.txt",
        contentBase64: Buffer.from("no").toString("base64"),
      },
      { bearer: tokenResponse.body.token },
    );

    assert.equal(upload.status, 403);
  });

  it("allows token-based API upload and download", async () => {
    const upload = await postJson(
      "/api/integration/upload",
      {
        path: "api",
        filename: "from-hosting.txt",
        contentBase64: Buffer.from("from cafe24 later").toString("base64"),
      },
      { bearer: apiToken },
    );
    assert.equal(upload.status, 201);

    const list = await getJson("/api/integration/files?path=api", { bearer: apiToken });
    assert.equal(list.status, 200);
    assert.equal(list.body.entries[0].name, "from-hosting.txt");

    const download = await fetch(`${baseUrl}/api/integration/download?path=api/from-hosting.txt`, {
      headers: { authorization: `Bearer ${apiToken}` },
    });
    assert.equal(download.status, 200);
    assert.equal(await download.text(), "from cafe24 later");
  });

  it("writes audit events without logging token values", async () => {
    const audit = await readFile(join(dataDir, "audit", "events.ndjson"), "utf8");
    assert.match(audit, /"event":"login"/);
    assert.match(audit, /"event":"file.upload"/);
    assert.match(audit, /"event":"token.create"/);
    assert.doesNotMatch(audit, /npc_/);
  });
});

async function getJson(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    headers: requestHeaders(options),
  });
  return parseResponse(response);
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
  return parseResponse(response);
}

function requestHeaders({ cookie, bearer } = {}) {
  const headers = {};
  if (cookie) headers.cookie = cookie;
  if (bearer) headers.authorization = `Bearer ${bearer}`;
  return headers;
}

async function parseResponse(response) {
  const cookie = response.headers.get("set-cookie") || "";
  const text = await response.text();
  return {
    status: response.status,
    cookie,
    body: text ? JSON.parse(text) : {},
  };
}
