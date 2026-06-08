#!/usr/bin/env bash
# Self-hosting round-trip / fixed-point test.
#
# Validates self-hosting integrity:
# 1. S2 = compiler.kbc compiles core/main.kl
# 2. S3 = S2 compiles itself
# 3. S4 = S3 compiles itself
# 4. Assert S3 == S4 (fixed-point: selfhosted compiler bytecode is stable)
#
# Bootstrap compiler.kbc (C++ output) and S2 (first VM self-compile) may
# differ in size; byte-identical bootstrap parity is tracked separately.
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
S4_KBC="$TMP_DIR/S4.kbc"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

compile_stage() {
  local label="$1" from_kbc="$2" to_kbc="$3" err_file="$4"
  echo "$label"
  echo "  Running: run_kbc $(basename "$from_kbc") --save-bytecode $(basename "$to_kbc") core/main.kl"
  if ! run_with_timeout "$COMPILE_TIMEOUT" "$KINGLET_BIN" --run "$from_kbc" --save-bytecode \
      "$to_kbc" "$ENTRY" 2>"$err_file"; then
    echo "FAIL: $label failed (timeout ${COMPILE_TIMEOUT}s or VM error)" >&2
    cat "$err_file" >&2
    exit 1
  fi
  if [[ ! -s "$to_kbc" ]]; then
    echo "FAIL: $(basename "$to_kbc") not produced" >&2
    cat "$err_file" >&2
    exit 1
  fi
  echo "  $(basename "$to_kbc"): $(stat -c%s "$to_kbc" 2>/dev/null || stat -f%z "$to_kbc") bytes"
}

echo "=== Self-hosting round-trip test ==="
echo

compile_stage "Step 1: S2 = compiler.kbc compiles itself" "$CLI_KBC" "$S2_KBC" "$TMP_DIR/s2.err"
echo
compile_stage "Step 2: S3 = S2 compiles itself" "$S2_KBC" "$S3_KBC" "$TMP_DIR/s3.err"
echo
compile_stage "Step 3: S4 = S3 compiles itself" "$S3_KBC" "$S4_KBC" "$TMP_DIR/s4.err"

echo
echo "Step 4: Fixed-point check (S3 == S4)"
if cmp -s "$S3_KBC" "$S4_KBC"; then
  echo "  ✓ S3 == S4 (fixed-point reached)"
else
  echo "  ✗ FAIL: S3 != S4" >&2
  cmp "$S3_KBC" "$S4_KBC" 2>&1 || true
  exit 1
fi

echo
echo "Step 5: Bootstrap parity (informational)"
bs_size=$(stat -c%s "$CLI_KBC" 2>/dev/null || stat -f%z "$CLI_KBC")
s2_size=$(stat -c%s "$S2_KBC" 2>/dev/null || stat -f%z "$S2_KBC")
s3_size=$(stat -c%s "$S3_KBC" 2>/dev/null || stat -f%z "$S3_KBC")
if cmp -s "$CLI_KBC" "$S3_KBC"; then
  echo "  ✓ compiler.kbc == S3 (bootstrap byte-identical)"
elif cmp -s "$CLI_KBC" "$S2_KBC"; then
  echo "  ✓ compiler.kbc == S2 (bootstrap byte-identical)"
else
  echo "  ~ compiler.kbc=${bs_size}B  S2=${s2_size}B  S3=${s3_size}B (bootstrap delta tracked separately)"
fi

echo
echo "=== Round-trip test PASSED ==="
echo "Self-hosting integrity verified:"
echo "  - S2 and S3 generation succeed"
echo "  - Fixed-point: S3 == S4"
