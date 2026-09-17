#!/usr/bin/env bash
# Checks local prerequisites for building and verifying the image.
# Trivy and Syft are checked separately by require-security-tools.sh.
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Checking commands"
for command in go docker git curl jq make; do
	require_command "${command}"
	info "found ${command}"
done
docker buildx version >/dev/null 2>&1 || fail "docker buildx is not available"
info "found docker buildx"

log "Checking Docker daemon"
docker info >/dev/null 2>&1 || fail "Docker daemon is not reachable"
info "Docker daemon reachable"

pass "prerequisites satisfied"
