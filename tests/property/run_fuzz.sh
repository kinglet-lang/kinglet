#!/usr/bin/env bash
# Fuzz-lite: random bytes through lexer/parser must not crash or hang.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

KINGLET_BIN=$(resolve_kinglet "$ROOT") || exit 2
export KINGLET_BIN
CLI_KBC=$(ensure_cli_kbc "$ROOT" "$KINGLET_BIN") || exit 2

FUZZ_ROUNDS="${FUZZ_ROUNDS:-32}"
FUZZ_TIMEOUT="${FUZZ_TIMEOUT:-5}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILURES=0

is_crash_exit() {
  case "$1" in
    139|134|136) return 0 ;;  # SIGSEGV, SIGABRT, SIGFPE
    *) return 1 ;;
  esac
}

fuzz_one() {
  local i="$1"
  local len=$(( (RANDOM % 240) + 16 ))
  local file="$TMP/fuzz_${i}.kl"
  local ec

  dd if=/dev/urandom of="$file" bs="$len" count=1 2>/dev/null

  run_with_timeout "$FUZZ_TIMEOUT" "$KINGLET_BIN" --run "$CLI_KBC" "$file" \
    >/dev/null 2>"$TMP/fuzz_${i}.tokens.err"
  ec=$?
  if [[ "$ec" -eq 124 ]]; then
    echo "FAIL  fuzz#$i tokens: hung after ${FUZZ_TIMEOUT}s" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if is_crash_exit "$ec"; then
    echo "FAIL  fuzz#$i tokens: crash exit $ec" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  run_with_timeout "$FUZZ_TIMEOUT" "$KINGLET_BIN" --run "$CLI_KBC" --ast "$file" \
    >/dev/null 2>"$TMP/fuzz_${i}.ast.err"
  ec=$?
  if [[ "$ec" -eq 124 ]]; then
    echo "FAIL  fuzz#$i --ast: hung after ${FUZZ_TIMEOUT}s" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if is_crash_exit "$ec"; then
    echo "FAIL  fuzz#$i --ast: crash exit $ec" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
}

echo "=== Fuzz-lite ($FUZZ_ROUNDS rounds, ${FUZZ_TIMEOUT}s cap) ==="
i=1
while [[ "$i" -le "$FUZZ_ROUNDS" ]]; do
  fuzz_one "$i"
  i=$((i + 1))
done

echo "===================="
if [[ "$FAILURES" -eq 0 ]]; then
  echo "Fuzz-lite passed ($FUZZ_ROUNDS rounds, no crash/hang)"
  exit 0
fi
echo "$FAILURES fuzz failure(s)" >&2
exit 1
