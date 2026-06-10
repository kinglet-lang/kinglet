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

if ! "$BOOTSTRAP" --native "$ROOT/.kinglet/out/.driver_probe" "$ROOT/tests/native/cases/just42.kl" \
  2>"$ROOT/.kinglet/.driver_probe.err"; then
  if grep -q 'native backend not built' "$ROOT/.kinglet/.driver_probe.err" 2>/dev/null; then
    echo "SKIP native driver smoke: bootstrap built without enable_llvm=true" >&2
    exit 0
  fi
  echo "native driver probe failed:" >&2
  cat "$ROOT/.kinglet/.driver_probe.err" >&2
  exit 1
fi
rm -f "$ROOT/.kinglet/out/.driver_probe" "$ROOT/.kinglet/.driver_probe.err"

if ! "$ROOT/kinglet" build --backend native --quiet 2>&1; then
  echo "FAIL driver smoke: kinglet build --backend native" >&2
  exit 1
fi

if [[ ! -x "$COMPILER" ]]; then
  echo "FAIL driver smoke: missing $COMPILER" >&2
  exit 1
fi

out=$("$COMPILER" --check "$CASE" 2>&1) || {
  echo "FAIL driver smoke: compiler --check exit $?" >&2
  echo "$out" >&2
  exit 1
}

if [[ "$out" != "OK: no type errors" ]]; then
  echo "FAIL driver smoke: unexpected output: $out" >&2
  exit 1
fi

echo "Native driver smoke passed."
