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

export_kinglet_bins "$ROOT" || exit 2
KINGLET="$KINGLET_BIN"
CLI_KBC=$(ensure_cli_kbc "$ROOT") || exit 2

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

probe_category() {
  case "$1" in
    01_*|02_*|03_*|04_*|05_*|06_*|07_*|08_*|09_*|10_*) echo "core" ;;
    11_*|12_*|13_*|25_*) echo "types" ;;
    14_*|15_*|16_*|17_*|18_*|19_*|20_*|21_*) echo "syntax" ;;
    23_*|24_*|26_*|27_*) echo "generics" ;;
    28_*|29_*) echo "platform" ;;
    *) echo "other" ;;
  esac
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

# Per-category counters (bash 3.x — no associative arrays on macOS)
for _cat in core types syntax generics platform other; do
  eval "cat_total_${_cat}=0 cat_run_${_cat}=0 cat_cg_${_cat}=0 cat_out_${_cat}=0"
done

bump_cat() {
  local cat="$1" stage="$2"
  eval "cat_total_${cat}=\$((cat_total_${cat} + 1))"
  case "$stage" in
    run✓) eval "cat_run_${cat}=\$((cat_run_${cat} + 1))" ;;
    cg✗) eval "cat_cg_${cat}=\$((cat_cg_${cat} + 1))" ;;
    run≠out) eval "cat_out_${cat}=\$((cat_out_${cat} + 1))" ;;
  esac
}

shopt -s nullglob
for f in "$CASES"/*.kl; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f" .kl)
  cat=$(probe_category "$name")

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
  bump_cat "$cat" "$stage"

  printf '| %-28s | %-12s | %-8s | %-10s | %s |\n' "$name" "$expect" "$check_cell" "$stage" "$note"
done

echo
echo "Total: $total probes, run✓: $reached_run, checker failures (non-blocking): $chk_fail"
echo
echo "By category (stage):"
for cat in core types syntax generics platform other; do
  eval "t=\$cat_total_${cat} r=\$cat_run_${cat} c=\$cat_cg_${cat} o=\$cat_out_${cat}"
  [[ "$t" -eq 0 ]] && continue
  printf '  %-10s run✓ %d/%d' "$cat" "$r" "$t"
  [[ "$c" -gt 0 ]] && printf '  cg✗ %d' "$c"
  [[ "$o" -gt 0 ]] && printf '  run≠out %d' "$o"
  echo
done
echo
echo "Legend:"
echo "  check chk✓/chk✗  — selfhost --check (informational; does not gate stage)"
echo "  parse✗           — selfhost parse failed"
echo "  cg✗              — selfhost compile failed"
echo "  run✗             — runtime error"
echo "  run≠out          — output mismatch vs EXPECT_OUT"
echo "  run✓             — compile + run matched oracle (chk✗ may still appear in note)"
echo "  categories       — see tests/probe/README.md"
