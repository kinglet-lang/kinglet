#!/usr/bin/env bash
# Builtin method matrix — selfhost via compiler.kbc (bootstrap = VM host only).
#
# Each case is a minimal program exercising one receiver.method() binding
# from compiler/codegen.kl emit_method_call. Oracle: // EXPECT_OUT: on line 1.
#
# Columns:
#   check  — compiler.kbc --check (informational)
#   stage  — parse → compile → run vs EXPECT_OUT
#
# Snapshot only — always exits 0. See README.md for the documented matrix.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT" || exit 2
KINGLET="$KINGLET_BIN"
CLI_KBC=$(ensure_cli_kbc "$ROOT") || exit 2

CASES="$ROOT/tests/builtin_methods/cases"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

receiver_kind() {
  case "$1" in
    array_*) echo "array" ;;
    map_*) echo "map" ;;
    string_*) echo "string" ;;
    *) echo "other" ;;
  esac
}

classify() {
  local f="$1"
  local expect="$2"
  local kbc="$3"
  local check_cell="chk✓"
  local note=""

  if ! "$KINGLET" --run "$CLI_KBC" --ast "$f" >/dev/null 2>"$TMP/e"; then
    echo "parse✗|chk-|$(head -1 "$TMP/e")"
    return
  fi

  "$KINGLET" --run "$CLI_KBC" "$f" --check >/dev/null 2>"$TMP/e"
  if grep -qE '[0-9]+ type error' "$TMP/e"; then
    check_cell="chk✗"
    note=$(head -1 "$TMP/e")
  fi

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

echo "# Builtin method matrix (selfhost via compiler.kbc)"
echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo "# VM host: ${KINGLET}"
echo
printf '| %-22s | %-8s | %-10s | %-8s | %-10s | %s |\n' "case" "receiver" "method" "check" "stage" "note"
printf '|%s|%s|%s|%s|%s|%s|\n' "----------------------" "--------" "----------" "--------" "----------" "----------------"

total=0
run_ok=0
chk_fail=0

for _r in array map string; do
  eval "cnt_${_r}=0 run_${_r}=0 chk_${_r}=0"
done

shopt -s nullglob
for f in "$CASES"/*.kl; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f" .kl)
  recv=$(receiver_kind "$base")
  method=${base#*_}

  expect=$(head -1 "$f" | sed -n 's/.*EXPECT_OUT:[[:space:]]*\(.*\)/\1/p')
  [[ -z "$expect" ]] && expect="<no oracle>"

  total=$((total + 1))
  kbc="$TMP/${base}.kbc"
  res=$(classify "$f" "$expect" "$kbc")
  stage=${res%%|*}
  rest=${res#*|}
  check_cell=${rest%%|*}
  note=${rest#*|}

  [[ "$stage" == "run✓" ]] && run_ok=$((run_ok + 1))
  [[ "$check_cell" == "chk✗" ]] && chk_fail=$((chk_fail + 1))

  eval "cnt_${recv}=\$((cnt_${recv} + 1))"
  [[ "$stage" == "run✓" ]] && eval "run_${recv}=\$((run_${recv} + 1))"
  [[ "$check_cell" == "chk✗" ]] && eval "chk_${recv}=\$((chk_${recv} + 1))"

  printf '| %-22s | %-8s | %-10s | %-8s | %-10s | %s |\n' \
    "$base" "$recv" "$method" "$check_cell" "$stage" "$note"
done

echo
echo "Total: $total cases, run✓: $run_ok, checker failures (non-blocking): $chk_fail"
echo
echo "By receiver (stage run✓ / total, chk✗):"
for recv in array map string; do
  eval "t=\$cnt_${recv} r=\$run_${recv} c=\$chk_${recv}"
  [[ "$t" -eq 0 ]] && continue
  printf '  %-8s run✓ %d/%d' "$recv" "$r" "$t"
  [[ "$c" -gt 0 ]] && printf '  chk✗ %d' "$c"
  echo
done
