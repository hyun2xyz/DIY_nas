import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { createIntegrationGatewayServer, loadGatewayTokensFromEnvironment } from "./integration-gateway.mjs";

const rootDir = fileURLToPath(new URL("..", import.meta.url));
await loadLocalEnv(rootDir);

const host = process.env.NAS_GATEWAY_HOST || "127.0.0.1";
const port = Number(process.env.NAS_GATEWAY_PORT || 8791);
const tokens = await loadGatewayTokensFromEnvironment();

const server = createIntegrationGatewayServer({ tokens });
server.listen(port, host, () => {
  console.log(`NAS integration gateway listening on http://${host}:${port}`);
  console.log(`Nextcloud base URL: ${process.env.NEXTCLOUD_BASE_URL || "(not configured)"}`);
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
