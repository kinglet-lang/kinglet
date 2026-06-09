#!/usr/bin/env bash
# Build the C++ bootstrap kinglet compiler (checkout expected at $BOOTSTRAP_ROOT).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP_ROOT="${BOOTSTRAP_ROOT:-$ROOT/bootstrap}"
OUT_DIR="${BOOTSTRAP_OUT:-$BOOTSTRAP_ROOT/out/Default}"

if [[ ! -f "$BOOTSTRAP_ROOT/BUILD.gn" ]]; then
  echo "bootstrap sources not found at $BOOTSTRAP_ROOT (set BOOTSTRAP_ROOT)" >&2
  exit 1
fi

export PATH="${HOME}/bin:${PATH}"

cd "$BOOTSTRAP_ROOT"
gn gen "$OUT_DIR" --args='is_debug=false'
ninja -C "$OUT_DIR" kinglet

BIN="$OUT_DIR/kinglet"
if [[ ! -x "$BIN" ]]; then
  echo "bootstrap build failed: $BIN missing" >&2
  exit 1
fi

echo "$BIN"
