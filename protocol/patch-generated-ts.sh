#!/bin/sh
set -eu

# flatc 25.12.19 omits the TypeScript create helper for tables that contain
# both union fields and table fields. Envelope now has a ControlHeader table
# field alongside two unions, so restore the helper to keep the existing
# Envelope.createEnvelope(...) call sites working. Callers that only pass the
# original four arguments keep the historical behavior.

FILE=${1:?usage: patch-generated-ts.sh <generated-envelope.ts>}

if [ ! -f "$FILE" ]; then
  echo "missing generated TypeScript envelope: $FILE" >&2
  exit 1
fi

if grep -q 'static createEnvelope(' "$FILE"; then
  exit 0
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

awk '
  { lines[NR] = $0 }
  /^}$/ { last = NR }
  END {
    for (i = 1; i <= NR; i++) {
      if (i == last) {
        print "static createEnvelope(builder:flatbuffers.Builder, version:number, payloadType:MessagePayload, payloadOffset:flatbuffers.Offset, headerOffset:flatbuffers.Offset = 0, fabricPayloadType:FabricPayload = FabricPayload.NONE, fabricPayloadOffset:flatbuffers.Offset = 0):flatbuffers.Offset {"
        print "  Envelope.startEnvelope(builder);"
        print "  Envelope.addVersion(builder, version);"
        print "  Envelope.addPayloadType(builder, payloadType);"
        print "  Envelope.addPayload(builder, payloadOffset);"
        print "  Envelope.addHeader(builder, headerOffset);"
        print "  Envelope.addFabricPayloadType(builder, fabricPayloadType);"
        print "  Envelope.addFabricPayload(builder, fabricPayloadOffset);"
        print "  return Envelope.endEnvelope(builder);"
        print "}"
      }
      print lines[i]
    }
  }
' "$FILE" > "$TMP"

mv "$TMP" "$FILE"
trap - EXIT
