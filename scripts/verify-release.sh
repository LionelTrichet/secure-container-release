#!/usr/bin/env bash
# Independent verification of a published release by its registry digest.
#
# Usage: verify-release.sh IMAGE_DIGEST_REF EXPECTED_VERSION EXPECTED_COMMIT \
#          EXPECTED_BUILT_AT EXPECTED_SOURCE_URL EXPECTED_REPOSITORY EXPECTED_REF
#
# Expects dist/release-manifest.json, dist/sbom.spdx.json and dist/SHA256SUMS.
# gh must be authenticated through GH_TOKEN; registry access must already work.
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 7 ]] || fail "usage: verify-release.sh IMAGE_DIGEST_REF EXPECTED_VERSION EXPECTED_COMMIT EXPECTED_BUILT_AT EXPECTED_SOURCE_URL EXPECTED_REPOSITORY EXPECTED_REF"
image_ref="$1"
expected_version="$2"
expected_commit="$3"
expected_built_at="$4"
expected_source="$5"
expected_repository="$6"
expected_ref="$7"

readonly OIDC_ISSUER="https://token.actions.githubusercontent.com"
readonly SPDX_PREDICATE="https://spdx.dev/Document/v2.3"

require_command cosign
require_command gh

[[ "${expected_commit}" =~ ${SHA_PATTERN} ]] || fail "expected commit is not a 40-character SHA"
[[ "${expected_ref}" == refs/tags/* ]] || fail "expected ref is not a tag ref: ${expected_ref}"
image_repository="${image_ref%@*}"
image_digest="${image_ref#*@}"
[[ "${image_ref}" == *"@"* && "${image_digest}" =~ ${DIGEST_PATTERN} ]] ||
	fail "image reference is not <repository>@sha256:<64 hex>: ${image_ref}"
expected_image_repository="$(printf 'ghcr.io/%s' "${expected_repository}" | tr '[:upper:]' '[:lower:]')"
[[ "${image_repository}" == "${expected_image_repository}" ]] ||
	fail "image repository is ${image_repository}, expected ${expected_image_repository}"
cosign_identity="https://github.com/${expected_repository}/.github/workflows/release.yml@${expected_ref}"
signer_workflow="${expected_repository}/.github/workflows/release.yml"

log "Remote runtime by digest"
"${REPO_ROOT}/scripts/verify-image.sh" "${image_ref}" \
	"${expected_version}" "${expected_commit}" "${expected_built_at}" "${expected_source}"

log "Cosign keyless signature"
cosign verify \
	--certificate-identity "${cosign_identity}" \
	--certificate-oidc-issuer "${OIDC_ISSUER}" \
	--certificate-github-workflow-repository "${expected_repository}" \
	--certificate-github-workflow-ref "${expected_ref}" \
	--certificate-github-workflow-sha "${expected_commit}" \
	--certificate-github-workflow-trigger "push" \
	"${image_ref}" >/dev/null
pass "signature identity ${cosign_identity}"

log "GitHub provenance attestation"
gh attestation verify "oci://${image_ref}" \
	--repo "${expected_repository}" \
	--signer-repo "${expected_repository}" \
	--signer-workflow "${signer_workflow}" \
	--source-ref "${expected_ref}" \
	--source-digest "${expected_commit}" \
	--deny-self-hosted-runners >/dev/null
pass "provenance attestation verified"

log "GitHub SBOM attestation"
gh attestation verify "oci://${image_ref}" \
	--repo "${expected_repository}" \
	--signer-repo "${expected_repository}" \
	--signer-workflow "${signer_workflow}" \
	--source-ref "${expected_ref}" \
	--source-digest "${expected_commit}" \
	--predicate-type "${SPDX_PREDICATE}" \
	--deny-self-hosted-runners >/dev/null
pass "SPDX SBOM attestation verified"

log "SBOM"
"${REPO_ROOT}/scripts/verify-sbom.sh" "${DIST_DIR}/sbom.spdx.json"

log "Release manifest"
manifest="${DIST_DIR}/release-manifest.json"
[[ -f "${manifest}" ]] || fail "release manifest not found"
jq -e '[.. | select(. == null)] | length == 0' "${manifest}" >/dev/null || fail "release manifest contains null values"
sbom_sha="$(sha256sum "${DIST_DIR}/sbom.spdx.json" | awk '{ print $1 }')"
tag="${expected_ref#refs/tags/}"
jq -e \
	--arg version "${expected_version}" \
	--arg tag "${tag}" \
	--arg commit "${expected_commit}" \
	--arg built_at "${expected_built_at}" \
	--arg image "${image_repository}" \
	--arg digest "${image_digest}" \
	--arg reference "${image_ref}" \
	--arg source "${expected_source}" \
	--arg identity "${cosign_identity}" \
	--arg workflow_prefix "${signer_workflow}@${expected_ref}" \
	--arg sbom_sha "${sbom_sha}" '
	.version == $version
	and .gitTag == $tag
	and .commit == $commit
	and .builtAt == $built_at
	and .image == $image
	and .digest == $digest
	and .imageReference == $reference
	and .source == $source
	and .workflowRef == $workflow_prefix
	and .cosignIdentity == $identity
	and .sbom == "sbom.spdx.json"
	and .sbomSha256 == $sbom_sha
	and (.localImageId | test("^sha256:[a-f0-9]{64}$"))
	and (.provenanceAttestationUrl | test("^https://"))
	and (.sbomAttestationUrl | test("^https://"))
	and (.workflowRun | test("^https://github.com/.+/actions/runs/[0-9]+$"))
' "${manifest}" >/dev/null || fail "release manifest does not match the verified release"
pass "release manifest matches"

log "Checksums"
expected_sums="$(cd "${DIST_DIR}" && sha256sum release-manifest.json sbom.spdx.json | LC_ALL=C sort -k2)"
[[ "$(cat "${DIST_DIR}/SHA256SUMS")" == "${expected_sums}" ]] || fail "SHA256SUMS does not list exactly the manifest and SBOM"
(cd "${DIST_DIR}" && sha256sum -c --strict SHA256SUMS >/dev/null) || fail "SHA256SUMS verification failed"
pass "SHA256SUMS verified"

pass "release verified: ${image_ref}"
