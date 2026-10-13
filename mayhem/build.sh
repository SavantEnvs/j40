#!/usr/bin/env bash
#
# mayhem/build.sh — build the j40 fuzz target and the functional oracle.
#
# j40 is a single-header (j40.h) JPEG XL decoder with no external deps beyond libm.
# We build:
#   /mayhem/j40-fuzz             sanitized libFuzzer harness  -> the Mayhem target
#   /mayhem/j40-fuzz-standalone  same harness + run-once driver (repro artifact)
#   build-oracle/dj40            normal-flags decoder CLI     -> mayhem/test.sh KAT oracle
# No network, no upstream edits — everything comes from the upstream tree.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the environment (base image exports the defaults); fall back for a bare run.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "${SRC:-/mayhem}"

HARNESS=mayhem/harnesses/j40_fuzz.c

# 1) Sanitized libFuzzer target — the DECODER ITSELF is instrumented (j40.h is header-only, so
#    compiling the harness compiles the whole project with $SANITIZER_FLAGS). -O1 keeps frames
#    readable for triage; $DEBUG_FLAGS after the sanitizer flags so -gdwarf-3 wins (DWARF < 4).
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE -O1 "$HARNESS" -lm -o j40-fuzz

# 2) Standalone (non-fuzzer) run-once reproducer for the same harness.
if [ -n "${STANDALONE_FUZZ_MAIN:-}" ]; then
  # shellcheck disable=SC2086
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
  # shellcheck disable=SC2086
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS -O1 "$HARNESS" /tmp/standalone_main.o -lm -o j40-fuzz-standalone
fi

# 3) Clean oracle build (NO sanitizers) of upstream's dj40 decoder CLI (dj40.c, the Makefile's
#    default target) so mayhem/test.sh is an honest known-answer oracle. -O2 is pinned so the
#    committed golden PNG hash stays byte-stable. $COVERAGE_FLAGS is empty by default.
mkdir -p build-oracle
# shellcheck disable=SC2086
$CC -O2 -Wc++-compat $COVERAGE_FLAGS dj40.c -lm -o build-oracle/dj40

echo "build.sh: built j40-fuzz (sanitized), j40-fuzz-standalone, build-oracle/dj40 (oracle)"
