#!/usr/bin/env bash
# Shared helpers for self-hosted golden suites.
#
# Selfhost suites drive the native toolchain compiler (`.kinglet/out/compiler`)
# built via `ensure_native_compiler`. Override with KINGLET_BOOTSTRAP (Ref C++
# compiler, must be LLVM-enabled) or KINGLET (native self-host binary).

# Bootstrap C++ compiler (native build required for toolchain compile).
resolve_bootstrap() {
  local root="$1"
  local k="${KINGLET_BOOTSTRAP:-}"
  local candidate

  if [[ -n "$k" ]]; then
    if [[ -x "$k" || -f "$k" ]]; then
      printf '%s' "$k"
      return 0
    fi
    if [[ -x "$k.exe" || -f "$k.exe" ]]; then
      printf '%s' "$k.exe"
      return 0
    fi
  fi

  for candidate in \
    "$root/../kinglet-bootstrap/out/Llvm/kinglet" \
    "$root/../kinglet-bootstrap/out/Default/kinglet" \
    "$root/bootstrap/out/Llvm/kinglet" \
    "$root/bootstrap/out/Default/kinglet" \
    "$root/../../kinglet/out/Llvm/kinglet" \
    "$root/../../kinglet/out/Default/kinglet" \
    "$root/../../../kinglet/out/Llvm/kinglet" \
    "$root/../../../kinglet/out/Default/kinglet"; do
    if [[ -x "$candidate" || -f "$candidate" ]]; then
      printf '%s' "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
      return 0
    fi
  done

  echo "bootstrap kinglet not found (tried KINGLET_BOOTSTRAP and sibling out/Llvm/)" >&2
  echo "Set KINGLET_BOOTSTRAP=/path/to/bootstrap/kinglet (LLVM build)." >&2
  return 2
}

# Export bootstrap + native self-host compiler paths.
export_kinglet_bins() {
  local root="$1"
  export KINGLET_BOOTSTRAP="$(resolve_bootstrap "$root")" || return 2
  export KINGLET_COMPILER="${KINGLET:-}"
  if [[ -z "$KINGLET_COMPILER" ]]; then
    export KINGLET_COMPILER="$(ensure_native_compiler "$root" 2>/dev/null)" || true
  fi
  export KINGLET_BIN="${KINGLET_COMPILER:-$KINGLET_BOOTSTRAP}"
  export KINGLET="$KINGLET_BIN"
}

# Ensure native toolchain compiler binary (ADR 0014 / 0022 P0-0).
# Prints absolute path to `.kinglet/out/compiler` on stdout.
ensure_native_compiler() {
  local root="$1"
  local build_sh="$root/scripts/build/build.sh"
  if [[ ! -f "$build_sh" ]]; then
    echo "ensure_native_compiler: $build_sh not found" >&2
    return 2
  fi
  if [[ -n "${2:-}" ]]; then
    export KINGLET_BOOTSTRAP="$2"
  fi
  bash "$build_sh" --quiet --backend native "$root"
}

# Deprecated: VM bytecode artefact (removed). Alias for native compiler path.
ensure_build_stamp() {
  ensure_native_compiler "$@"
}

ensure_cli_kbc() {
  ensure_native_compiler "$@"
}

# Normalize CRLF to LF byte-for-byte in the given files.
strip_cr() {
  local f
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    tr -d '\r' <"$f" >"$f.nocr" && mv -f "$f.nocr" "$f"
  done
}

# Run native self-host compiler with flags on a .kl source.
# Usage: run_compiler <compiler_bin> <mode-flag> <src.kl> [extra args...]
run_compiler() {
  local compiler="$1"
  local flag="$2"
  local src="$3"
  shift 3
  "$compiler" "$flag" "$src" "$@"
}

