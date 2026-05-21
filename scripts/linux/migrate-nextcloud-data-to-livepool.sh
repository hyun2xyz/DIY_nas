#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/nas-cloud/nextcloud}"
TARGET_DATA="${TARGET_DATA:-/srv/nas/live/nextcloud-data}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/nas-cloud/backups}"

if [[ ! -f "$APP_DIR/compose.yaml" ]]; then
  echo "compose.yaml not found at $APP_DIR." >&2
  exit 1
fi

if [[ ! -d "$TARGET_DATA" ]]; then
  echo "Target data directory does not exist: $TARGET_DATA" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"

cd "$APP_DIR"

echo "[1/7] Stopping Nextcloud stack"
sudo docker compose down

echo "[2/7] Copying current data to $TARGET_DATA"
sudo rsync -aHAX --numeric-ids ./data/ "$TARGET_DATA/"
sudo chown -R 33:33 "$TARGET_DATA"

echo "[3/7] Backing up compose.yaml"
cp compose.yaml "compose.yaml.before-livepool-$(date +%Y%m%d-%H%M%S)"

echo "[4/7] Repointing app and cron data bind mount"
python3 - <<'PY'
from pathlib import Path

path = Path("compose.yaml")
text = path.read_text()
old = "- ./data:/var/www/html/data"
new = "- /srv/nas/live/nextcloud-data:/var/www/html/data"
if old not in text and new not in text:
    raise SystemExit("Expected Nextcloud data bind mount was not found.")
text = text.replace(old, new)
path.write_text(text)
PY

echo "[5/7] Installing backup script that writes to $BACKUP_DIR"
cat > "$HOME/nas-cloud/backup-nextcloud-cold.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$HOME/nas-cloud/nextcloud"
BACKUP_DIR="${BACKUP_DIR:-$HOME/nas-cloud/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP_DIR/nextcloud-cold-$STAMP.tar.gz"

cd "$APP_DIR"
mkdir -p "$BACKUP_DIR"

echo "[1/4] Stopping Nextcloud containers"
sudo docker compose down

echo "[2/4] Creating cold backup: $DEST"
sudo tar -czf "$DEST" compose.yaml html /srv/nas/live/nextcloud-data db

echo "[3/4] Restarting Nextcloud containers"
sudo docker compose up -d

echo "[4/4] Writing checksum"
sha256sum "$DEST" > "$DEST.sha256"

echo "Backup created:"
ls -lh "$DEST" "$DEST.sha256"
EOF
chmod +x "$HOME/nas-cloud/backup-nextcloud-cold.sh"

echo "[6/7] Starting Nextcloud stack"
sudo docker compose up -d
sudo docker compose ps

echo "[7/7] Verifying data mount and disk usage"
mount | grep '/srv/nas/live/nextcloud-data' || true
du -sh "$TARGET_DATA" "$BACKUP_DIR"
