# ADR-003: Third-party dependency admission and commercial licensing policy

- **Status:** Proposed — qualification gates required
- **Date:** 2026-10-29
- **Scope:** All third-party source, binaries, WASM, SDKs, and services used by AirDesk or Wanix
- **Supersedes:** None
- **Related:** ADR-001, ADR-002, ADR-007
- **Implementation:** Web dependency pins, license gate, and CycloneDX SBOM generation are active as of 2026-10-29.

## Decision

Adopt a gated dependency policy. A library enters the production baseline only after its license, maintenance, platform fit, security posture, and AirDesk-specific behavior have been reviewed. “Popular” or “upstream-tested” is not sufficient by itself.

Every dependency is assigned one status:

- **Spike:** isolated experiment; not shipped.
- **Trial:** shipped behind an adapter or feature flag; may be removed.
- **Adopt:** approved for production use at a pinned version.
- **Hold:** evaluated but not approved; may be revisited.
- **Reject:** not permitted without a superseding ADR.

Promotion requires the evidence below. A Trial may not become Adopt because it “works on my machine.”

## License policy

### Pre-approved for distributed client code

The following SPDX licenses are approved for code distributed in AirDesk clients, subject to notice and attribution obligations:

- MIT
- BSD-2-Clause
- BSD-3-Clause
- Apache-2.0
- ISC
- MPL-2.0

MPL-2.0 remains file-level copyleft; modified MPL files must be made available under MPL-2.0. Apache-2.0 requires preservation of notices and patent terms.

### GPL

GPL is permitted only in **server-side or separately distributed optional modules** that are not linked, bundled, or shipped inside the AirDesk iOS/Android client or App Store binary. Use a process, container, or network boundary. Commercial use is allowed, but distribution triggers source, notice, and installation obligations.

Where a project offers “GPLv2 or later,” prefer GPLv2 to reduce installation-information obligations. GPL components must not be treated as an implementation detail hidden behind a permissive wrapper.

### AGPL and SSPL

AGPL and SSPL are **case-by-case**. They are not pre-approved. AGPL server use requires a source-offer and network-use review. SSPL requires explicit commercial and legal review because it is not an OSI-approved license and may impose service-distribution obligations.

### LGPL and all other licenses

LGPL is not pre-approved. It requires case-by-case review covering linking, relinking, replacement, and distribution mechanics. All licenses not listed above require review before use.

### Commercial distribution obligations

Before any commercial release:

- produce a complete dependency inventory and SBOM;
- preserve license texts and NOTICE files;
- document source-offer obligations for copyleft components;
- verify that build outputs are reproducible enough to satisfy source obligations;
- obtain legal sign-off for GPL/AGPL/SSPL or any non-pre-approved license;
- confirm that App Store or Play Store terms do not conflict with the license.

## Admission gates

A dependency is eligible for **Adopt** only when all gates pass.

1. **License:** SPDX identifier confirmed, obligations understood, and distribution boundary approved.
2. **Maintenance:** recent release or active commit history, a security-reporting path, and a credible maintainer/bus factor assessment.
3. **Platform fit:** supported in WKWebView, Android WebView, and Cast Chromium where applicable; no undocumented JIT, native-code, or origin assumptions.
4. **Upstream evidence:** upstream test suite passes at the pinned version; known issues are reviewed.
5. **AirDesk evidence:** integration test, failure-mode test, performance benchmark, binary-size measurement, and rollback plan.
6. **Supply chain:** exact version or commit pin, integrity hash, lockfile entry, and provenance note.
7. **Exit strategy:** an adapter boundary or migration plan exists for components that touch runtime, transport, compositor, or terminal behavior.

## Required artifacts

Each adopted dependency must have:

- exact version or commit;
- SPDX license and NOTICE status;
- SBOM entry, preferably CycloneDX;
- lockfile or integrity hash;
- owner and review date;
- link to the qualification benchmark and tests;
- known limitations and removal plan where relevant.

## Exceptions

An exception must be time-boxed and recorded in the adopting ADR or backlog item. It must name:

- the component and version;
- the unmet gate;
- the compensating control;
- the owner;
- the expiry date or next review trigger.

Expired exceptions block release.

## Consequences

- Adoption is slower and requires evidence, but license contamination and platform surprises are caught before release.
- GPL server components remain possible, including in a commercial product, without putting copyleft code into the client binary.
- Every layer needs an adapter or explicit exit plan, which increases design work but limits lock-in.
- The policy creates ongoing maintenance: SBOM generation, pin updates, security review, and periodic re-qualification.
- “Tested” means tested by upstream and qualified by AirDesk; neither alone is sufficient.
