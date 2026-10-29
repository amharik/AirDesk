#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FLATC=${FLATC:-flatc}
EXPECTED=25.12.19
ACTUAL=$("$FLATC" --version | awk '{print $3}')

if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "flatc $EXPECTED required, found $ACTUAL" >&2
  exit 1
fi

cd "$ROOT"
rm -rf web/src/protocol/generated/air-desk
mkdir -p web/src/protocol/generated AirDesk/Protocol/Generated protocol/generated/rust

"$FLATC" --ts -o web/src/protocol/generated protocol/airdesk.fbs
"$FLATC" --swift -o AirDesk/Protocol/Generated protocol/airdesk.fbs
"$FLATC" --rust -o protocol/generated/rust protocol/airdesk.fbs

find web/src/protocol/generated -name '*.ts' -type f | while IFS= read -r file; do
  tmp=$(mktemp)
  {
    echo '// @ts-nocheck'
    cat "$file"
  } > "$tmp"
  mv "$tmp" "$file"
done

echo "Generated protocol bindings with flatc $ACTUAL."
