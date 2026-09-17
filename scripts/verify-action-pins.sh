#!/usr/bin/env bash
# Every external Action must be one of the allowlisted full-SHA pins with its
# matching version comment. A 40-character regex alone is not enough.
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

allowlist() {
	cat <<'PINS'
actions/checkout 3d3c42e5aac5ba805825da76410c181273ba90b1 v7.0.1
actions/setup-go b7ad1dad31e06c5925ef5d2fc7ad053ef454303e v7.0.0
docker/setup-buildx-action 37fe631027851001ddb9b187196cc803df7f5f0e v4.3.0
docker/login-action dbcb813823bdd20940b903addbd779551569679f v4.6.0
actions/attest 1e69f48acb82d1966a394da916b4c1698aa569d6 v4.2.2
sigstore/cosign-installer 6f9f17788090df1f26f669e9d70d6ae9567deba6 v4.1.2
PINS
}

workflows=("${REPO_ROOT}"/.github/workflows/*.yml)
[[ -e "${workflows[0]}" ]] || fail "no workflow files found"

checked=0
failures=0
for workflow in "${workflows[@]}"; do
	while IFS= read -r line; do
		reference="$(sed -E 's/^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*//; s/[[:space:]]*#.*$//' <<<"${line}")"
		comment=""
		if [[ "${line}" == *"#"* ]]; then
			comment="$(sed -E 's/^[^#]*#[[:space:]]*//; s/[[:space:]]+$//' <<<"${line}")"
		fi
		action="${reference%@*}"
		ref="${reference#*@}"
		checked=$((checked + 1))

		if [[ "${reference}" != *"@"* ]] ||
			! allowlist | awk -v a="${action}" -v r="${ref}" -v c="${comment}" \
				'$1 == a && $2 == r && $3 == c { found = 1 } END { exit !found }'; then
			printf 'FAIL: %s: not an allowlisted pin: %s # %s\n' \
				"${workflow#"${REPO_ROOT}"/}" "${reference}" "${comment:-<no version comment>}" >&2
			failures=$((failures + 1))
		fi
	done < <(grep -E '^[[:space:]]*-?[[:space:]]*uses:' "${workflow}")
done

((checked > 0)) || fail "no Action references found"
((failures == 0)) || fail "${failures} Action reference(s) are not allowlisted"
pass "${checked} Action references match the full-SHA allowlist"
