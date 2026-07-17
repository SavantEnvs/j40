#!/usr/bin/env bash
#
# mayhem/test.sh — functional oracle for j40. Upstream ships NO test suite (no unit tests, no
# CI test job), so this is an AUTHORED known-answer oracle: it RUNS the prebuilt clean decoder
# (build-oracle/dj40 from mayhem/build.sh) on a committed JPEG XL sample and asserts the decoded
# output byte-matches a committed golden PNG — a behavioral KAT, not an exit-code check. A PATCH
# that neuters the decoder to exit(0) produces no/empty output and FAILS here (anti-reward-hack).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "${SRC:-/mayhem}"

BIN=build-oracle/dj40
INPUT=mayhem/j40-fuzz/testsuite/1.jxl
GOLDEN=mayhem/golden/1.png
OUT=/tmp/j40_oracle.png
LOG=/tmp/j40_oracle.log
passed=0; failed=0

check() { # <name> <condition-rc>
  if [ "$2" -eq 0 ]; then echo "  ok   - $1"; passed=$((passed+1))
  else echo "  FAIL - $1"; failed=$((failed+1)); fi
}

# emit_ctrf <tool> <passed> <failed> [skipped]
emit_ctrf() {
  local tool="$1" p="$2" f="$3" s="${4:-0}"
  local tests=$(( p + f + s ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": { "tests": $tests, "passed": $p, "failed": $f, "pending": 0, "skipped": $s, "other": 0 }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":0,"skipped":%d,"other":0}}}\n' \
    "$tool" "$tests" "$p" "$f" "$s"
  [ "$f" -eq 0 ]
}

if [ ! -x "$BIN" ]; then
  echo "test.sh: $BIN missing — build.sh must build it (not rebuilding here)" >&2
  emit_ctrf j40-kat 0 1; exit 1
fi

rm -f "$OUT"
"$BIN" "$INPUT" "$OUT" >"$LOG" 2>&1
rc=$?

# 1) decode succeeds and reports the sample's true geometry (809x864).
if [ "$rc" -eq 0 ] && grep -q "809x864 frame read." "$LOG"; then check "dj40 decodes 1.jxl as an 809x864 frame" 0
else check "dj40 decodes 1.jxl as an 809x864 frame" 1; fi

# 2) decoded PNG byte-matches the committed golden (known-answer).
if [ -f "$OUT" ] && cmp -s "$OUT" "$GOLDEN"; then check "decoded PNG matches golden ($GOLDEN)" 0
else check "decoded PNG matches golden ($GOLDEN)" 1; fi

# 3) a truncated stream is rejected with a decode error (no silent success, no output).
head -c 300 "$INPUT" > /tmp/j40_trunc.jxl
if "$BIN" /tmp/j40_trunc.jxl /tmp/j40_trunc.png >"$LOG" 2>&1; then check "truncated input is rejected with an error" 1
else grep -q "Error:" "$LOG"; check "truncated input is rejected with an error" $?; fi

# 4) garbage (non-JXL) input is rejected with a decode error.
printf 'this is not a jxl file at all............' > /tmp/j40_junk.jxl
if "$BIN" /tmp/j40_junk.jxl /tmp/j40_junk.png >"$LOG" 2>&1; then check "garbage input is rejected with an error" 1
else grep -q "Error:" "$LOG"; check "garbage input is rejected with an error" $?; fi

echo "test.sh: passed=$passed failed=$failed"
emit_ctrf j40-kat "$passed" "$failed"
