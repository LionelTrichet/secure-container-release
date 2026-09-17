# Secure Container Release

**Verifiable OCI release pipeline with GitHub Actions, vulnerability scanning, SPDX SBOM, provenance and keyless signing.**

Secure Container Release is a compact reference repository for building and verifying an OCI image with GitHub Actions.

A successful registry push is not considered a release. The pipeline verifies the workload, scans the exact image, generates an SPDX SBOM, publishes that same image, attests and signs its immutable digest, then independently verifies the published artifact before creating a GitHub Release.

## Why

A registry tag proves that an object exists. It does not prove which source produced it, whether that exact artifact passed the expected security checks or whether its release identity can be independently verified.

## What This Proves

- GitHub Actions least-privilege permissions
- fork-safe pull request CI
- immutable full-SHA Action pins
- exact tool version control
- digest-pinned build inputs
- non-root distroless runtime
- read-only runtime compatibility
- capability-free workload
- build-once release semantics
- Trivy vulnerability gating
- SPDX 2.3 SBOM generation
- GHCR publication through `GITHUB_TOKEN`
- immutable registry digest handling
- GitHub provenance attestation
- GitHub SBOM attestation
- Sigstore OIDC keyless signing
- Cosign identity verification
- post-publication artifact verification

## Release Flow

```text
main HEAD ─▶ lightweight tag v0.1.0 ─▶ validate tag == current main
  ─▶ make check
  ─▶ build one linux/amd64 image with pinned Buildx and BuildKit ─▶ save LOCAL_IMAGE_ID
  ─▶ hardened runtime check ─▶ Trivy HIGH report ─▶ Trivy CRITICAL gate
  ─▶ Syft SPDX 2.3 SBOM ─▶ SBOM contract
  ─▶ GHCR login with GITHUB_TOKEN ─▶ push the same image ─▶ capture registry digest
  ─▶ pull by digest ─▶ REMOTE_IMAGE_ID == LOCAL_IMAGE_ID ─▶ runtime check by digest
  ─▶ provenance attestation ─▶ SPDX SBOM attestation ─▶ Cosign keyless signature
  ─▶ Cosign identity verification ─▶ provenance and SBOM attestation verification
  ─▶ release-manifest.json ─▶ SHA256SUMS ─▶ verify-release.sh
  ─▶ GitHub Release v0.1.0
```

Nothing reaches the registry until quality, runtime, vulnerability and SBOM checks have passed on the exact image that will be pushed.

## Architecture

- **Workload** — a Go service using only the standard library. It serves `GET /healthz` and `GET /version` on port 8080. `/version` returns the version, full commit SHA and commit timestamp injected at link time.
- **Image** — a multi-stage build from `golang:1.27.1-bookworm` into `gcr.io/distroless/static-debian13:nonroot`, both pinned by digest. It runs as UID `65532`, with no shell, no package manager and no writable filesystem requirement.
- **CI** (`.github/workflows/ci.yml`) — pull requests and pushes to `main`, read-only permissions, no registry access.
- **Release** (`.github/workflows/release.yml`) — runs only for the `v0.1.0` tag and is the only workflow with write, OIDC and attestation permissions.
- **Scripts** (`scripts/`) — the verification logic used by `make`, CI and the release workflow.

See [ARCHITECTURE.md](ARCHITECTURE.md).

## Stack

| Component | Version |
|-----------|---------|
| Go | 1.27.1 (standard library only) |
| Docker Buildx | 0.37.0 |
| BuildKit | 0.33.0, pinned by digest |
| Trivy | 0.74.0 |
| Syft | 1.51.1 |
| Cosign | 3.1.3 |
| Runner | `ubuntu-24.04` |

