#!/usr/bin/env bash
# Static Dockerfile policy.
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dockerfile="${REPO_ROOT}/Dockerfile"
[[ -f "${dockerfile}" ]] || fail "Dockerfile not found"

readonly EXPECTED_BUILDER='FROM golang:1.27.1-bookworm@sha256:648f440f42a0958804efb24df176f806f9d353b41f1c0627f666428e40310f6b AS builder'
readonly EXPECTED_RUNTIME='FROM gcr.io/distroless/static-debian13:nonroot@sha256:f7f8f729987ad0fdf6b05eeeae94b26e6a0f613bdf46feea7fc40f7bd72953e6'

mapfile -t from_lines < <(grep -E '^FROM[[:space:]]' "${dockerfile}")
[[ "${#from_lines[@]}" -eq 2 ]] || fail "expected exactly 2 FROM lines, found ${#from_lines[@]}"
[[ "${from_lines[0]}" == "${EXPECTED_BUILDER}" ]] || fail "builder FROM is not the pinned image: ${from_lines[0]}"
[[ "${from_lines[1]}" == "${EXPECTED_RUNTIME}" ]] || fail "runtime FROM is not the pinned image: ${from_lines[1]}"
pass "builder and runtime images pinned by digest"

grep -Fxq 'USER 65532:65532' "${dockerfile}" || fail "USER 65532:65532 is missing"
pass "USER 65532:65532"

grep -Fxq 'ENTRYPOINT ["/app/server"]' "${dockerfile}" || fail 'ENTRYPOINT ["/app/server"] is missing'
pass "entrypoint exact"

if grep -Eiq ':latest([[:space:]@]|$)' "${dockerfile}"; then
	fail "Dockerfile references a latest tag"
fi
if grep -Eiq '^[[:space:]]*HEALTHCHECK' "${dockerfile}"; then
	fail "Dockerfile defines HEALTHCHECK"
fi
if grep -Eq '^[[:space:]]*COPY[[:space:]]+\.[[:space:]]+\.' "${dockerfile}"; then
	fail "Dockerfile uses COPY . ."
fi
pass "no latest tag, no HEALTHCHECK, no COPY . ."
