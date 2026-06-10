#!/usr/bin/env bash
# Build bootstrap kinglet with LLVM native backend enabled.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP_ROOT="${BOOTSTRAP_ROOT:-$ROOT/bootstrap}"
OUT_DIR="${BOOTSTRAP_OUT:-$BOOTSTRAP_ROOT/out/Default}"

if [[ ! -f "$BOOTSTRAP_ROOT/BUILD.gn" ]]; then
  echo "bootstrap sources not found at $BOOTSTRAP_ROOT (set BOOTSTRAP_ROOT)" >&2
  exit 1
fi

export PATH="${HOME}/bin:${PATH}"

LLVM_CONFIG="${LLVM_CONFIG:-}"
if [[ -z "$LLVM_CONFIG" ]]; then
  for candidate in \
    /opt/homebrew/opt/llvm/bin/llvm-config \
    /usr/local/opt/llvm/bin/llvm-config; do
    if [[ -x "$candidate" ]]; then
      LLVM_CONFIG="$candidate"
      break
    fi
  done
fi
if [[ -z "$LLVM_CONFIG" ]] && command -v llvm-config >/dev/null 2>&1; then
  LLVM_CONFIG="$(command -v llvm-config)"
fi
if [[ -z "$LLVM_CONFIG" || ! -x "$LLVM_CONFIG" ]]; then
  echo "llvm-config not found; install LLVM or set LLVM_CONFIG" >&2
  exit 1
fi

cd "$BOOTSTRAP_ROOT"
gn gen "$OUT_DIR" --args="is_debug=false enable_llvm=true llvm_config=\"$LLVM_CONFIG\""
ninja -C "$OUT_DIR" kinglet kinglet_rt

BIN="$OUT_DIR/kinglet"
if [[ ! -x "$BIN" ]]; then
  echo "bootstrap LLVM build failed: $BIN missing" >&2
  exit 1
fi

echo "$BIN"
