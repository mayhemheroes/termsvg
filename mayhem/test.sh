#!/usr/bin/env bash
#
# termsvg/mayhem/test.sh — RUN termsvg's OWN Go test suite (go test ./...) and emit a
# CTRF summary. exit 0 iff no test failed.
#
# PATCH-grade oracle: termsvg's suite asserts behaviour, not "exits 0" — the color
# catalog tests assert index mappings and palette contents, the ir tests assert frame
# capture/deduplication semantics, the raster tests assert pixel-level draw results,
# and the svg/gif/webm renderer tests assert rendered output structure and content
# against expected values. A no-op / exit(0) patch that breaks parse/process/render
# FAILS these assertions.
#
# Anti-reward-hack (SPEC §6.3): pure-Go test binaries and the `go` tool are statically
# linked (LD_PRELOAD can't intercept them), so we run the suite through the thin
# dynamically-linked C shim mayhem-build/test-runner built by build.sh. A sabotage
# LD_PRELOAD _exit(0) intercepts the shim before it exec()s → no test output → the
# oracle counts differ → sabotage detected.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SRC:=/mayhem}"
export PATH="/opt/toolchains/go/bin:/opt/toolchains/go-path/bin:/usr/local/bin:/usr/bin:/bin"
export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"
export GOMODCACHE="${GOMODCACHE:-/opt/toolchains/go-path/pkg/mod}"
export GOCACHE="${GOCACHE:-/opt/toolchains/go-path/build-cache}"
export GOPROXY="${GOPROXY:-file://${GOMODCACHE}/cache/download,https://proxy.golang.org,direct}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER="$SRC/mayhem-build/test-runner"
JSON="$SRC/mayhem-build/gotest.json"
mkdir -p "$SRC/mayhem-build"

if [ -x "$RUNNER" ]; then
  echo "=== running: test-runner (go test -json -count=1 ./... shim, interceptable by LD_PRELOAD) ==="
  "$RUNNER" > "$JSON" 2>"$SRC/mayhem-build/gotest.err"; rc=$?
  grep -v '"Action":"output"' "$JSON" 2>/dev/null | python3 -c '
import sys, json
for line in sys.stdin:
    try:
        ev = json.loads(line.strip())
        if ev.get("Action") in ("pass","fail","skip") and ev.get("Test"):
            print(ev["Action"].upper(), ev.get("Test",""))
    except: pass
' 2>/dev/null | tail -40 || true
  [ -s "$SRC/mayhem-build/gotest.err" ] && { echo "--- stderr ---"; tail -5 "$SRC/mayhem-build/gotest.err"; }
elif command -v go >/dev/null 2>&1; then
  echo "=== running: go test -json -count=1 ./... (fallback) ==="
  go test -count=1 -json ./... > "$JSON" 2>"$SRC/mayhem-build/gotest.err"; rc=$?
  [ -s "$SRC/mayhem-build/gotest.err" ] && { echo "--- stderr ---"; tail -5 "$SRC/mayhem-build/gotest.err"; }
else
  echo "neither test-runner nor go available — cannot run the test suite" >&2
  emit_ctrf "go-test" 0 1 0; exit 2
fi

# Count test-level events (non-empty "Test" field). Subtests included — real asserted cases.
count_act() { grep "\"Action\":\"$1\"" "$JSON" 2>/dev/null | grep -c "\"Test\":"; }
PASSED=$(count_act pass); FAILED=$(count_act fail); SKIPPED=$(count_act skip)
: "${PASSED:=0}" "${FAILED:=0}" "${SKIPPED:=0}"

if [ "$(( PASSED + FAILED + SKIPPED ))" -eq 0 ]; then
  echo "no test events parsed; treating as failure (suite must run)" >&2
  emit_ctrf "go-test" 0 1 0; exit 1
fi

# Trust the parsed failures; if go exited non-zero but we counted 0 failures (e.g. a
# package build error), force a failure so the oracle stays honest.
if [ "$rc" -ne 0 ] && [ "$FAILED" -eq 0 ]; then FAILED=1; fi

emit_ctrf "go-test" "$PASSED" "$FAILED" "$SKIPPED"
