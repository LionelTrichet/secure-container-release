SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := check

LOCAL_IMAGE := secure-container-release:local

.PHONY: doctor fmt-check unit build verify-action-pins verify-dockerfile \
	verify-versions check image smoke scan sbom verify-sbom verify-local clean

doctor:
	@scripts/doctor.sh

fmt-check:
	@test -z "$$(gofmt -l cmd internal)" || { printf 'FAIL: gofmt:\n'; gofmt -l cmd internal; exit 1; }
	@printf 'PASS: gofmt\n'

unit:
	go test ./...

build:
	go build ./cmd/server
	@printf 'PASS: native build\n'

verify-action-pins:
	@scripts/verify-action-pins.sh

verify-dockerfile:
	@scripts/verify-dockerfile.sh

verify-versions:
	@scripts/verify-versions.sh

check: fmt-check
	go vet ./...
	@$(MAKE) --no-print-directory unit
	@$(MAKE) --no-print-directory build
	@$(MAKE) --no-print-directory verify-action-pins
	@$(MAKE) --no-print-directory verify-dockerfile
	@$(MAKE) --no-print-directory verify-versions
	bash -n scripts/*.sh
	@printf 'PASS: make check\n'

image:
	@bash -c '. scripts/lib.sh && \
		commit="$$(head_commit)" && \
		built_at="$$(commit_timestamp "$$commit")" && \
		source="$$(source_url)" && \
		log "Building $(LOCAL_IMAGE) (commit $$commit)" && \
		BUILDX_NO_DEFAULT_ATTESTATIONS=1 docker buildx build \
			--platform linux/amd64 \
			--provenance=false \
			--sbom=false \
			--load \
			--build-arg VERSION=dev \
			--build-arg "COMMIT=$$commit" \
			--build-arg "BUILT_AT=$$built_at" \
			--build-arg "SOURCE_URL=$$source" \
			--tag "$(LOCAL_IMAGE)" \
			. && \
		pass "image built: $(LOCAL_IMAGE)"'

smoke:
	@bash -c '. scripts/lib.sh && \
		commit="$$(head_commit)" && \
		scripts/verify-image.sh "$(LOCAL_IMAGE)" dev "$$commit" "$$(commit_timestamp "$$commit")" "$$(source_url)"'

scan:
	@scripts/scan-image.sh "$(LOCAL_IMAGE)"

sbom:
	@scripts/generate-sbom.sh "$(LOCAL_IMAGE)"

verify-sbom:
	@scripts/verify-sbom.sh

verify-local:
	@$(MAKE) --no-print-directory check
	@scripts/require-security-tools.sh
	@$(MAKE) --no-print-directory image
	@$(MAKE) --no-print-directory smoke
	@$(MAKE) --no-print-directory scan
	@$(MAKE) --no-print-directory sbom
	@$(MAKE) --no-print-directory verify-sbom
	@printf 'PASS: make verify-local\n'

clean:
	rm -rf dist server
	@docker image rm "$(LOCAL_IMAGE)" >/dev/null 2>&1 || true
	@printf 'PASS: clean\n'
