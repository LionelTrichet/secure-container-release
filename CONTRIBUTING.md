# Contributing

## Requirements

- Go 1.27.x
- Docker with Buildx
- git, curl, jq and make

For full security verification:

- Trivy 0.74.0
- Syft 1.51.1

`make doctor` checks the base requirements; `scripts/require-security-tools.sh` checks Trivy and Syft.

## Before Opening a Pull Request

```bash
make check
```

Recommended:

```bash
make verify-local
```

## Rules

Changes must not add, without a new specification:

- a paid dependency;
- a cloud requirement;
- a new external Go library;
- a committed secret;
- a mutable Action tag;
- a new registry;
- a new architecture;
- a new deployment system.

Every Action reference must be a full commit SHA from the allowlist in `scripts/verify-action-pins.sh`, followed by its version comment.

## Commits

Use short conventional prefixes such as `feat:`, `fix:`, `test:`, `ci:`, `security:`, `docs:` and `chore:`.
