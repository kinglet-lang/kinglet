#!/usr/bin/env bash
# Oracle-anchored regression suite: pins the measured sh-vs-bs divergences
# (see handoff/03-measured-gap-sh-vs-bs.md) so they cannot silently regress.
#
# Expected outputs are HAND-VERIFIED oracles, NOT blessed from this compiler's
# own output (which is how latent bugs survived in the golden suites):
#   - where the bootstrap is correct (guard, implicit return, ...), the oracle
#     is the bootstrap's output;
#   - where the bootstrap is itself buggy (it prints <enum:N:M> for bound enum/
#     error payloads), the oracle is the hand-verified correct value, which the
#     self-host produces.
#
# Two buckets:
#   MUST_PASS  - asserted; a mismatch fails the suite (these are fixed/correct).
#   KNOWN_FAIL - run + reported, non-gating; an unexpected pass (XPASS) is
#                flagged so the case can be promoted once its gap is fixed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"
KINGLET=$(resolve_kinglet "$ROOT") || exit 2

CASES="$ROOT/tests/regression/cases"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Self-host now correct here — assert and guard against regression.
MUST_PASS=(
  guard_stmt 18_guard implicit_return                 # fixed sh control-flow bugs
  12_enum_match try_catch                             # sh correct; bootstrap leaks <enum>
  enum_destructure_test match_enum_destruct enum_guard_test
  match_basic match_binding                           # trailing newline corrected (io::out no \n)
  map_basic map_symbol_table                          # map type + literal support added
)
# Known remaining gaps (tracked, non-gating). Oracle = correct (bootstrap) output.
KNOWN_FAIL=(
  chained_comparisons                                 # no chained cmp desugaring
  arrays_type_error arrays_bytecode cat               # shallow checker / exit-code mismatch
)

# Run case $1; sets OUT_OK / EXIT_OK / GOT_EXIT / WANT_EXIT.
run_one() {
  local name="$1"
  local src="$CASES/$name.kl" exp="$CASES/$name.expected" exit_file="$CASES/$name.exit"
  WANT_EXIT=0
  [[ -f "$exit_file" ]] && WANT_EXIT=$(cat "$exit_file")
  "$KINGLET" "$src" >"$TMP/out" 2>"$TMP/err" </dev/null
  GOT_EXIT=$?
  strip_cr "$TMP/out"
  OUT_OK=0; EXIT_OK=0
  diff -q "$exp" "$TMP/out" >/dev/null 2>&1 && OUT_OK=1
  [[ "$GOT_EXIT" -eq "$WANT_EXIT" ]] && EXIT_OK=1
}

echo "=== Regression suite (oracle-anchored sh-vs-bs divergences) ==="
fails=0; xpass=0

echo; echo "-- MUST PASS --"
for name in "${MUST_PASS[@]}"; do
  run_one "$name"
  if [[ "$OUT_OK" -eq 1 && "$EXIT_OK" -eq 1 ]]; then
    echo "PASS  $name"
  else
    echo "FAIL  $name (exit want=$WANT_EXIT got=$GOT_EXIT)"
    diff -u "$CASES/$name.expected" "$TMP/out" | sed 's/^/      /' | head -20
    fails=$((fails + 1))
  fi
done

echo; echo "-- KNOWN FAIL (tracked gaps; expected to still diverge) --"
for name in "${KNOWN_FAIL[@]}"; do
  run_one "$name"
  if [[ "$OUT_OK" -eq 1 && "$EXIT_OK" -eq 1 ]]; then
    echo "XPASS $name  <-- now matches oracle; PROMOTE to MUST_PASS"
    xpass=$((xpass + 1))
  else
    echo "xfail $name (tracked; exit want=$WANT_EXIT got=$GOT_EXIT)"
  fi
done

echo; echo "=== Summary ==="
echo "MUST_PASS failures: $fails"
echo "KNOWN_FAIL now passing (promote): $xpass"
if [[ "$fails" -eq 0 ]]; then echo "Regression suite PASSED"; else echo "Regression suite FAILED"; fi
[[ "$fails" -eq 0 ]]
