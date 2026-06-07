#!/usr/bin/env bash
# Shared helpers for self-hosted golden suites.
#
# All suites that drive the self-hosted entry (`core/main.kl`) share the same
# pain: compiling core/main.kl from source costs ~85s, but running the result
# from a cached .kbc costs ~70ms. Each suite sources this file and calls
# `ensure_cli_kbc` to get a path it can pass to `kinglet --run`.
#
# Source-of-truth for which kinglet binary to use is the KINGLET env var,
# defaulting to F:/code/kinglet/out/Default/kinglet.exe. (The original
# scripts referenced a stale `kinglet-bootstrap/out/Debug/kinglet` path
# that no longer exists.)

# Resolve KINGLET to an executable. Prints absolute path on stdout, exits 2
# on failure.
resolve_kinglet() {
  local k="${KINGLET:-$1/../../kinglet/out/Default/kinglet.exe}"
  if [[ -x "$k" || -f "$k" ]]; then
    printf '%s' "$k"
    return 0
  fi
  if [[ -x "$k.exe" || -f "$k.exe" ]]; then
    printf '%s' "$k.exe"
    return 0
  fi
  echo "kinglet binary not found at $k" >&2
  echo "Set KINGLET=/path/to/kinglet to override." >&2
  return 2
}

# Ensure $ROOT/compiler.kbc exists and is newer than every .kl under core/,
# parser/, compiler/, checker/, lexer/. Rebuild it via
# `kinglet --save-bytecode compiler.kbc core/main.kl` only when stale. ROOT and
# KINGLET_BIN must be set by the caller. Prints the .kbc path on stdout.
ensure_cli_kbc() {
  local root="$1"
  local kinglet="$2"
  local entry="$root/core/main.kl"
  local cli_kbc="$root/compiler.kbc"

  local needs_rebuild=0
  if [[ ! -f "$cli_kbc" ]]; then
    needs_rebuild=1
  else
    for kl in "$root"/core/*.kl "$root"/parser/*.kl "$root"/compiler/*.kl "$root"/checker/*.kl "$root"/lexer/*.kl; do
      [[ -f "$kl" ]] || continue
      if [[ "$kl" -nt "$cli_kbc" ]]; then
        needs_rebuild=1
        break
      fi
    done
  fi
  if [[ "$needs_rebuild" -eq 1 ]]; then
    echo "Rebuilding $cli_kbc (this is slow, ~85s) ..." >&2
    if ! "$kinglet" --save-bytecode "$cli_kbc" "$entry" 2>"$root/.cli_kbc_compile.err"; then
      echo "failed to rebuild compiler.kbc:" >&2
      cat "$root/.cli_kbc_compile.err" >&2
      rm -f "$root/.cli_kbc_compile.err"
      return 2
    fi
    rm -f "$root/.cli_kbc_compile.err"
  fi
  printf '%s' "$cli_kbc"
}

# Normalize CRLF to LF byte-for-byte in the given files. `tr -d` deletes raw
# 0x0D bytes, sidestepping the text-mode pitfalls of in-place editors: BSD
# `sed -i` needs a backup-suffix argument and does not interpret `\r`, while
# Windows `perl -i` re-adds `\r` on write via its `:crlf` layer. tr operates on
# the byte stream and behaves the same on macOS, Linux, and Git-Bash.
strip_cr() {
  local f
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    tr -d '\r' <"$f" >"$f.nocr" && mv -f "$f.nocr" "$f"
  done
}

# Compile .kl source to .kbc bytecode using the bootstrap compiler.
# Usage: compile_kl <src.kl> <out.kbc> [--strip-debug]
# Returns: compiler exit code
# Side effects: stderr captured to <out.kbc>.stderr
compile_kl() {
  local src="$1"
  local out="$2"
  local strip_flag=""
  shift 2
  if [[ "${1:-}" == "--strip-debug" ]]; then
    strip_flag="--strip-debug"
  fi
  local kinglet="${KINGLET_BIN:-$KINGLET}"
  "$kinglet" --save-bytecode "$out" $strip_flag "$src" 2>"$out.stderr"
  return $?
}

# Compile .kl with the self-hosted compiler (compiler.kbc artefact).
# Usage: compile_selfhost <cli_kbc> <src.kl> <out.kbc> [--strip-debug]
# Returns: compiler exit code
# Side effects: stderr captured to <out.kbc>.stderr
compile_selfhost() {
  local cli_kbc="$1"
  local src="$2"
  local out="$3"
  local strip_flag=""
  shift 3
  if [[ "${1:-}" == "--strip-debug" ]]; then
    strip_flag="--strip-debug"
  fi
  local kinglet="${KINGLET_BIN:-$KINGLET}"
  "$kinglet" --run "$cli_kbc" --save-bytecode "$out" $strip_flag "$src" 2>"$out.stderr"
  return $?
}

# Run compiled .kbc bytecode file using the host VM.
# Usage: run_kbc <prog.kbc> [args...]
# Returns: program exit code
run_kbc() {
  local kbc="$1"
  shift
  local kinglet="${KINGLET_BIN:-$KINGLET}"
  "$kinglet" --run "$kbc" "$@"
  return $?
}

# Test case runner: compile .kl, run in specified mode, compare outputs.
# Usage: run_case <name> <mode> <expected_exit> <expected_stdout> <expected_stderr>
# mode: "run" (execute) | "--ast" | "--check" | "--bytecode"
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

  if [[ "$mode" == "run" ]]; then
    "$kinglet" "$source" >"$stdout" 2>"$stderr"
  else
    "$kinglet" "$mode" "$source" >"$stdout" 2>"$stderr"
  fi
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

# Test case runner with program arguments (forwarded to sys::args()).
# Usage: run_args_case <name> <expected_exit> <expected_stdout> <expected_stderr> [program args...]
run_args_case() {
  local name="$1"
  local expected_exit="$2"
  local expected_stdout="$3"
  local expected_stderr="$4"
  shift 4
  local source="${TEST_CASES_DIR:-.}/$name.kl"
  local stdout="${TMP_DIR:-.}/$name.stdout"
  local stderr="${TMP_DIR:-.}/$name.stderr"
  local kinglet="${KINGLET_BIN:-$KINGLET}"

  "$kinglet" "$source" "$@" >"$stdout" 2>"$stderr"
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

# Test case runner: run in mode, assert exit 0, no stderr, stdout contains patterns.
# Usage: run_contains_case <name> <mode> [pattern1] [pattern2] ...
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
