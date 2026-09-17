#!/usr/bin/env bash
# Generates an SPDX 2.3 JSON SBOM from an exact local image.
#
# Usage: generate-sbom.sh IMAGE [OUTPUT]
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 && $# -le 2 ]] || fail "usage: generate-sbom.sh IMAGE [OUTPUT]"
image="$1"
output="${2:-${DIST_DIR}/sbom.spdx.json}"

mkdir -p "$(dirname "${output}")"
rm -f "${output}"

log "SPDX 2.3 SBOM: ${image}"
syft scan "docker:${image}" -o "spdx-json@2.3=${output}" --quiet
[[ -s "${output}" ]] || fail "SBOM was not written to ${output}"
pass "SBOM written to ${output#"${REPO_ROOT}"/}"
