#!/usr/bin/env bash
# L4 driver smoke: native toolchain binary from kinglet build runs --check.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tests/common.sh
source "$ROOT/tests/common.sh"

BOOTSTRAP=$(resolve_bootstrap "$ROOT") || exit 2
export KINGLET_BOOTSTRAP="$BOOTSTRAP"

CASE="$ROOT/tests/native/cases/io_line.kl"
COMPILER="$ROOT/.kinglet/out/compiler"
TMP_DIR="$(mktemp -d)"
PROBE_BIN="$TMP_DIR/driver_probe"
PROBE_ERR="$TMP_DIR/driver_probe.err"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! "$BOOTSTRAP" --native "$PROBE_BIN" "$ROOT/tests/native/cases/just42.kl" 2>"$PROBE_ERR"; then
  if grep -q 'native backend not built' "$PROBE_ERR" 2>/dev/null; then
    echo "SKIP native driver smoke: bootstrap built without enable_llvm=true" >&2
    exit 0
  fi
  echo "native driver probe failed:" >&2
  cat "$PROBE_ERR" >&2
  exit 1
fi

if ! "$ROOT/kinglet" build --backend native --quiet 2>&1; then
  echo "FAIL driver smoke: kinglet build --backend native" >&2
  exit 1
fi

if [[ ! -x "$COMPILER" ]]; then
  echo "FAIL driver smoke: missing $COMPILER" >&2
  exit 1
fi

# float_arith.kl exercises the scanner's float-literal parsing, which relies
# on native float arithmetic inside the driver itself.
for case_file in "$CASE" "$ROOT/tests/native/cases/float_arith.kl"; do
  out=$("$COMPILER" --check "$case_file" 2>&1) || {
    echo "FAIL driver smoke: compiler --check $case_file exit $?" >&2
    echo "$out" >&2
    exit 1
  }

  if [[ "$out" != "OK: no type errors" ]]; then
    echo "FAIL driver smoke: unexpected output for $case_file: $out" >&2
    exit 1
  fi
done

echo "Native driver smoke passed."
