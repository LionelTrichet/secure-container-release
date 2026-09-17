#!/usr/bin/env bash
# Vulnerability report (HIGH, CRITICAL) followed by a CRITICAL gate.
# Unfixed vulnerabilities are not ignored and nothing is suppressed.
#
# Usage: scan-image.sh IMAGE
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 1 ]] || fail "usage: scan-image.sh IMAGE"
image="$1"

[[ ! -e "${REPO_ROOT}/.trivyignore" ]] || fail ".trivyignore must not exist"

log "Vulnerability report (HIGH, CRITICAL): ${image}"
trivy image --scanners vuln --severity HIGH,CRITICAL --exit-code 0 --no-progress "${image}"

log "CRITICAL gate: ${image}"
if ! trivy image --scanners vuln --severity CRITICAL --exit-code 1 --no-progress --quiet "${image}"; then
	fail "CRITICAL vulnerabilities found in ${image}"
fi
pass "no CRITICAL vulnerabilities"
