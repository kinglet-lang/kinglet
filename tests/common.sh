#!/usr/bin/env bash
# Shared helpers for self-hosted golden suites.
#
# All suites that drive the self-hosted entry (`cli/main.kl`) share the same
# pain: compiling cli/main.kl from source costs ~85s, but running the result
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

# Ensure $ROOT/cli.kbc exists and is newer than every .kl under cli/, parser/,
# compiler/, checker/, lexer/. Rebuild it via
# `kinglet --save-bytecode cli.kbc cli/main.kl` only when stale. ROOT and
# KINGLET_BIN must be set by the caller. Prints the .kbc path on stdout.
ensure_cli_kbc() {
  local root="$1"
  local kinglet="$2"
  local entry="$root/cli/main.kl"
  local cli_kbc="$root/cli.kbc"

  local needs_rebuild=0
  if [[ ! -f "$cli_kbc" ]]; then
    needs_rebuild=1
  else
    for kl in "$root"/cli/*.kl "$root"/parser/*.kl "$root"/compiler/*.kl "$root"/checker/*.kl "$root"/lexer/*.kl; do
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
      echo "failed to rebuild cli.kbc:" >&2
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
