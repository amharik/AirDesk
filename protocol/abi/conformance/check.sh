#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
MANIFEST="$ROOT/protocol/abi/conformance/manifest.json"
ABI_CHECK="$ROOT/protocol/abi/check.sh"

fail() {
  echo "host ABI conformance check failed: $*" >&2
  exit 1
}

[ -f "$MANIFEST" ] || fail "missing ${MANIFEST#"$ROOT/"}"
[ -x "$ABI_CHECK" ] || fail "missing executable ${ABI_CHECK#"$ROOT/"}"

# Static WIT validity comes before any runtime claim.
"$ABI_CHECK"

if ! command -v python3 >/dev/null 2>&1; then
  fail "python3 required to validate the conformance manifest"
fi

python3 - "$MANIFEST" <<'PY'
import json
import os
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)


def require(condition, message):
    if not condition:
        print(f"host ABI conformance check failed: {message}", file=sys.stderr)
        sys.exit(1)


require(manifest.get("contractVersion") == 1, "contractVersion must be 1")
require(
    manifest.get("profile") == "airdesk-host-abi-conformance-v1",
    "unexpected profile",
)
require(
    manifest.get("baselineAbi") == "airdesk:host-abi@0.2.0",
    "baselineAbi must be airdesk:host-abi@0.2.0",
)
require(
    manifest.get("targetAbi") == "airdesk:host-abi@0.3.0",
    "targetAbi must be airdesk:host-abi@0.3.0",
)
require(
    manifest.get("tooling", {}).get("wasmTools") == "1.263.0",
    "tooling.wasmTools must be 1.263.0",
)
rules = manifest.get("rules", {})
require(rules.get("perRuntimeQualification") is True, "per-runtime qualification is required")
require(
    rules.get("crossRuntimeEquivalenceAssumed") is False,
    "cross-runtime equivalence must not be assumed",
)
require(
    rules.get("requiresEvidenceForQualified") is True,
    "qualified runtimes require evidence",
)
require(rules.get("mixedWorlds") == "rejected", "mixed worlds must be rejected")

required_interfaces = {"vfs-service", "pty-service", "display-sink"}
runtimes = manifest.get("runtimes")
require(isinstance(runtimes, list) and runtimes, "runtimes must be a non-empty list")
qualified = manifest.get("qualifiedRuntimes")
require(isinstance(qualified, list), "qualifiedRuntimes must be a list")

by_id = {}
for runtime in runtimes:
    require(isinstance(runtime, dict), "each runtime must be an object")
    runtime_id = runtime.get("id")
    require(isinstance(runtime_id, str) and runtime_id, "runtime id is required")
    require(runtime_id not in by_id, f"duplicate runtime id {runtime_id}")
    by_id[runtime_id] = runtime

    claimed = runtime.get("claimedInterfaces")
    require(isinstance(claimed, list), f"{runtime_id}: claimedInterfaces must be a list")
    require(
        set(claimed).issubset(required_interfaces),
        f"{runtime_id}: unknown claimed interface",
    )

    status = runtime.get("status")
    require(status in {"not-run", "failed", "passed"}, f"{runtime_id}: invalid status")
    evidence = runtime.get("evidence")
    if status in {"failed", "passed"}:
        require(isinstance(evidence, str) and evidence, f"{runtime_id}: {status} requires evidence")
        evidence_path = evidence if os.path.isabs(evidence) else os.path.join(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(path)))),
            evidence,
        )
        require(os.path.isfile(evidence_path), f"{runtime_id}: evidence file is missing: {evidence}")
    else:
        require(evidence is None, f"{runtime_id}: not-run runtime must not carry evidence")

for runtime_id in qualified:
    require(runtime_id in by_id, f"unknown qualified runtime {runtime_id}")
    require(
        by_id[runtime_id].get("status") == "passed",
        f"qualified runtime {runtime_id} is not marked passed",
    )

passed = {runtime_id for runtime_id, runtime in by_id.items() if runtime.get("status") == "passed"}
require(
    passed == set(qualified),
    "qualifiedRuntimes must contain exactly the passed runtimes",
)

require(
    len(by_id) == 3 and set(by_id) == {"wanix", "native-rust", "native-swift"},
    "expected wanix, native-rust and native-swift runtime records",
)

print(f"Conformance manifest valid: {len(qualified)} qualified runtime(s).")
PY

echo "Host ABI conformance harness is current; runtime results remain unclaimed unless listed as qualified."
