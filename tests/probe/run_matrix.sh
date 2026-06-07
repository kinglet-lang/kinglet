#!/usr/bin/env bash
# Capability matrix probe runner for the self-hosted Kinglet compiler.
#
# Every stage goes through compiler.kbc (bootstrap kinglet is only the VM host):
#   parse  → kinglet --run compiler.kbc --ast <probe>
#   check  → kinglet --run compiler.kbc --check <probe>   (informational)
#   compile→ kinglet --run compiler.kbc --save-bytecode <tmp> <probe>
#   run    → kinglet --run <tmp>
#
# The `check` column is reported separately and does NOT gate compile/run: the
# selfhost checker is still shallow on match, builtins, and using-selective.
# The `stage` column reflects the end-to-end pipeline (parse → compile → run).
#
# Run-stage oracle: line-1 `// EXPECT_OUT: <text>` in each probe file.
#
# Snapshot only — always exits 0.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

KINGLET=$(resolve_kinglet "$ROOT") || exit 2
CLI_KBC=$(ensure_cli_kbc "$ROOT" "$KINGLET") || exit 2

CASES="$ROOT/tests/probe/cases"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# classify <file> <expect> <tmp_kbc>
# Prints: stage|check|note  (pipe-delimited; note may be empty)
classify() {
  local f="$1"
  local expect="$2"
  local kbc="$3"
  local check_cell="chk✓"
  local note=""

  # Parse
  if ! "$KINGLET" --run "$CLI_KBC" --ast "$f" >/dev/null 2>"$TMP/e"; then
    echo "parse✗|chk-|$(head -1 "$TMP/e")"
    return
  fi

  # Check (non-blocking; match "N type error(s)", not "OK: no type errors")
  "$KINGLET" --run "$CLI_KBC" "$f" --check >/dev/null 2>"$TMP/e"
  if grep -qE '[0-9]+ type error' "$TMP/e"; then
    check_cell="chk✗"
    note=$(head -1 "$TMP/e")
  fi

  # Compile
  : >"$TMP/e"
  "$KINGLET" --run "$CLI_KBC" --save-bytecode "$kbc" "$f" >/dev/null 2>"$TMP/e" || true
  if grep -q 'compile error' "$TMP/e"; then
    local cg_note
    cg_note=$(head -1 "$TMP/e")
    if [[ -n "$note" ]]; then
      echo "cg✗|${check_cell}|${note}; ${cg_note}"
    else
      echo "cg✗|${check_cell}|${cg_note}"
    fi
    return
  fi
  if [[ ! -f "$kbc" ]]; then
    echo "cg✗|${check_cell}|failed to write bytecode"
    return
  fi

  # Run
  local out ec
  out=$("$KINGLET" --run "$kbc" 2>"$TMP/e") || ec=$?
  ec=${ec:-0}
  if [[ "$ec" -ne 0 ]]; then
    local rt_note
    rt_note=$(head -1 "$TMP/e")
    if [[ -n "$note" ]]; then
      echo "run✗|${check_cell}|${note}; ${rt_note}"
    else
      echo "run✗|${check_cell}|${rt_note}"
    fi
    return
  fi

  if [[ "$out" == "$expect" ]]; then
    if [[ -n "$note" ]]; then
      echo "run✓|${check_cell}|${note}"
    else
      echo "run✓|${check_cell}|"
    fi
    return
  fi

  if [[ -n "$note" ]]; then
    echo "run≠out|${check_cell}|${note}; got:'${out}'"
  else
    echo "run≠out|${check_cell}|got:'${out}'"
  fi
}

echo "# Kinglet capability matrix (selfhost via compiler.kbc)"
echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo "# VM host: ${KINGLET}"
echo
printf '| %-28s | %-12s | %-8s | %-10s | %s |\n' "probe" "expect" "check" "stage" "note"
printf '|%s|%s|%s|%s|%s|\n' "----------------------------" "------------" "--------" "----------" "----------------"

reached_run=0
total=0
chk_fail=0

shopt -s nullglob
for f in "$CASES"/*.kl; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f" .kl)

  expect=$(head -1 "$f" | sed -n 's/.*EXPECT_OUT:[[:space:]]*\(.*\)/\1/p')
  [[ -z "$expect" ]] && expect="<no oracle>"

  total=$((total + 1))
  kbc="$TMP/${name}.kbc"

  res=$(classify "$f" "$expect" "$kbc")
  stage=${res%%|*}
  rest=${res#*|}
  check_cell=${rest%%|*}
  note=${rest#*|}

  [[ "$stage" == "run✓" ]] && reached_run=$((reached_run + 1))
  [[ "$check_cell" == "chk✗" ]] && chk_fail=$((chk_fail + 1))

  printf '| %-28s | %-12s | %-8s | %-10s | %s |\n' "$name" "$expect" "$check_cell" "$stage" "$note"
done

echo
echo "Total: $total probes, run✓: $reached_run, checker failures (non-blocking): $chk_fail"
echo
echo "Legend:"
echo "  check chk✓/chk✗  — selfhost --check (informational; does not gate stage)"
echo "  parse✗           — selfhost parse failed"
echo "  cg✗              — selfhost compile failed"
echo "  run✗             — runtime error"
echo "  run≠out          — output mismatch vs EXPECT_OUT"
echo "  run✓             — compile + run matched oracle (chk✗ may still appear in note)"
