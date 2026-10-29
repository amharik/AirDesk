#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-"$ROOT/CastReceiver/dist"}"
SHELL_SRC="$ROOT/AirDesk/Resources/DesktopShell"

if [[ ! -f "$SHELL_SRC/index.html" ]]; then
  echo "Missing desktop shell: $SHELL_SRC/index.html" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/desktop"

install -m 0644 "$ROOT/CastReceiver/index.html" "$OUT/index.html"
install -m 0644 "$ROOT/CastReceiver/receiver.js" "$OUT/receiver.js"
install -m 0644 "$ROOT/CastReceiver/receiver.css" "$OUT/receiver.css"
cp -R "$SHELL_SRC/." "$OUT/desktop/"

perl -0pi -e 's#\.\./AirDesk/Resources/DesktopShell/index\.html#desktop/index.html#g' "$OUT/receiver.js"

if grep -q '../AirDesk/Resources/DesktopShell' "$OUT/receiver.js"; then
  echo "Packaged receiver still references the repository layout." >&2
  exit 1
fi

echo "Packaged Cast receiver: $OUT"
echo "Serve this directory over HTTPS with COOP/COEP headers and register:"
echo "  https://<receiver-host>/index.html"
