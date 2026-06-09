#!/usr/bin/env bash
# Explicit kbc emission for debugging (ADR 0014 M2).
#
# Usage:
#   kinglet-debug-emit-kbc.sh [--shadow] <out.kbc> <src.kl> [project_root]
#
#   --shadow   compile via self-host compiler.kbc (VM host)
#   (default)  compile via bootstrap Ref compiler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

ENGINE="ref"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --shadow)
      ENGINE="shadow"
      shift
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 2 ]]; then
  echo "usage: kinglet debug emit-kbc [--shadow] <out.kbc> <src.kl>" >&2
  exit 2
fi

OUT="$1"
SRC="$2"
shift 2

ROOT="${1:-}"
if [[ -z "$ROOT" ]]; then
  ROOT=$(find_project_root "$(pwd)") || {
    echo "kinglet debug emit-kbc: no kinglet.toml found" >&2
    exit 2
  }
fi
ROOT=$(cd "$ROOT" && pwd)

if [[ ! -f "$SRC" ]]; then
  if [[ -f "$ROOT/$SRC" ]]; then
    SRC="$ROOT/$SRC"
  else
    echo "kinglet debug emit-kbc: source not found: $SRC" >&2
    exit 2
  fi
fi
SRC=$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")

OUT_DIR=$(dirname "$OUT")
if [[ "$OUT_DIR" != "." && "$OUT_DIR" != ".." ]]; then
  mkdir -p "$OUT_DIR"
fi

# shellcheck source=/dev/null
source "$ROOT/tests/common.sh"
export_kinglet_bins "$ROOT" || exit 2

if [[ "$ENGINE" == "ref" ]]; then
  exec "$KINGLET_BOOTSTRAP" --save-bytecode "$OUT" "$SRC"
fi

CLI_KBC=$(ensure_build_stamp "$ROOT") || exit 2
exec "$KINGLET_BIN" --run "$CLI_KBC" --save-bytecode "$OUT" "$SRC"
