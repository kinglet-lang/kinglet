#!/usr/bin/env bash
# Self-hosting round-trip / fixed-point test.
#
# Proves the byte-identical self-hosting claim from AGENT.md:
# 1. S2 = selfhost compiles itself (compiler.kbc → S2.kbc)
# 2. S3 = S2 compiles itself (S2.kbc → S3.kbc)
# 3. Assert S2 == S3 (fixed-point: the compiler reaches a stable state)
# 4. Assert compiler.kbc == S2 (reproducibility: the toolchain reproduces itself)
#
# This is the ONLY automated test that validates self-hosting integrity.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT" || exit 2
CLI_KBC=$(ensure_cli_kbc "$ROOT") || exit 2

ENTRY="$ROOT/core/main.kl"
COMPILE_TIMEOUT="${KINGLET_COMPILE_TIMEOUT:-600}"
TMP_DIR="$(mktemp -d)"
S2_KBC="$TMP_DIR/S2.kbc"
S3_KBC="$TMP_DIR/S3.kbc"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "=== Self-hosting round-trip test ==="
echo

# S2 generation: selfhost (compiler.kbc) compiles itself
echo "Step 1: S2 = selfhost compiles itself"
echo "  Running: run_kbc compiler.kbc --save-bytecode S2.kbc core/main.kl"
if ! run_with_timeout "$COMPILE_TIMEOUT" "$KINGLET_BIN" --run "$CLI_KBC" --save-bytecode \
    "$S2_KBC" "$ENTRY" 2>"$TMP_DIR/s2.err"; then
  echo "FAIL: S2 generation failed (timeout ${COMPILE_TIMEOUT}s or VM error)" >&2
  cat "$TMP_DIR/s2.err" >&2
  exit 1
fi
if [[ ! -s "$S2_KBC" ]]; then
  echo "FAIL: S2.kbc not produced" >&2
  cat "$TMP_DIR/s2.err" >&2
  exit 1
fi
echo "  S2.kbc: $(stat -c%s "$S2_KBC" 2>/dev/null || stat -f%z "$S2_KBC") bytes"

# S3 generation: S2 compiles itself
echo
echo "Step 2: S3 = S2 compiles itself"
echo "  Running: run_kbc S2.kbc --save-bytecode S3.kbc core/main.kl"
if ! run_with_timeout "$COMPILE_TIMEOUT" "$KINGLET_BIN" --run "$S2_KBC" --save-bytecode \
    "$S3_KBC" "$ENTRY" 2>"$TMP_DIR/s3.err"; then
  echo "FAIL: S3 generation failed (timeout ${COMPILE_TIMEOUT}s or VM error)" >&2
  cat "$TMP_DIR/s3.err" >&2
  exit 1
fi
if [[ ! -s "$S3_KBC" ]]; then
  echo "FAIL: S3.kbc not produced" >&2
  cat "$TMP_DIR/s3.err" >&2
  exit 1
fi
echo "  S3.kbc: $(stat -c%s "$S3_KBC" 2>/dev/null || stat -f%z "$S3_KBC") bytes"

# Fixed-point check: S2 == S3
echo
echo "Step 3: Fixed-point check (S2 == S3)"
if cmp -s "$S2_KBC" "$S3_KBC"; then
  echo "  ✓ S2 == S3 (fixed-point reached)"
else
  echo "  ✗ FAIL: S2 != S3" >&2
  # Show byte-level diff for debugging
  if command -v cmp >/dev/null 2>&1; then
    cmp "$S2_KBC" "$S3_KBC" 2>&1 || true
  fi
  exit 1
fi

# Reproducibility check: compiler.kbc == S2
echo
echo "Step 4: Reproducibility check (compiler.kbc == S2)"
if cmp -s "$CLI_KBC" "$S2_KBC"; then
  echo "  ✓ compiler.kbc == S2 (toolchain reproduces itself)"
else
  echo "  ✗ FAIL: compiler.kbc != S2" >&2
  echo "  This means the cached compiler.kbc is out of sync." >&2
  echo "  Rebuild with: kinglet --save-bytecode compiler.kbc core/main.kl" >&2
  if command -v cmp >/dev/null 2>&1; then
    cmp "$CLI_KBC" "$S2_KBC" 2>&1 || true
  fi
  exit 1
fi

echo
echo "=== Round-trip test PASSED ==="
echo "Self-hosting integrity verified:"
echo "  - Fixed-point: S2 == S3"
echo "  - Reproducibility: compiler.kbc == S2"
