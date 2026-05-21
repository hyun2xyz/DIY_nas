import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { createPilotCloudServer } from "./app.mjs";

const rootDir = fileURLToPath(new URL("..", import.meta.url));
await loadLocalEnv(rootDir);

const host = process.env.NAS_PILOT_HOST || "127.0.0.1";
const port = Number(process.env.NAS_PILOT_PORT || 8790);

const server = createPilotCloudServer();
server.listen(port, host, () => {
  console.log(`NAS pilot cloud listening on http://${host}:${port}`);
  console.log(`Data dir: ${process.env.NAS_PILOT_DATA_DIR || join(process.env.USERPROFILE || rootDir, "nas-pilot-data")}`);
});

server.on("error", (error) => {
  console.error(error.message);
  process.exit(1);
});

async function loadLocalEnv(root) {
  try {
    const env = await readFile(join(root, ".env"), "utf8");
    for (const line of env.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const separator = trimmed.indexOf("=");
      if (separator === -1) continue;

      const key = trimmed.slice(0, separator).trim();
      const value = trimmed.slice(separator + 1).trim().replace(/^"|"$/g, "");
      if (!process.env[key]) process.env[key] = value;
    }
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
}
