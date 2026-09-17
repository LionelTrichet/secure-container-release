# Architecture

## Purpose

Build one OCI image and prove that the exact published immutable digest passed quality and vulnerability gates, has an SPDX SBOM, has verifiable build provenance and carries a verifiable keyless signature.

## System Boundary

The repository contains a minimal Go workload, its Dockerfile, verification scripts and two GitHub Actions workflows. Everything that produces or verifies a release runs on GitHub-hosted `ubuntu-24.04` runners.

External services involved in a release: GitHub Actions, GitHub Container Registry, the GitHub Attestations API, Sigstore (Fulcio, Rekor, TUF), the Trivy vulnerability database and GitHub release hosting. There is no cloud account, no self-hosted runner and no deployment.

## Pull Request Trust Boundary

Pull requests, including those from forks, run `ci.yml` with `permissions: contents: read`. They receive no secrets, no OIDC token and no package or attestation permission. Checkout does not persist credentials. `pull_request_target` is not used, and no pull request metadata is interpolated into shell code.

## CI Flow

```text
quality:   make check
container: pinned Buildx + BuildKit → build (version "ci", commit under test)
           → hardened runtime check → Trivy gate → SPDX SBOM → SBOM contract
```

`container` depends on `quality`. Neither job logs in to a registry, pushes, signs or attests.

## Release Flow

```text
tag v0.1.0 (lightweight, == main HEAD)
  → make check
  → build once → LOCAL_IMAGE_ID
  → runtime check → Trivy report → CRITICAL gate → SBOM → SBOM contract
  → GHCR login → push → registry digest
  → remove local image → pull by digest → REMOTE_IMAGE_ID == LOCAL_IMAGE_ID
  → runtime check by digest
  → provenance attestation → SBOM attestation → Cosign sign
  → Cosign verify → provenance verify → SBOM attestation verify
  → release-manifest.json → SHA256SUMS → verify-release.sh
  → draft GitHub Release with assets → publish
```

Publication of the GitHub Release is the last automated step. Nothing is committed back to the repository after a release.

## Build-Once Model

The release job builds the image exactly once with `docker buildx build --load`, tagging it `ghcr.io/lioneltrichet/secure-container-release:v0.1.0`. The runtime check, the vulnerability gate and the SBOM all read that same local image. The push publishes that same image. There is no rebuild anywhere after the build step.

## Image Identity

| Field | Source |
|-------|--------|
| version | tag without the leading `v`, required to equal `APP_VERSION` |
| commit | full 40-character SHA of the tag commit |
| builtAt | `git show -s --format=%cI` of that commit |
| source | `https://github.com/LionelTrichet/secure-container-release` |

The same values are injected with `-ldflags -X`, written as OCI labels and returned by `/version`. The Go module path comes from `go list -m`, so no account name is hardcoded in the build.

Local builds use version `dev` and CI builds use version `ci`, both with the real commit and commit timestamp.

## Runtime Verification

`scripts/verify-image.sh` checks an image reference against expected version, commit, timestamp and source:

- `Config.User` is `65532:65532`;
- the title, version, revision, created, source and licenses labels match;
- the container runs with `--read-only`, `--cap-drop ALL` and `--security-opt no-new-privileges:true`, published on `127.0.0.1` only;
- `/healthz` returns `200` with status `ok` within 15 seconds, polled every 250 ms;
- `/version` returns exactly the expected version, commit and timestamp.

The container name includes the script's process ID and cleanup removes only that container.

## Vulnerability Gate

`scripts/scan-image.sh` runs Trivy twice against the image: a HIGH and CRITICAL report that always exits 0, then a CRITICAL scan that exits 1 on any finding. Unfixed vulnerabilities count. A `.trivyignore` file makes the script fail.

## SBOM Generation

`scripts/generate-sbom.sh` runs Syft against the local image in the Docker daemon and writes SPDX 2.3 JSON. `scripts/verify-sbom.sh` checks the SPDX 2.3 contract and a size below 16 MiB.

## Registry Publication

The job logs in to GHCR with `docker/login-action` and `GITHUB_TOKEN`, then runs `docker push` for the built tag. Only the tag `v0.1.0` is published.

## Digest Boundary

After the push, the registry digest is read from the image's `RepoDigests` and validated as `ghcr.io/lioneltrichet/secure-container-release@sha256:<64 hex>`. From that point every check targets the digest reference, never the tag.

The local image is removed and the job confirms it is gone before pulling by digest, so the comparison cannot pass against a cached copy. The pulled image ID must equal the ID recorded after the build. This comparison has been exercised against both the containerd image store, where the ID is the manifest digest, and the classic image store, where it is the image config digest; it holds in both.

## GitHub Provenance

`actions/attest` with `subject-name` set to the repository without a tag, `subject-digest` set to the digest and `push-to-registry: true` produces a build provenance attestation. Storage records are disabled with `create-storage-record: false`, so no `artifact-metadata` permission is granted.

## SBOM Attestation

A second, independent `actions/attest` step with `sbom-path: dist/sbom.spdx.json` attaches the SPDX document to the same digest.

## Sigstore Signing

`cosign sign --yes` signs the digest reference. Fulcio issues a short-lived certificate for the workflow's OIDC identity and the signature is recorded in Rekor. No key is generated, stored or passed in.

## Verification Strategy

Inside the release job:

- `cosign verify` with the exact certificate identity, OIDC issuer, workflow repository, workflow ref, workflow commit and `push` trigger;
- `gh attestation verify` for provenance and, with the SPDX 2.3 predicate type, for the SBOM, both constrained to the repository as source and signer, the release workflow, the tag ref, the tag commit and GitHub-hosted runners;
- `scripts/verify-release.sh`, which repeats the runtime, signature and attestation checks and validates the SBOM, the manifest values against the verified release and `SHA256SUMS`.

`release-manifest.json` is generated with `jq -n` and must not contain empty or null values. `SHA256SUMS` lists the manifest and the SBOM, sorted.

## Permission Model

| Workflow | Permissions |
|----------|-------------|
| `ci.yml` | `contents: read` |
| `release.yml` | `contents: write`, `packages: write`, `id-token: write`, `attestations: write` |

The release job holds these permissions only for the `v0.1.0` tag push. Registry login stays active until verification finishes.

## External Trust Dependencies

- GitHub-hosted runners, the Actions pinned by full SHA and `GITHUB_TOKEN`.
- GitHub's OIDC issuer and Sigstore's Fulcio, Rekor and TUF root.
- GHCR and the GitHub Attestations API.
- Docker Hub and `gcr.io` for the digest-pinned base images, and Docker Hub for the digest-pinned BuildKit image.
- GitHub release downloads for Trivy and Syft, verified through checksum files whose own hashes are pinned.
- The Trivy vulnerability database, which changes over time.

## Failure Model

- Any failure before the push stops the release with nothing published.
- Any failure after the push fails the workflow and no GitHub Release is published. The image, tag, signature and attestations are not deleted, so they can be inspected.
- An existing published release is never overwritten. A draft left by a failed run is deleted and recreated; the Git tag is kept.
- Upstream outages fail the release. Downloads retry up to three times; there is no other retry mechanism. The release can be rerun after recovery.

## Non-Goals

Kubernetes, Helm, Terraform, cloud deployment, multiple architectures, multiple registries, GitOps, policy engines, additional scanners, runtime monitoring, staging, rollout and rollback automation, private signing keys, KMS and self-hosted runners are out of scope.
