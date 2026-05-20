#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/nas-cloud/filebrowser}"
APP_NAME="${APP_NAME:-NAS Drive}"
SOURCE_NAME="${SOURCE_NAME:-NAS Drive}"
CONFIG="$APP_DIR/data/config.yaml"

if [ ! -f "$CONFIG" ]; then
  echo "Missing config: $CONFIG" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
cp "$CONFIG" "$CONFIG.bak-$STAMP"

python3 - "$CONFIG" "$APP_NAME" "$SOURCE_NAME" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
app_name = sys.argv[2]
source_name = sys.argv[3]
text = path.read_text(encoding="utf-8")

if not text.startswith("frontend:\n"):
    text = f'frontend:\n  name: "{app_name}"\n\n' + text
else:
    lines = text.splitlines()
    out = []
    i = 0
    while i < len(lines):
        if lines[i] == "frontend:":
            out.append(lines[i])
            i += 1
            found_name = False
            while i < len(lines) and (lines[i].startswith("  ") or lines[i] == ""):
                if lines[i].lstrip().startswith("name:"):
                    out.append(f'  name: "{app_name}"')
                    found_name = True
                else:
                    out.append(lines[i])
                i += 1
            if not found_name:
                out.append(f'  name: "{app_name}"')
            continue
        out.append(lines[i])
        i += 1
    text = "\n".join(out) + "\n"

for old in (
    "      name: NAS Drive",
    '      name: "NAS Drive"',
    "      name: NAS Drive",
):
    text = text.replace(old, f'      name: "{source_name}"')

# Do not keep bootstrap credentials in config.yaml. If these remain after the
# first run, restarting the container can reset the admin password.
lines = text.splitlines()
out = []
i = 0
while i < len(lines):
    if lines[i] == "auth:":
        block = [lines[i]]
        i += 1
        while i < len(lines) and (lines[i].startswith("  ") or lines[i] == ""):
            block.append(lines[i])
            i += 1

        kept = []
        for line in block[1:]:
            key = line.strip().split(":", 1)[0]
            if key in {"adminUsername", "adminPassword"}:
                continue
            kept.append(line)

        if any(line.strip() for line in kept):
            out.append("auth:")
            out.extend(kept)
        continue

    out.append(lines[i])
    i += 1

text = "\n".join(out) + "\n"

path.write_text(text, encoding="utf-8")
PY

cd "$APP_DIR"
if command -v docker >/dev/null 2>&1; then
  docker compose restart filebrowser || docker compose up -d
else
  echo "Docker command not found; config was patched but container was not restarted." >&2
fi

echo "Applied Korean-friendly FileBrowser settings."
echo "Config backup: $CONFIG.bak-$STAMP"
echo "Display name: $APP_NAME"
echo "Source name: $SOURCE_NAME"
echo "Note: per-user language is controlled by browser locale or the user's Language setting."
