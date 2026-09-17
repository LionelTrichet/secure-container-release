#!/usr/bin/env bash
# SPDX 2.3 SBOM contract.
#
# Usage: verify-sbom.sh [SBOM]
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

sbom="${1:-${DIST_DIR}/sbom.spdx.json}"
readonly MAX_BYTES=$((16 * 1024 * 1024))

[[ -f "${sbom}" ]] || fail "SBOM not found: ${sbom}"
size="$(file_size "${sbom}")"
((size > 0)) || fail "SBOM is empty"
((size < MAX_BYTES)) || fail "SBOM is ${size} bytes, limit is 16 MiB"

jq -e . "${sbom}" >/dev/null || fail "SBOM is not valid JSON"
jq -e '
	.spdxVersion == "SPDX-2.3"
	and .SPDXID == "SPDXRef-DOCUMENT"
	and ((.name // "") | length > 0)
	and ((.documentNamespace // "") | length > 0)
	and (.creationInfo | type == "object")
	and (.packages | type == "array")
	and (.packages | length >= 1)
' "${sbom}" >/dev/null || fail "SBOM does not satisfy the SPDX 2.3 contract"

pass "SPDX 2.3 SBOM valid: $(jq '.packages | length' "${sbom}") packages, ${size} bytes"
