#!/usr/bin/env bash
# Shadow LLVM native smoke (ADR 0019, Route B): the self-host compiler emits
# textual .ll; clang++ assembles and links with libkinglet_rt.a. The resulting
# binary's exit code and stdout must match the bootstrap VM run. No C++
# KirToLlvm is on the path. Gracefully SKIPs when clang++ or the runtime lib
# is unavailable (CI bootstrap may be built without LLVM).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT" || exit 2
BOOTSTRAP="${KINGLET_BOOTSTRAP:-}"
KINGLET_BIN="${KINGLET_BIN:-$BOOTSTRAP}"
CASES_DIR="$ROOT/tests/native/cases"
MANIFEST="$ROOT/tests/native/shadow_manifest.txt"
TMP_DIR="$(mktemp -d)"
FAILURES=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

command -v clang++ >/dev/null 2>&1 || { echo "SKIP shadow smoke: clang++ not found" >&2; exit 0; }
RT_LIB="$(ensure_cruntime_rt "$ROOT" 2>/dev/null)" || RT_LIB="$(dirname "$BOOTSTRAP")/obj/runtime/libkinglet_rt.a"
[[ -f "$RT_LIB" ]] || { echo "SKIP shadow smoke: $RT_LIB not found (build bootstrap with LLVM)" >&2; exit 0; }

SHADOW_COMPILER="$(ensure_native_compiler "$ROOT")" || exit 2

run_case() {
  local name="$1"
  local src="$CASES_DIR/$name.kl"
  local ll="$TMP_DIR/$name.ll"
  local obj="$TMP_DIR/$name.o"
  local bin="$TMP_DIR/$name"
  local stderr="$TMP_DIR/$name.err"
  local want_exit=0
  local ec=0

  if [[ ! -f "$src" ]]; then
    echo "FAIL $name: missing $src" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if [[ -f "$CASES_DIR/$name.exit" ]]; then
    want_exit=$(cat "$CASES_DIR/$name.exit")
  fi

  if ! "$SHADOW_COMPILER" --emit-ll "$ll" "$src" 2>"$stderr"; then
    echo "FAIL $name: shadow --emit-ll failed" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if ! clang++ -Wno-override-module -c "$ll" -o "$obj" 2>>"$stderr"; then
    echo "FAIL $name: clang++ assemble failed" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if ! clang++ "$obj" "$RT_LIB" -o "$bin" 2>>"$stderr"; then
    echo "FAIL $name: clang++ link failed" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  local stdout_file="$TMP_DIR/$name.stdout"
  local parity_file="$CASES_DIR/$name.stdout"
  if [[ -f "$parity_file" ]]; then
    local bs_stdout="$TMP_DIR/$name.bs.stdout"
    local bs_bin="$TMP_DIR/$name.bs"
    if ! "$BOOTSTRAP" --backend native -o "$bs_bin" "$src" 2>>"$stderr"; then
      echo "FAIL $name: bootstrap native build failed" >&2
      FAILURES=$((FAILURES + 1))
      return
    fi
    "$bs_bin" >"$bs_stdout" 2>>"$stderr" || true
    strip_cr "$bs_stdout"
    "$bin" >"$stdout_file" 2>>"$stderr" || ec=$?
    strip_cr "$stdout_file"
    if ! diff -u "$bs_stdout" "$stdout_file" >/dev/null; then
      echo "FAIL $name: native stdout != bootstrap native stdout" >&2
      diff -u "$bs_stdout" "$stdout_file" >&2
      FAILURES=$((FAILURES + 1))
      return
    fi
  else
    "$bin" 2>>"$stderr" || ec=$?
  fi
  strip_cr "$stderr"

  if [[ "$ec" -ne "$want_exit" ]]; then
    echo "FAIL $name: exit want=$want_exit got=$ec" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if [[ -s "$stderr" ]]; then
    echo "FAIL $name: stderr not empty" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS $name"
}

while IFS= read -r name || [[ -n "$name" ]]; do
  [[ -z "$name" ]] && continue
  [[ "$name" =~ ^# ]] && continue
  run_case "$name"
done <"$MANIFEST"

if [[ "$FAILURES" -ne 0 ]]; then
  echo "Shadow native smoke tests failed: $FAILURES" >&2
  exit 1
fi
echo "Shadow native smoke tests passed."
