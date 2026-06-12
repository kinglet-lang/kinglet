#!/usr/bin/env bash
# Build toolchain artefacts via Ref compiler + Klos (ADR 0014 M0).
#
# Usage:
#   build.sh [--quiet] [--backend native|vm] [project_root]
#   KINGLET_BOOTSTRAP=/path/to/kinglet build.sh
#
# Internal toolchain build (stamp/Klos). User-facing `kinglet build` uses the
# bootstrap binary; prove and tests call this script for cache semantics.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

QUIET=0
BACKEND=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet)
      QUIET=1
      shift
      ;;
    --backend)
      BACKEND="${2:-}"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

ROOT="${1:-}"
if [[ -z "$ROOT" ]]; then
  ROOT=$(find_project_root "$(pwd)") || {
    echo "kinglet build: no kinglet.toml found" >&2
    exit 2
  }
fi
ROOT=$(cd "$ROOT" && pwd)

# shellcheck source=/dev/null
source "$ROOT/tests/common.sh"
BOOTSTRAP=$(resolve_bootstrap "$ROOT") || exit 2

ENGINE=$(get_build_config "$ROOT" engine "ref")
if [[ "$ENGINE" != "ref" ]]; then
  echo "kinglet build: only engine=ref is supported in M0 (got $ENGINE)" >&2
  echo "Use kinglet prove for shadow builds." >&2
  exit 2
fi

if [[ -z "$BACKEND" ]]; then
  BACKEND=$(get_build_config "$ROOT" default_backend "vm")
fi

ensure_kinglet_dirs "$ROOT"

BUILD_ROOT=$(get_build_config "$ROOT" root "core/main.kl")
ENTRY="$ROOT/$BUILD_ROOT"
if [[ ! -f "$ENTRY" ]]; then
  echo "kinglet build: entry not found: $ENTRY" >&2
  exit 2
fi

STAMP=$(compute_compiler_stamp "$ROOT" "$BOOTSTRAP")
CACHED_STAMP=$(stamp_read "$ROOT" compiler)
OBJECT_ID=$(stamp_object_id "$ROOT" compiler)
if [[ "$BACKEND" == "native" ]]; then
  OUT_NAME="compiler"
  kinglet_layout_dirs "$ROOT"
  OUT_PATH="$KINGLET_OUT_DIR/$OUT_NAME"
  NATIVE_STAMP=$(compute_compiler_stamp "$ROOT" "$BOOTSTRAP" native)
  CACHED_NATIVE_STAMP=$(stamp_read "$ROOT" compiler-native)
  if [[ "$NATIVE_STAMP" == "$CACHED_NATIVE_STAMP" && -x "$OUT_PATH" ]]; then
    if [[ "$QUIET" -eq 0 ]]; then
      echo "kinglet build: cache hit (stamp $NATIVE_STAMP)" >&2
    fi
    printf '%s\n' "$OUT_PATH"
    exit 0
  fi
  # Per-module object cache: unchanged modules skip LLVM codegen and only
  # changed ones are re-emitted before the relink.
  OBJ_CACHE_DIR="$KINGLET_OBJECTS_DIR/native"
  mkdir -p "$OBJ_CACHE_DIR"
  if [[ "$QUIET" -eq 0 ]]; then
    echo "kinglet build: native backend for $BUILD_ROOT ..." >&2
  fi
  if ! "$BOOTSTRAP" --backend native -o "$OUT_PATH" --obj-cache "$OBJ_CACHE_DIR" "$ENTRY" \
      2>"$ROOT/.kinglet_build.err"; then
    echo "kinglet build: native compile failed:" >&2
    cat "$ROOT/.kinglet_build.err" >&2
    rm -f "$ROOT/.kinglet_build.err"
    exit 2
  fi
  rm -f "$ROOT/.kinglet_build.err"
  stamp_write "$ROOT" compiler-native "$NATIVE_STAMP" ""
  printf '%s\n' "$OUT_PATH"
  exit 0
fi

OUT_NAME="compiler.kbc"
kinglet_layout_dirs "$ROOT"
OUT_PATH="$KINGLET_OUT_DIR/$OUT_NAME"

if [[ "$STAMP" == "$CACHED_STAMP" && -n "$OBJECT_ID" && -f "$KINGLET_OBJECTS_DIR/$OBJECT_ID" && -f "$OUT_PATH" ]]; then
  if [[ "$QUIET" -eq 0 ]]; then
    echo "kinglet build: cache hit (stamp $STAMP)" >&2
  fi
  printf '%s\n' "$OUT_PATH"
  exit 0
fi

if [[ "$QUIET" -eq 0 ]]; then
  echo "kinglet build: compiling $BUILD_ROOT via bootstrap ..." >&2
fi

TMP_OUT=$(mktemp "${TMPDIR:-/tmp}/kinglet-build.XXXXXX.kbc")
trap 'rm -f "$TMP_OUT"' EXIT

if [[ "${KINGLET_STRIP_DEBUG:-0}" == "1" ]]; then
  if ! "$BOOTSTRAP" --save-bytecode "$TMP_OUT" --strip-debug "$ENTRY" 2>"$ROOT/.kinglet_build.err"; then
    echo "kinglet build: bootstrap compile failed:" >&2
    cat "$ROOT/.kinglet_build.err" >&2
    rm -f "$ROOT/.kinglet_build.err"
    exit 2
  fi
elif ! "$BOOTSTRAP" --save-bytecode "$TMP_OUT" "$ENTRY" 2>"$ROOT/.kinglet_build.err"; then
  echo "kinglet build: bootstrap compile failed:" >&2
  cat "$ROOT/.kinglet_build.err" >&2
  rm -f "$ROOT/.kinglet_build.err"
  exit 2
fi
rm -f "$ROOT/.kinglet_build.err"

OBJECT_ID=$(object_id_for_file "$TMP_OUT")
klos_write_object "$ROOT" "$OBJECT_ID" "$TMP_OUT" "kbc" "$STAMP" "ref"
OUT_PATH=$(install_out_artifact "$ROOT" "$TMP_OUT" "$OUT_NAME")
stamp_write "$ROOT" compiler "$STAMP" "$OBJECT_ID"

# Backward-compatible symlink at repo root (release workflow, docs).
ln -sf ".kinglet/out/$OUT_NAME" "$ROOT/compiler.kbc"

if [[ "$QUIET" -eq 0 ]]; then
  echo "kinglet build: wrote $OUT_PATH (object $OBJECT_ID)" >&2
fi
printf '%s\n' "$OUT_PATH"
