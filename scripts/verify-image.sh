#!/usr/bin/env bash
# Runs an image with a hardened runtime and checks its identity.
#
# Usage: verify-image.sh IMAGE EXPECTED_VERSION EXPECTED_COMMIT EXPECTED_BUILT_AT EXPECTED_SOURCE_URL
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 5 ]] || fail "usage: verify-image.sh IMAGE EXPECTED_VERSION EXPECTED_COMMIT EXPECTED_BUILT_AT EXPECTED_SOURCE_URL"
image="$1"
expected_version="$2"
expected_commit="$3"
expected_built_at="$4"
expected_source="$5"

[[ "${expected_commit}" =~ ${SHA_PATTERN} ]] || fail "expected commit is not a 40-character SHA: ${expected_commit}"

container="secure-container-release-smoke-$$"
started=false
cleanup() {
	if [[ "${started}" == true ]]; then
		docker rm -f "${container}" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT INT TERM

log "Image configuration: ${image}"
user="$(docker image inspect "${image}" --format '{{.Config.User}}')"
[[ "${user}" == "65532:65532" ]] || fail "Config.User is '${user}', expected 65532:65532"
pass "Config.User = 65532:65532"

label() {
	docker image inspect "${image}" --format "{{ index .Config.Labels \"org.opencontainers.image.$1\" }}"
}
check_label() {
	local name="$1" expected="$2" actual
	actual="$(label "${name}")"
	[[ "${actual}" == "${expected}" ]] || fail "label org.opencontainers.image.${name} is '${actual}', expected '${expected}'"
	info "org.opencontainers.image.${name} = ${actual}"
}
check_label title "Secure Container Release"
check_label version "${expected_version}"
check_label revision "${expected_commit}"
check_label created "${expected_built_at}"
check_label source "${expected_source}"
check_label licenses "Apache-2.0"
pass "OCI labels match"

log "Hardened runtime"
docker run --detach --name "${container}" \
	--read-only \
	--cap-drop ALL \
	--security-opt no-new-privileges:true \
	--publish 127.0.0.1::8080 \
	"${image}" >/dev/null
started=true

host_port="$(docker port "${container}" 8080/tcp 2>/dev/null | awk -F: '$1 == "127.0.0.1" { print $NF; exit }' || true)"
[[ "${host_port}" =~ ^[0-9]+$ ]] || fail "container port 8080 is not published on 127.0.0.1"
base="http://127.0.0.1:${host_port}"

inspect_field() {
	docker inspect "${container}" --format "$1"
}
[[ "$(inspect_field '{{.HostConfig.ReadonlyRootfs}}')" == "true" ]] || fail "root filesystem is not read-only"
[[ "$(inspect_field '{{json .HostConfig.CapDrop}}')" == '["ALL"]' ]] || fail "capabilities are not dropped"
inspect_field '{{json .HostConfig.SecurityOpt}}' | grep -q 'no-new-privileges:true' || fail "no-new-privileges is not set"
pass "read-only root filesystem, capabilities dropped, no-new-privileges, bound to 127.0.0.1"

log "Health"
health=""
deadline=$((SECONDS + 15))
while ((SECONDS < deadline)); do
	if health="$(curl --silent --fail --max-time 2 "${base}/healthz")"; then
		break
	fi
	if [[ "$(inspect_field '{{.State.Running}}')" != "true" ]]; then
		docker logs "${container}" >&2 || true
		fail "container exited before becoming healthy"
	fi
	health=""
	sleep 0.25
done
[[ -n "${health}" ]] || fail "/healthz did not return 200 within 15s"
jq -e '.status == "ok"' <<<"${health}" >/dev/null || fail "/healthz returned unexpected body: ${health}"
pass "/healthz -> 200 {\"status\":\"ok\"}"

log "Version identity"
body="$(curl --silent --fail --max-time 5 "${base}/version")" || fail "/version did not return 200"
jq -e . <<<"${body}" >/dev/null || fail "/version did not return valid JSON"
actual_version="$(jq -r '.version' <<<"${body}")"
actual_commit="$(jq -r '.commit' <<<"${body}")"
actual_built_at="$(jq -r '.builtAt' <<<"${body}")"
[[ "${actual_version}" == "${expected_version}" ]] || fail "version is '${actual_version}', expected '${expected_version}'"
[[ "${actual_commit}" =~ ${SHA_PATTERN} ]] || fail "commit '${actual_commit}' is not a 40-character SHA"
[[ "${actual_commit}" == "${expected_commit}" ]] || fail "commit is '${actual_commit}', expected '${expected_commit}'"
[[ "${actual_built_at}" == "${expected_built_at}" ]] || fail "builtAt is '${actual_built_at}', expected '${expected_built_at}'"
info "version = ${actual_version}"
info "commit  = ${actual_commit}"
info "builtAt = ${actual_built_at}"
pass "runtime identity matches"

container_user="$(docker top "${container}" -o uid 2>/dev/null | awk 'NR == 2 { print $1 }' || true)"
if [[ -n "${container_user}" ]]; then
	[[ "${container_user}" == "65532" ]] || fail "process runs as UID ${container_user}, expected 65532"
	pass "process runs as UID 65532"
fi

pass "image verified: ${image}"
