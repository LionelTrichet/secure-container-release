#!/usr/bin/env bash
# Asserts that every pinned version agrees across the repository.
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

expect() {
	[[ "$2" == "$3" ]] || fail "$1: expected '$3', found '$2'"
	info "$1 = $3"
}

log "build/versions.env"
expect GO_VERSION "${GO_VERSION}" 1.27.1
expect TRIVY_VERSION "${TRIVY_VERSION}" 0.74.0
expect SYFT_VERSION "${SYFT_VERSION}" 1.51.1
expect COSIGN_VERSION "${COSIGN_VERSION}" 3.1.3
expect BUILDX_VERSION "${BUILDX_VERSION}" 0.37.0
expect BUILDKIT_VERSION "${BUILDKIT_VERSION}" 0.33.0
expect APP_VERSION "${APP_VERSION}" 0.1.0
expect TRIVY_CHECKSUM_FILE_SHA256 "${TRIVY_CHECKSUM_FILE_SHA256}" bc701c3c3ee8b9acbea2c23257e41381e3854888f51281616a6ba5dc96963821
expect SYFT_CHECKSUM_FILE_SHA256 "${SYFT_CHECKSUM_FILE_SHA256}" 105346699e7cb694afa37a21e2386432df6278c99f71331c24b1e0bb0f38cc75

log "Go"
expect "go.mod go directive" "$(awk '$1 == "go" { print $2; exit }' "${REPO_ROOT}/go.mod")" "${GO_VERSION}"
grep -Eq "^FROM golang:${GO_VERSION//./\\.}-bookworm@" "${REPO_ROOT}/Dockerfile" ||
	fail "Dockerfile builder is not golang:${GO_VERSION}"
info "Dockerfile builder = golang:${GO_VERSION}"
for workflow in ci.yml release.yml; do
	file="${REPO_ROOT}/.github/workflows/${workflow}"
	count="$(grep -Ec "go-version:[[:space:]]*'${GO_VERSION//./\\.}'" "${file}" || true)"
	((count >= 1)) || fail "${workflow} does not set go-version '${GO_VERSION}'"
	if grep -E "go-version:" "${file}" | grep -Ev "'${GO_VERSION//./\\.}'" | grep -q .; then
		fail "${workflow} sets a different go-version"
	fi
	info "${workflow} go-version = ${GO_VERSION}"
done
[[ -e "${REPO_ROOT}/go.sum" ]] && fail "go.sum exists but the module has no external dependencies"
info "no go.sum"

log "Buildx, BuildKit and Cosign in workflows"
for workflow in ci.yml release.yml; do
	file="${REPO_ROOT}/.github/workflows/${workflow}"
	grep -Eq "version:[[:space:]]*v${BUILDX_VERSION//./\\.}$" "${file}" ||
		fail "${workflow} does not pin Buildx v${BUILDX_VERSION}"
	grep -Eq "image=moby/buildkit:v${BUILDKIT_VERSION//./\\.}-ubuntu@sha256:[a-f0-9]{64}$" "${file}" ||
		fail "${workflow} does not pin BuildKit v${BUILDKIT_VERSION} by digest"
	info "${workflow} Buildx v${BUILDX_VERSION}, BuildKit v${BUILDKIT_VERSION}"
done
grep -Eq "cosign-release:[[:space:]]*'v${COSIGN_VERSION//./\\.}'" "${REPO_ROOT}/.github/workflows/release.yml" ||
	fail "release.yml does not pin Cosign v${COSIGN_VERSION}"
info "release.yml cosign-release = v${COSIGN_VERSION}"

log "Action version comments"
"${REPO_ROOT}/scripts/verify-action-pins.sh" >/dev/null
info "Action comments correspond to allowlisted releases"

pass "versions are consistent"
