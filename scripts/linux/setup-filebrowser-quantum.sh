#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/nas-cloud/filebrowser}"
POOL="${POOL:-livepool}"
DATASET="${DATASET:-${POOL}/drive}"
DRIVE_MOUNT="${DRIVE_MOUNT:-/srv/nas/live/drive}"
HOST_PORT="${HOST_PORT:-8090}"
PUBLIC_URL="${PUBLIC_URL:-https://drive.example.com}"
APP_NAME="${APP_NAME:-NAS Drive}"
SOURCE_NAME="${SOURCE_NAME:-NAS Drive}"

echo "[1/7] Checking live ZFS pool"
if ! zpool list -H "$POOL" >/dev/null 2>&1; then
  echo "ZFS pool '$POOL' was not found. Aborting before touching storage." >&2
  exit 1
fi

echo "[2/7] Preparing drive dataset"
if zfs list -H "$DATASET" >/dev/null 2>&1; then
  current_mount="$(zfs get -H -o value mountpoint "$DATASET")"
  if [ "$current_mount" != "$DRIVE_MOUNT" ]; then
    echo "Existing dataset '$DATASET' has mountpoint '$current_mount', expected '$DRIVE_MOUNT'." >&2
    exit 1
  fi
else
  zfs create -o mountpoint="$DRIVE_MOUNT" "$DATASET"
fi

mkdir -p "$DRIVE_MOUNT"/{files,integrations,shared,uploads}
chown -R 1000:1000 "$DRIVE_MOUNT"

echo "[3/7] Preparing FileBrowser Quantum app directory"
mkdir -p "$APP_DIR/data"
chown -R 1000:1000 "$APP_DIR"

echo "[4/7] Writing config.yaml"
cat > "$APP_DIR/data/config.yaml" <<EOF_CONFIG
frontend:
  name: "$APP_NAME"

server:
  cacheDir: /home/filebrowser/data/tmp
  database: /home/filebrowser/data/database.db
  externalUrl: "$PUBLIC_URL"
  sources:
    - path: /srv
      name: "$SOURCE_NAME"
      config:
        defaultEnabled: true
EOF_CONFIG

chown 1000:1000 "$APP_DIR/data/config.yaml"
chmod 600 "$APP_DIR/data/config.yaml"

echo "[5/7] Writing compose.yaml"
cat > "$APP_DIR/compose.yaml" <<EOF_COMPOSE
services:
  filebrowser:
    image: gtstef/filebrowser:stable
    container_name: nas-filebrowser-quantum
    restart: unless-stopped
    ports:
      - "${HOST_PORT}:80"
    volumes:
      - ./data:/home/filebrowser/data
      - ${DRIVE_MOUNT}:/srv
EOF_COMPOSE

chown 1000:1000 "$APP_DIR/compose.yaml"

echo "[6/7] Starting FileBrowser Quantum"
cd "$APP_DIR"
docker compose up -d

echo "[7/7] Verifying local service"
docker compose ps
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "http://127.0.0.1:${HOST_PORT}/" >/dev/null 2>&1; then
    echo "FileBrowser Quantum is healthy at http://127.0.0.1:${HOST_PORT}"
    echo "Drive data root: $DRIVE_MOUNT"
    echo "Display name: $APP_NAME"
    echo "Source name: $SOURCE_NAME"
    echo "Korean UI: browser Korean locale is auto-detected; existing users can also set Profile/Settings -> Language -> Korean."
    exit 0
  fi
  sleep 2
done

echo "FileBrowser Quantum did not answer /health in time. Recent logs:" >&2
docker compose logs --tail=120 filebrowser >&2
exit 1
