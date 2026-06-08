#!/usr/bin/env bash
# Oracle-anchored regression: selfhost must match hand-verified outputs.
# Also reports bootstrap vs selfhost drift on MUST_PASS cases (non-gating).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

KINGLET_BIN=$(resolve_kinglet "$ROOT") || exit 2
BOOTSTRAP_BIN=$(resolve_bootstrap "$ROOT") || exit 2
export KINGLET_BIN
CLI_KBC=$(ensure_cli_kbc "$ROOT" "$KINGLET_BIN") || exit 2

CASES="$ROOT/tests/regression/cases"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MUST_PASS=(
  guard_stmt 18_guard implicit_return
  12_enum_match try_catch
  enum_destructure_test match_enum_destruct enum_guard_test
  match_basic match_binding
  map_basic map_symbol_table
  arrays_type_error
)
KNOWN_FAIL=(
  arrays_bytecode cat
)

run_selfhost() {
  local src="$1" stdout="$2" stderr="$3" kbc="$4"
  compile_selfhost "$CLI_KBC" "$src" "$kbc" 2>"$stderr" || return $?
  run_kbc "$kbc" >"$stdout" 2>>"$stderr"
  return $?
}

run_bootstrap() {
  local src="$1" stdout="$2" stderr="$3"
  "$BOOTSTRAP_BIN" "$src" >"$stdout" 2>"$stderr"
  return $?
}

run_one() {
  local name="$1"
  local src="$CASES/$name.kl"
  local exp="$CASES/$name.expected"
  local exit_file="$CASES/$name.exit"
  local kbc="$TMP/$name.kbc"

  WANT_EXIT=0
  [[ -f "$exit_file" ]] && WANT_EXIT=$(cat "$exit_file")

  if [[ "$WANT_EXIT" -eq 65 ]]; then
    set +e
    "$KINGLET_BIN" --run "$CLI_KBC" "$src" --check >"$TMP/sh.out" 2>"$TMP/sh.err"
    GOT_EXIT=$?
    set -e
  else
    set +e
    run_selfhost "$src" "$TMP/sh.out" "$TMP/sh.err" "$kbc"
    GOT_EXIT=$?
    set -e
  fi
  strip_cr "$TMP/sh.out" "$TMP/sh.err"

  OUT_OK=0
  EXIT_OK=0
  if [[ -f "$exp" ]]; then
    diff -q "$exp" "$TMP/sh.out" >/dev/null 2>&1 && OUT_OK=1
  else
    OUT_OK=1
  fi
  [[ "$GOT_EXIT" -eq "$WANT_EXIT" ]] && EXIT_OK=1

  DRIFT=0
  if [[ "$OUT_OK" -eq 1 && "$EXIT_OK" -eq 1 && -f "$exp" ]]; then
    run_bootstrap "$src" "$TMP/bs.out" "$TMP/bs.err" || true
    bs_ec=$?
    strip_cr "$TMP/bs.out" "$TMP/bs.err"
    if [[ "$bs_ec" -ne "$GOT_EXIT" ]] || ! diff -q "$TMP/sh.out" "$TMP/bs.out" >/dev/null 2>&1; then
      DRIFT=1
    fi
  fi
}

echo "=== Regression (selfhost oracle + bootstrap drift report) ==="
fails=0
xpass=0
drifts=0

echo
echo "-- MUST PASS (selfhost vs oracle) --"
for name in "${MUST_PASS[@]}"; do
  run_one "$name"
  if [[ "$OUT_OK" -eq 1 && "$EXIT_OK" -eq 1 ]]; then
    if [[ "$DRIFT" -eq 1 ]]; then
      echo "PASS  $name  (drift: bootstrap differs)"
      drifts=$((drifts + 1))
    else
      echo "PASS  $name"
    fi
  else
    echo "FAIL  $name (exit want=$WANT_EXIT got=$GOT_EXIT)"
    if [[ -f "$CASES/$name.expected" ]]; then
      diff -u "$CASES/$name.expected" "$TMP/sh.out" | sed 's/^/      /' | head -20
    fi
    fails=$((fails + 1))
  fi
done

echo
echo "-- KNOWN FAIL (tracked gaps) --"
for name in "${KNOWN_FAIL[@]}"; do
  run_one "$name"
  if [[ "$OUT_OK" -eq 1 && "$EXIT_OK" -eq 1 ]]; then
    echo "XPASS $name  <-- promote to MUST_PASS"
    xpass=$((xpass + 1))
  else
    echo "xfail $name (exit want=$WANT_EXIT got=$GOT_EXIT)"
  fi
done

echo
echo "=== Summary ==="
echo "MUST_PASS failures: $fails"
echo "MUST_PASS bootstrap drift (non-gating): $drifts"
echo "KNOWN_FAIL promoted: $xpass"
if [[ "$fails" -eq 0 ]]; then
  echo "Regression suite PASSED"
else
  echo "Regression suite FAILED"
fi
[[ "$fails" -eq 0 ]]
