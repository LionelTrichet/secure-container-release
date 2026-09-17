# Security

## Threat Model

| Threat | Control |
|--------|---------|
| Malicious fork pull request | CI has `contents: read`, no secrets, no OIDC token, no registry access |
| Malicious workflow modification | release runs only for the `v0.1.0` tag, which must point to the current `main` HEAD |
| Mutable Action tag | every Action is pinned to an allowlisted full SHA, enforced in `make check` |
| Over-privileged token | CI is read-only; only the release workflow gets write, OIDC and attestation permissions |
| Registry tag mutation | after the push every check uses the immutable digest, never the tag |
| Long-lived signing key theft | there is no signing key; signing is keyless through GitHub OIDC and Sigstore |
| Rebuild-after-scan artifact substitution | the image is built once; the pulled digest must have the same image ID as the tested build |
| Unverified runtime base | builder and runtime images are pinned by digest and checked by `verify-dockerfile.sh` |
| Vulnerable runtime package | Trivy fails the build on any CRITICAL vulnerability |
| Wrong source commit released | the tag must be lightweight and equal to `main` HEAD; commit and timestamp are verified at runtime |
| Attestation from the wrong workflow | `gh attestation verify` requires this repository, the release workflow, the tag ref, the tag commit and hosted runners |
| Signature from the wrong repository | `cosign verify` requires the exact workflow identity, issuer, repository, ref, commit and trigger |

## Pull Request Boundary

`ci.yml` runs on `pull_request` and on pushes to `main`. It never uses `pull_request_target`. Checkout runs with `persist-credentials: false`. The container job builds and scans locally but never logs in, pushes, signs or attests.

## GitHub Actions Trust

The repository trusts GitHub-hosted runners and six Actions. Docker Engine and the GitHub CLI are provided by the `ubuntu-24.04` runner image; each workflow prints their versions.

## Action SHA Pinning

Every `uses:` reference must match one allowlisted pair of full commit SHA and version comment. `scripts/verify-action-pins.sh` fails on a mutable tag, an unknown Action, an unlisted SHA or a mismatched version comment. Enabling the repository setting that requires full-SHA pins is recommended as an additional control.

## GITHUB_TOKEN Permissions

- `ci.yml`: `contents: read` at workflow level; no job elevates it.
- `release.yml`: exactly `contents: write`, `packages: write`, `id-token: write` and `attestations: write`. `artifact-metadata: write` is not granted because storage records are disabled.

The recommended repository default for workflow permissions is read-only.

## OIDC

Only the release job can request an OIDC token. Sigstore uses it to issue a short-lived signing certificate, and GitHub uses it for attestations. The token is never printed.

## Registry Authentication

GHCR login uses `GITHUB_TOKEN` through `docker/login-action`. No personal access token is used. Login stays active until verification finishes and is removed when the job ends.

## No Long-Lived Credentials

There are no custom repository secrets, no personal access tokens, no signing keys and no cloud credentials.

## Keyless Signing

`cosign sign` signs the image digest with a certificate bound to `https://github.com/LionelTrichet/secure-container-release/.github/workflows/release.yml@refs/tags/v0.1.0`. Verification never uses wildcard identities, `--insecure-ignore-tlog` or insecure registries. Signatures are recorded in the public Rekor transparency log, which permanently records the repository and workflow identity.

## Container Hardening

The runtime image is distroless and static: no shell, no package manager. It runs as UID `65532`, works with a read-only root filesystem, needs no Linux capabilities and needs no privilege escalation. Local and CI checks run it with `--read-only`, `--cap-drop ALL` and `--security-opt no-new-privileges:true`, bound to `127.0.0.1`.

## Base Image Pinning

`golang:1.27.1-bookworm` and `gcr.io/distroless/static-debian13:nonroot` are referenced by tag and digest. The digest decides what is pulled. Dependabot proposes base image updates weekly; an update changes the pinned digest in a reviewed pull request.

## BuildKit Pinning

CI and release set up Buildx 0.37.0 with the `docker-container` driver and `moby/buildkit:v0.33.0-ubuntu` pinned by digest. BuildKit's automatic provenance and SBOM are disabled; attestations come only from `actions/attest`.

## Vulnerability Policy

Trivy reports HIGH and CRITICAL findings and fails on any CRITICAL finding, including unfixed ones. Findings are never suppressed: there is no `.trivyignore`. A new CRITICAL finding in a pinned base image blocks the release until the base image is updated.

## Dynamic Vulnerability Data

A previously passing image can fail later when the vulnerability database gains new findings. The repository intentionally treats this as expected scanner behavior rather than suppressing findings for reproducibility.

## SBOM

The SBOM is SPDX 2.3 JSON generated by Syft from the exact released image, validated for structure and size, attached to the GitHub Release and attested to the image digest.

## Artifact Attestations

Build provenance and the SPDX SBOM are attested to the image digest with `actions/attest` and pushed to the registry. Attestations for a personal account require a public repository.

## Fork Pull Requests

A pull request from a fork runs the full quality and container checks with read-only permissions and without secrets. It cannot publish, sign or attest anything.

## Release Identity

A release is identified by the tag `v0.1.0`, the tag commit, the commit timestamp, the repository URL, the registry digest, the signing identity and the attestation URLs. All of them are recorded in `release-manifest.json` and verified before the GitHub Release is published.

## Known Limitations

- Docker Engine and the GitHub CLI on the runner are not pinned by this repository.
- The release is verifiable, not bit-for-bit reproducible.
- The workflows trust GitHub-hosted infrastructure, Sigstore's public-good instance and the upstream publishers of the pinned Actions, images and tools.
- The GHCR package must be made public manually once after the first release.

## Vulnerability Reporting

Please report security issues privately through GitHub's **Report a vulnerability** option on this repository instead of opening a public issue. Include the affected file or workflow and steps to reproduce.
