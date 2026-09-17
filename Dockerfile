# Both base images are pinned by digest. No syntax directive: it would pull an
# unpinned Dockerfile frontend image.

FROM golang:1.27.1-bookworm@sha256:648f440f42a0958804efb24df176f806f9d353b41f1c0627f666428e40310f6b AS builder

ARG VERSION
ARG COMMIT
ARG BUILT_AT

WORKDIR /src

COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal

ENV CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    GOTOOLCHAIN=local

# The module path comes from go.mod, so no account name is hardcoded here.
RUN test -n "${VERSION}" && test -n "${COMMIT}" && test -n "${BUILT_AT}" \
 && module="$(go list -m)" \
 && go build -trimpath -buildvcs=false \
      -ldflags "-s -w -X ${module}/internal/version.Version=${VERSION} -X ${module}/internal/version.Commit=${COMMIT} -X ${module}/internal/version.BuiltAt=${BUILT_AT}" \
      -o /app/server ./cmd/server

FROM gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3

ARG VERSION
ARG COMMIT
ARG BUILT_AT
ARG SOURCE_URL

LABEL org.opencontainers.image.title="Secure Container Release" \
      org.opencontainers.image.description="Minimal workload for a verifiable OCI release pipeline." \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${COMMIT}" \
      org.opencontainers.image.created="${BUILT_AT}" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.licenses="Apache-2.0"

COPY --from=builder /app/server /app/server

USER 65532:65532

EXPOSE 8080

ENTRYPOINT ["/app/server"]