| Action | Version | Pinned SHA |
|--------|---------|------------|
| `actions/checkout` | v7.0.1 | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/setup-go` | v7.0.0 | `b7ad1dad31e06c5925ef5d2fc7ad053ef454303e` |
| `docker/setup-buildx-action` | v4.3.0 | `37fe631027851001ddb9b187196cc803df7f5f0e` |
| `docker/login-action` | v4.6.0 | `dbcb813823bdd20940b903addbd779551569679f` |
| `actions/attest` | v4.2.2 | `1e69f48acb82d1966a394da916b4c1698aa569d6` |
| `sigstore/cosign-installer` | v4.1.2 | `6f9f17788090df1f26f669e9d70d6ae9567deba6` |

Tool versions and checksum-file hashes live in [`build/versions.env`](build/versions.env).

## Quick Start

Requirements: Go 1.27.x, Docker with Buildx, git, curl, jq and make.

```bash
make doctor
make check
make image
make smoke
```

Full security verification also needs Trivy 0.74.0 and Syft 1.51.1:

```bash
make verify-local
```

## Local Verification

| Target | What it does |
|--------|--------------|
| `make check` | gofmt, `go vet`, unit tests, native build, Action pin allowlist, Dockerfile policy, version consistency, `bash -n` |
| `make image` | builds `secure-container-release:local` for `linux/amd64` with version `dev`, the current HEAD commit, its commit timestamp and the origin URL |
| `make smoke` | runs the image read-only, with all capabilities dropped and `no-new-privileges`, bound to `127.0.0.1`, and checks labels, health and version identity |
| `make scan` | Trivy HIGH and CRITICAL report, then a CRITICAL gate |
| `make sbom` | Syft SPDX 2.3 JSON SBOM of the local image into `dist/sbom.spdx.json` |
| `make verify-sbom` | SPDX 2.3 contract and size limit |
| `make verify-local` | all of the above in order |
| `make clean` | removes `dist/`, the native binary and the local image |

## Pull Request CI

`ci.yml` runs on pull requests and on pushes to `main`, with `permissions: contents: read` and no secrets, so pull requests from forks run the same checks without write access.

- **quality** — `make check`.
- **container** — builds the image with version `ci` and the commit under test, verifies the hardened runtime, runs the Trivy gate, generates and verifies the SBOM.

CI never logs in to a registry, pushes, signs or attests.

## Release Pipeline

`release.yml` runs only when the lightweight tag `v0.1.0` is pushed. Its permissions are exactly `contents: write`, `packages: write`, `id-token: write` and `attestations: write`.

The owner releases with:

```bash
git switch main
git pull --ff-only
git tag v0.1.0
git push origin v0.1.0
```

The workflow refuses an annotated tag, a tag that does not point to the current `main` HEAD, and any other tag. The release commit is the tag commit; the build timestamp is that commit's timestamp, not the build time.

If any verification fails after the push, the workflow fails and no GitHub Release is published. The image, tag, signature and attestations are left in place for diagnosis. A published release is never overwritten; a draft left by a failed run is replaced.

## Build-Once Guarantee

The release image is built exactly once. The same local image is checked at runtime, scanned, used for the SBOM and then pushed.

After the push the workflow removes the local image, pulls it back by registry digest and requires the pulled image ID to equal the ID recorded right after the build. The runtime identity check then runs again against the digest.

## Container Hardening

- Non-root: `USER 65532:65532`, verified from the image configuration.
- Distroless static runtime: no shell, no package manager.
- Runs with `--read-only`, `--cap-drop ALL` and `--security-opt no-new-privileges:true`.
- Local checks publish the port on `127.0.0.1` only.
- Static binary: `CGO_ENABLED=0`, `-trimpath`, `-buildvcs=false`.
- No `HEALTHCHECK`: the image has no tool to run one. Health is checked from outside.

## Vulnerability Policy

Trivy first prints a HIGH and CRITICAL report without failing, then fails on any CRITICAL vulnerability. Unfixed vulnerabilities are not ignored, and there is no `.trivyignore`.

A previously passing image can fail later when the vulnerability database gains new findings. The repository intentionally treats this as expected scanner behavior rather than suppressing findings for reproducibility.

## SBOM

Syft generates an SPDX 2.3 JSON SBOM from the exact image that is released, never from a rebuild. The contract requires valid JSON, `spdxVersion` `SPDX-2.3`, `SPDXID` `SPDXRef-DOCUMENT`, a non-empty name and document namespace, `creationInfo`, at least one package, and a size below 16 MiB.

## Provenance

`actions/attest` creates a build provenance attestation for the image digest and pushes it to the registry. A second, independent `actions/attest` step creates an SPDX SBOM attestation for the same digest. Both use `create-storage-record: false`.

The workflow verifies both with `gh attestation verify`, constrained to this repository as source and signer, the release workflow, the tag ref, the tag commit and GitHub-hosted runners.

## Keyless Signing

`cosign sign` signs the digest using the workflow's GitHub OIDC identity through Sigstore. There is no private key anywhere.

Verification requires the exact certificate identity `https://github.com/LionelTrichet/secure-container-release/.github/workflows/release.yml@refs/tags/v0.1.0`, the issuer `https://token.actions.githubusercontent.com`, and the workflow repository, ref, commit and `push` trigger. No wildcard identity is accepted.

## Verify a Published Release

The canonical digest and identities are recorded in `release-manifest.json`, attached to the `v0.1.0` GitHub Release. Nothing needs to be copied from this README.

