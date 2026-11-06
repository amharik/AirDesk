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

if [ ! -f "$ROOT/protocol/baseline/airdesk_v1.fbs" ]; then
  echo "missing protocol/baseline/airdesk_v1.fbs" >&2
  exit 1
fi

"$FLATC" --conform "$ROOT/protocol/baseline/airdesk_v1.fbs" "$ROOT/protocol/airdesk.fbs"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/swift" "$TMP/ts" "$TMP/rust" "$TMP/kotlin"

"$FLATC" --swift -o "$TMP/swift" "$ROOT/protocol/airdesk.fbs"
"$FLATC" --ts -o "$TMP/ts" "$ROOT/protocol/airdesk.fbs"
"$FLATC" --rust -o "$TMP/rust" "$ROOT/protocol/airdesk.fbs"
"$FLATC" --kotlin -o "$TMP/kotlin" "$ROOT/protocol/airdesk.fbs"

sed 's/[[:space:]]*$//' "$TMP/swift/airdesk_generated.swift" > "$TMP/swift/airdesk_generated.normalized.swift"
cmp "$TMP/swift/airdesk_generated.normalized.swift" "$ROOT/AirDesk/Protocol/Generated/airdesk_generated.swift"
cmp "$TMP/rust/airdesk_generated.rs" "$ROOT/protocol/generated/rust/airdesk_generated.rs"

find "$TMP/ts" -name '*.ts' -type f | while IFS= read -r generated; do
  expected="$TMP/expected.ts"
  {
    echo '// @ts-nocheck'
    cat "$generated"
  } > "$expected"
  mv "$expected" "$generated"
done

"$ROOT/protocol/patch-generated-ts.sh" "$TMP/ts/air-desk/protocol/envelope.ts"

find "$TMP/ts" -name '*.ts' -type f | while IFS= read -r generated; do
  relative=${generated#"$TMP/ts/"}
  committed="$ROOT/web/src/protocol/generated/$relative"
  cmp "$generated" "$committed"
done

find "$TMP/kotlin" -name '*.kt' -type f | while IFS= read -r generated; do
  relative=${generated#"$TMP/kotlin/"}
  cmp "$generated" "$ROOT/protocol/generated/kotlin/$relative"
done

echo "Protocol schema, baseline conformance and generated bindings are current."
