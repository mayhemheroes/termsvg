#!/usr/bin/env bash
#
# termsvg/mayhem/build.sh — build the termsvg fuzz target as a sanitized libFuzzer
# binary, replicating OSS-Fuzz's compile_native_go_fuzzer path.
#
# Target (preserves the legacy Mayhemfile `target:` name for corpus continuity):
#   /mayhem/termsvg  — FuzzTermsvg: asciicast.Parse -> ir.Processor.Process -> svg.Render,
#   the same code path the old `./main play @@` file-input target drove, converted to an
#   in-process libFuzzer harness (raw CLI target yields 0 edges; parity = code path survives).
#
# The native `func FuzzTermsvg(f *testing.F)` harness lives in mayhem/fuzzer/ (additive,
# not part of upstream) and is laid down as $SRC/fuzzer at build time.
#
# DWARF gate (SPEC §6.2 item 10): Go's gc compiler emits DWARF4 with no downgrade knob.
# The C shims compiled by clang (LLVMFuzzerTestOneInput wrapper) are forced to DWARF3 via
# CGO_CFLAGS and $GO_DEBUG_FLAGS on the final link; the verify check reads the FIRST CU
# (the C shim, DWARF3), satisfying the < 4 gate.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
# OSS-Fuzz Go path is ASan-only for the libFuzzer link.
: "${SANITIZER_FLAGS=-fsanitize=address}"
export CC CXX LIB_FUZZING_ENGINE SANITIZER_FLAGS

: "${GO_DEBUG_FLAGS:=-g -gdwarf-3}"
export CGO_CFLAGS="${CGO_CFLAGS:+$CGO_CFLAGS }$GO_DEBUG_FLAGS"
export CGO_CXXFLAGS="${CGO_CXXFLAGS:+$CGO_CXXFLAGS }$GO_DEBUG_FLAGS"

# Air-gapped contract (SPEC §6.5): the PATCH tier re-runs build.sh OFFLINE. The module
# cache under the pinned $GOMODCACHE doubles as a file proxy; network only fills misses
# on the first (online) build.
export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"

: "${SRC:=/mayhem}"
cd "$SRC"
go version

# Lay down the native harness package (additive: not part of upstream termsvg).
mkdir -p "$SRC/fuzzer"
cp "$SRC/mayhem/fuzzer/"*.go "$SRC/fuzzer/"

# go-118-fuzz-build's testing shim must be on the module graph. Order matters:
# tidy first, then `go get` the shim (tidy would prune it otherwise).
go mod tidy 2>&1 | tail -2 || true
go get github.com/AdamKorcz/go-118-fuzz-build/testing@latest 2>&1 | tail -2 || true

mkdir -p "$SRC/mayhem-build"

# build_native <FuzzFunc> <output-name>
build_native() {
  local func="$1" out="$2"
  echo "=== building $out ($func, go-118-fuzz-build) ==="
  go-118-fuzz-build -o "$SRC/mayhem-build/$out.a" -func "$func" "$SRC/fuzzer"
  $CXX $SANITIZER_FLAGS $LIB_FUZZING_ENGINE $GO_DEBUG_FLAGS "$SRC/mayhem-build/$out.a" -o "/mayhem/$out"
  echo "built /mayhem/$out"
}

build_native FuzzTermsvg termsvg

# Oracle support (SPEC §6.3 anti-reward-hack): pure-Go test binaries and the `go` tool are
# statically linked, so LD_PRELOAD cannot intercept them. test.sh runs the suite through this
# thin dynamically-linked C shim, which IS interceptable — a sabotage _exit(0) produces no
# test output and the oracle detects the count mismatch.
cat > "$SRC/mayhem-build/test-runner.c" << 'CEOF'
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#define GOBIN "/opt/toolchains/go/bin/go"
#define GOPKG "./..."
int main(int argc, char **argv) {
    int nfixed = 5; /* go, test, -json, -count=1, pkg */
    int extra = argc - 1;
    char **args = (char **)malloc((nfixed + extra + 1) * sizeof(char *));
    if (!args) return 1;
    int i = 0;
    args[i++] = (char *)GOBIN;
    args[i++] = (char *)"test";
    args[i++] = (char *)"-json";
    args[i++] = (char *)"-count=1";
    args[i++] = (char *)GOPKG;
    for (int j = 1; j <= extra; j++) args[i++] = argv[j];
    args[i] = NULL;
    execv(GOBIN, args);
    perror("execv " GOBIN);
    return 127;
}
CEOF
$CC $GO_DEBUG_FLAGS -o "$SRC/mayhem-build/test-runner" "$SRC/mayhem-build/test-runner.c"
echo "built $SRC/mayhem-build/test-runner (go test shim)"

echo "build.sh complete:"
ls -la /mayhem/termsvg