```bash
repo="LionelTrichet/secure-container-release"

gh release download v0.1.0 --repo "$repo" --pattern 'release-manifest.json' --pattern 'SHA256SUMS' --pattern 'sbom.spdx.json'
sha256sum -c SHA256SUMS

image="$(jq -r .imageReference release-manifest.json)"
identity="$(jq -r .cosignIdentity release-manifest.json)"
commit="$(jq -r .commit release-manifest.json)"

docker pull "$image"

cosign verify "$image" \
  --certificate-identity "$identity" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-github-workflow-repository "$repo" \
  --certificate-github-workflow-ref refs/tags/v0.1.0 \
  --certificate-github-workflow-sha "$commit"

gh attestation verify "oci://$image" \
  --repo "$repo" \
  --signer-workflow "$repo/.github/workflows/release.yml" \
  --source-ref refs/tags/v0.1.0 \
  --source-digest "$commit" \
  --deny-self-hosted-runners

gh attestation verify "oci://$image" \
  --repo "$repo" \
  --signer-workflow "$repo/.github/workflows/release.yml" \
  --source-ref refs/tags/v0.1.0 \
  --source-digest "$commit" \
  --predicate-type https://spdx.dev/Document/v2.3 \
  --deny-self-hosted-runners
```

`gh attestation verify` needs an authenticated GitHub CLI.

## GHCR Visibility

GitHub Container Registry creates the first package as private by default. After the initial verified release, the package owner must change the package visibility to Public once so the published digest can be pulled anonymously.

This is a manual step and is not automated: **Profile → Packages → secure-container-release → Package settings → Danger Zone → Change visibility → Public**. After that, pulling by digest works without logging in:

```bash
docker logout ghcr.io || true
docker pull "$(jq -r .imageReference release-manifest.json)"
```

## Repository Structure

```text
cmd/server/            process entry point: HTTP server, signals, shutdown
internal/server/       /healthz and /version handlers
internal/version/      link-time build metadata
build/versions.env     pinned tool versions and checksum-file hashes
scripts/               verification, scanning, SBOM and release scripts
.github/workflows/     ci.yml and release.yml
.github/dependabot.yml weekly updates for Actions and Docker base images
Dockerfile             digest-pinned multi-stage build
```

## Security Boundary

- Pull request CI has read-only permissions and no secrets.
- Only the release workflow can write contents and packages, request an OIDC token and create attestations.
- Registry authentication uses the short-lived `GITHUB_TOKEN`. No personal access token, no custom secret, no signing key.
- Every Action is pinned to an allowlisted full SHA, enforced by `scripts/verify-action-pins.sh`.
- Trivy and Syft are installed only after their checksum files and archives are verified.

See [SECURITY.md](SECURITY.md).

## Operational Limitations

- Releases depend on public infrastructure: GitHub Actions, GHCR, the GitHub Attestations API, Sigstore Fulcio, Rekor and TUF, the Trivy vulnerability database, and GitHub release hosting. A temporary outage can fail a release; rerun it after recovery.
- Docker Engine and the GitHub CLI come from the `ubuntu-24.04` runner image and are not pinned in this repository.
- Builds use pinned inputs, but the release is not claimed to be bit-for-bit reproducible.
- A single `linux/amd64` image and the single tag `v0.1.0`.
- Artifact attestations on a personal account require a public repository.

## What This Is / Is Not

Secure Container Release is a compact reference implementation of a verifiable OCI release workflow using GitHub Actions, GHCR, vulnerability scanning, SPDX SBOMs, attestations and keyless signing.

| It is | It is not |
|-------|-----------|
| a verifiable release of one OCI image | an enterprise software supply chain |
| a reference for least-privilege GitHub Actions | a complete DevSecOps platform |
| a build-once, verify-by-digest pattern | a production deployment platform |
| provenance, SBOM attestation and keyless signing | SLSA certified or fully reproducible |

## Development

```bash
make check          # before every pull request
make verify-local   # full local security verification
```

Unit tests cover the handlers with `httptest`, the method policy (`405` with `Allow: GET`), unknown routes and injected build metadata. The module has no external dependencies, so there is no `go.sum`.

## Upstream References

- [Go](https://go.dev/doc/)
- [Security hardening for GitHub Actions](https://docs.github.com/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [GitHub Packages: Container registry](https://docs.github.com/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [GitHub artifact attestations](https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations)
- [`gh attestation verify`](https://cli.github.com/manual/gh_attestation_verify)
- [Docker Buildx](https://docs.docker.com/build/)
- [Moby BuildKit](https://github.com/moby/buildkit)
- [Trivy](https://trivy.dev/)
- [Syft](https://github.com/anchore/syft)
- [SPDX](https://spdx.dev/)
- [Sigstore](https://docs.sigstore.dev/)
- [Cosign](https://github.com/sigstore/cosign)
- [Distroless](https://github.com/GoogleContainerTools/distroless)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
