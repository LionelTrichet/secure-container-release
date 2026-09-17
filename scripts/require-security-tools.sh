#!/usr/bin/env bash
# Requires the exact pinned Trivy and Syft versions.
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_command trivy
require_command syft

trivy_version="$(trivy --version 2>/dev/null | awk '/^Version:/ { print $2; exit }')"
[[ "${trivy_version}" == "${TRIVY_VERSION}" ]] ||
	fail "Trivy ${TRIVY_VERSION} required, found '${trivy_version}'"
info "Trivy ${trivy_version}"

syft_version="$(syft version 2>/dev/null | awk '/^Version:/ { print $2; exit }')"
[[ "${syft_version}" == "${SYFT_VERSION}" ]] ||
	fail "Syft ${SYFT_VERSION} required, found '${syft_version}'"
info "Syft ${syft_version}"

pass "security tools pinned"