# Test case runner: compile .kl, run in specified mode, compare outputs.
# mode: "run" (execute via bootstrap native) | "--ast" | "--check" | "--bytecode"
run_case() {
  local name="$1"
  local mode="$2"
  local expected_exit="$3"
  local expected_stdout="$4"
  local expected_stderr="$5"
  local source="${TEST_CASES_DIR:-.}/$name.kl"
  local stdout="${TMP_DIR:-.}/$name.stdout"
  local stderr="${TMP_DIR:-.}/$name.stderr"
  local kinglet="${KINGLET_BIN:-$KINGLET}"
  local bootstrap="${KINGLET_BOOTSTRAP:-$kinglet}"

  if [[ "$mode" == "run" ]]; then
    local tmpbin="${TMP_DIR:-.}/$name.bin"
    local actual_exit=0
    if ! "$bootstrap" --backend native -o "$tmpbin" "$source" 2>"$stderr"; then
      actual_exit=$?
    else
      "$tmpbin" >"$stdout" 2>>"$stderr"
      actual_exit=$?
    fi
  else
    "$kinglet" "$mode" "$source" >"$stdout" 2>"$stderr"
    actual_exit=$?
  fi

  strip_cr "$stdout" "$stderr"

  local failed=0
  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "FAIL $name: exit code expected $expected_exit, got $actual_exit" >&2
    failed=1
  fi
  if ! diff -u <(printf "%s" "$expected_stdout") "$stdout" >/dev/null; then
    echo "FAIL $name: stdout mismatch" >&2
    diff -u <(printf "%s" "$expected_stdout") "$stdout" >&2
    failed=1
  fi
  if ! diff -u <(printf "%s" "$expected_stderr") "$stderr" >/dev/null; then
    echo "FAIL $name: stderr mismatch" >&2
    diff -u <(printf "%s" "$expected_stderr") "$stderr" >&2
    failed=1
  fi

  return $failed
}

run_args_case() {
  local name="$1"
  local expected_exit="$2"
  local expected_stdout="$3"
  local expected_stderr="$4"
  shift 4
  local source="${TEST_CASES_DIR:-.}/$name.kl"
  local stdout="${TMP_DIR:-.}/$name.stdout"
  local stderr="${TMP_DIR:-.}/$name.stderr"
  local bootstrap="${KINGLET_BOOTSTRAP:-$KINGLET_BIN}"

  local tmpbin="${TMP_DIR:-.}/$name.bin"
  if ! "$bootstrap" --backend native -o "$tmpbin" "$source" 2>"$stderr"; then
    strip_cr "$stdout" "$stderr"
    return 1
  fi
  "$tmpbin" "$@" >"$stdout" 2>>"$stderr"
  local actual_exit=$?

  strip_cr "$stdout" "$stderr"

  local failed=0
  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "FAIL $name: exit code expected $expected_exit, got $actual_exit" >&2
    failed=1
  fi
  if ! diff -u <(printf "%s" "$expected_stdout") "$stdout" >/dev/null; then
    echo "FAIL $name: stdout mismatch" >&2
    diff -u <(printf "%s" "$expected_stdout") "$stdout" >&2
    failed=1
  fi
  if ! diff -u <(printf "%s" "$expected_stderr") "$stderr" >/dev/null; then
    echo "FAIL $name: stderr mismatch" >&2
    diff -u <(printf "%s" "$expected_stderr") "$stderr" >&2
    failed=1
  fi

  return $failed
}

run_contains_case() {
  local name="$1"
  local mode="$2"
  shift 2
  local source="${TEST_CASES_DIR:-.}/$name.kl"
  local stdout="${TMP_DIR:-.}/$name.stdout"
  local stderr="${TMP_DIR:-.}/$name.stderr"
  local kinglet="${KINGLET_BIN:-$KINGLET}"

  "$kinglet" "$mode" "$source" >"$stdout" 2>"$stderr"
  local actual_exit=$?

  strip_cr "$stdout" "$stderr"

  local failed=0
  if [[ "$actual_exit" -ne 0 ]]; then
    echo "FAIL $name: exit code expected 0, got $actual_exit" >&2
    failed=1
  fi
  if [[ -s "$stderr" ]]; then
    echo "FAIL $name: unexpected stderr output" >&2
    cat "$stderr" >&2
    failed=1
  fi
  for pattern in "$@"; do
    if ! grep -q "$pattern" "$stdout"; then
      echo "FAIL $name: stdout missing pattern '$pattern'" >&2
      failed=1
    fi
  done

  return $failed
}

run_with_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
    return $?
  fi
  "$@"
  return $?
}
