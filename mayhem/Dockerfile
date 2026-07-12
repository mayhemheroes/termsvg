# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form) — builds ON TOP of the org C/C++ base image
# (ghcr.io/mayhemheroes/base). termsvg is a pure-Go project, so the base (C/C++ only)
# needs Go added as a USER root step, plus the OSS-Fuzz Go fuzzing tooling
# (go-118-fuzz-build) that turns the native Go fuzz harness into a libFuzzer binary.
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] \
#       -t termsvg-commit:test .

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); never bake it as ENV — an empty
# value breaks clang. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH

# The OSS-Fuzz Go path is ASan-only; build.sh handles the Go specifics.
ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

# termsvg's go.mod requires go >= 1.25.6; pin a matching stable release by version + sha256.
ARG GO_VERSION=1.25.12
ARG GO_SHA256=234828b7a89e0e303d2556310ee549fbcf253d28de937bac3da13d6294262ac1

# ── Go toolchain @ a FIXED, lockable, $HOME-independent prefix ─────────────────────────
# SPEC §6.2 item 8 + §6.5: commit build and PATCH re-run run under different $HOMEs.
# Pinning GOROOT/GOPATH/GOMODCACHE/GOCACHE under /opt/toolchains ensures the module cache
# populated during the first (online) image build is found again by the offline re-run.
ENV GOROOT=/opt/toolchains/go \
    GOPATH=/opt/toolchains/go-path \
    GOMODCACHE=/opt/toolchains/go-path/pkg/mod \
    GOCACHE=/opt/toolchains/go-path/build-cache \
    GOTOOLCHAIN=local \
    GOFLAGS=-mod=mod \
    PATH=/opt/toolchains/go/bin:/opt/toolchains/go-path/bin:/usr/local/bin:/usr/bin:/bin

USER root
RUN repro-sources-list.sh 2>/dev/null || true; \
    apt-get update && apt-get install -yq --no-install-recommends wget ca-certificates git ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && install -d /opt/toolchains/go-path \
    && wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tgz \
    && echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - \
    && tar -C /opt/toolchains -xzf /tmp/go.tgz && rm /tmp/go.tgz \
    && go version \
    && go install github.com/AdamKorcz/go-118-fuzz-build@latest \
    && ls -la "$(go env GOPATH)/bin" \
    && chmod -R a+rX /opt/toolchains/go \
    && chown -R 2000:2000 /opt/toolchains/go-path \
    && go clean -cache 2>/dev/null || true

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git
# history) is copied to /mayhem; build.sh builds in place.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

# Run termsvg's own Go test suite at build time (a failing suite fails the image build).
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
