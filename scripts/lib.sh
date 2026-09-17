#!/usr/bin/env bash
# Shared helpers. Sourced by the other scripts; reads only repository files.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

# shellcheck source=../build/versions.env
. "${REPO_ROOT}/build/versions.env"

readonly LOCAL_IMAGE="secure-container-release:local"
readonly DIST_DIR="${REPO_ROOT}/dist"
readonly SHA_PATTERN='^[a-f0-9]{40}$'
readonly DIGEST_PATTERN='^sha256:[a-f0-9]{64}$'

log() { printf '==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
pass() { printf 'PASS: %s\n' "$*"; }
fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

# download OUTPUT URL — fail-fast download with bounded retries.
download() {
	curl --fail --location --silent --show-error --retry 3 --retry-delay 2 -o "$1" "$2"
}

# head_commit — full 40-character SHA of HEAD.
head_commit() {
	local commit
	commit="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
	[[ "${commit}" =~ ${SHA_PATTERN} ]] || fail "HEAD is not a 40-character SHA: ${commit}"
	printf '%s\n' "${commit}"
}

# commit_timestamp COMMIT — committer timestamp in strict ISO 8601 (RFC 3339).
# Build metadata uses the commit time, never the wall clock.
commit_timestamp() {
	git -C "${REPO_ROOT}" show -s --format=%cI "$1"
}

# source_url — HTTPS URL of the origin remote. Converts the common GitHub SSH
# forms to HTTPS and drops a trailing .git.
source_url() {
	local remote
	remote="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null)" ||
		fail "git remote 'origin' is not configured"
	case "${remote}" in
	git@github.com:*) remote="https://github.com/${remote#git@github.com:}" ;;
	ssh://git@github.com/*) remote="https://github.com/${remote#ssh://git@github.com/}" ;;
	esac
	remote="${remote%.git}"
	[[ "${remote}" =~ ^https://[^[:space:]]+$ ]] || fail "cannot normalize origin URL: ${remote}"
	printf '%s\n' "${remote}"
}

# file_size FILE — size in bytes (GNU and BSD stat).
file_size() {
	stat -c %s "$1" 2>/dev/null || stat -f %z "$1"
}
