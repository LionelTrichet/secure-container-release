#!/usr/bin/env bash
# Installs the exact Trivy and Syft releases after verifying the checksum file
# itself against build/versions.env and the archive against the checksum file.
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

install_dir="${INSTALL_DIR:-/usr/local/bin}"
work_dir="$(mktemp -d)"
cleanup() { rm -rf "${work_dir}"; }
trap cleanup EXIT INT TERM

install_binary() {
	if [[ -w "${install_dir}" ]]; then
		install -m 0755 "$1" "${install_dir}/$2"
	else
		sudo install -m 0755 "$1" "${install_dir}/$2"
	fi
}

# verify_release TOOL BASE_URL CHECKSUM_FILE EXPECTED_FILE_SHA ARCHIVE
verify_release() {
	local tool="$1" base="$2" checksums="$3" expected="$4" archive="$5" actual line
	download "${work_dir}/${checksums}" "${base}/${checksums}"
	actual="$(sha256sum "${work_dir}/${checksums}" | awk '{ print $1 }')"
	[[ "${actual}" == "${expected}" ]] ||
		fail "${tool} checksum file SHA-256 ${actual} does not match build/versions.env"

	line="$(awk -v name="${archive}" '$2 == name || $2 == "*" name' "${work_dir}/${checksums}")"
	[[ -n "${line}" && "$(printf '%s\n' "${line}" | wc -l)" -eq 1 ]] ||
		fail "${tool} checksum file has no single entry for ${archive}"

	download "${work_dir}/${archive}" "${base}/${archive}"
	(cd "${work_dir}" && printf '%s\n' "${line}" | sha256sum -c --strict --quiet) ||
		fail "${tool} archive checksum mismatch"
	info "${tool} archive checksum verified"
}

log "Trivy ${TRIVY_VERSION}"
trivy_archive="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
verify_release trivy \
	"https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}" \
	"trivy_${TRIVY_VERSION}_checksums.txt" "${TRIVY_CHECKSUM_FILE_SHA256}" "${trivy_archive}"
tar -xzf "${work_dir}/${trivy_archive}" -C "${work_dir}" trivy
install_binary "${work_dir}/trivy" trivy

log "Syft ${SYFT_VERSION}"
syft_archive="syft_${SYFT_VERSION}_linux_amd64.tar.gz"
verify_release syft \
	"https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}" \
	"syft_${SYFT_VERSION}_checksums.txt" "${SYFT_CHECKSUM_FILE_SHA256}" "${syft_archive}"
tar -xzf "${work_dir}/${syft_archive}" -C "${work_dir}" syft
install_binary "${work_dir}/syft" syft

"$(dirname "${BASH_SOURCE[0]}")/require-security-tools.sh"
