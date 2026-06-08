#!/usr/bin/env bash
# Snapshot matrix: bootstrap vs selfhost over a broad corpus (non-gating).
# Prints compile / bytecode / behavior columns; always exits 0 unless setup fails.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

VM=$(resolve_kinglet "$ROOT") || exit 2
BS=$(resolve_bootstrap "$ROOT") || exit 2
export KINGLET_BIN="$VM"
CLI_KBC=$(ensure_cli_kbc "$ROOT" "$VM") || exit 2

echo "# Differential matrix (bootstrap vs selfhost)"
echo "# VM:        $VM"
echo "# bootstrap: $BS"
echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo

# Collect corpus (bash 3.x — no associative arrays).
CORPUS_FILE="$(mktemp)"
trap 'rm -f "$CORPUS_FILE"' EXIT

add_dir() {
  local d="$1"
  [[ -d "$d" ]] || return 0
  find "$d" -name '*.kl' -type f | sort
}

{
  add_dir "$ROOT/tests/differential/cases"
  add_dir "$ROOT/tests/exec/cases"
  add_dir "$ROOT/tests/probe/cases"
} | awk -F/ '{print $NF "\t" $0}' | sort -u -t$'\t' -k1,1 | cut -f2- >"$CORPUS_FILE"

if [[ ! -s "$CORPUS_FILE" ]]; then
  echo "no corpus .kl files found" >&2
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$CORPUS_FILE"' EXIT

compile_bs() {
  local src="$1" out="$2"
  "$BS" --save-bytecode "$out" "$src" >/dev/null 2>"$out.err"
  return $?
}

compile_sh() {
  local src="$1" out="$2"
  compile_selfhost "$CLI_KBC" "$src" "$out" 2>"$out.err"
  return $?
}

run_bs() {
  local src="$1" tag="$2"
  "$BS" "$src" >"$TMP/$tag.out" 2>"$TMP/$tag.err"
  return $?
}

run_sh() {
  local kbc="$1" tag="$2"
  run_kbc "$kbc" >"$TMP/$tag.out" 2>"$TMP/$tag.err"
  return $?
}

printf '| %-26s | %-7s | %-10s | %-9s | %s |\n' "case" "compile" "bytecode" "behavior" "note"
printf '|%s|%s|%s|%s|%s|\n' "----------------------------" "---------" "------------" "-----------" "--------------------"

total=0 bc_same=0 bc_diff=0 sh_only_fail=0 bs_only_fail=0 both_fail=0
beh_same=0 beh_diff=0 beh_na=0

while IFS= read -r src; do
  [[ -z "$src" ]] && continue
  name=$(basename "$src" .kl)
  total=$((total + 1))
  bskbc="$TMP/$name.bs.kbc"
  shkbc="$TMP/$name.sh.kbc"

  ec_bs=0 ec_sh=0
  compile_bs "$src" "$bskbc" || ec_bs=$?
  compile_sh "$src" "$shkbc" || ec_sh=$?

  compile_cell="" bc_cell="-" beh_cell="-" note=""

  if [[ "$ec_bs" -eq 0 && "$ec_sh" -eq 0 ]]; then
    compile_cell="both"
    if cmp -s "$bskbc" "$shkbc" 2>/dev/null; then
      bc_cell="identical"
      bc_same=$((bc_same + 1))
    else
      bc_cell="DIFFER"
      bc_diff=$((bc_diff + 1))
      sz_bs=$(wc -c <"$bskbc" | tr -d ' ')
      sz_sh=$(wc -c <"$shkbc" | tr -d ' ')
      note="bc: bs=${sz_bs}B sh=${sz_sh}B"
    fi

    rc_bs=0 rc_sh=0
    run_bs "$src" "$name.bs" || rc_bs=$?
    run_sh "$shkbc" "$name.sh" || rc_sh=$?
    strip_cr "$TMP/$name.bs.out" "$TMP/$name.sh.out"

    if [[ "$rc_bs" -eq "$rc_sh" ]] && cmp -s "$TMP/$name.bs.out" "$TMP/$name.sh.out" 2>/dev/null; then
      beh_cell="identical"
      beh_same=$((beh_same + 1))
    else
      beh_cell="DIFFER"
      beh_diff=$((beh_diff + 1))
      note="${note:+$note; }exit bs=$rc_bs sh=$rc_sh"
      cmp -s "$TMP/$name.bs.out" "$TMP/$name.sh.out" 2>/dev/null || note="${note}, stdout differs"
    fi

  elif [[ "$ec_bs" -eq 0 && "$ec_sh" -ne 0 ]]; then
    compile_cell="sh✗"
    sh_only_fail=$((sh_only_fail + 1))
    beh_na=$((beh_na + 1))
    note="sh: $(head -1 "$shkbc.err" 2>/dev/null)"
  elif [[ "$ec_bs" -ne 0 && "$ec_sh" -eq 0 ]]; then
    compile_cell="bs✗"
    bs_only_fail=$((bs_only_fail + 1))
    beh_na=$((beh_na + 1))
    note="bs: $(head -1 "$bskbc.err" 2>/dev/null)"
  else
    compile_cell="both✗"
    both_fail=$((both_fail + 1))
    beh_na=$((beh_na + 1))
    note="both reject"
  fi

  printf '| %-26s | %-7s | %-10s | %-9s | %s |\n' "$name" "$compile_cell" "$bc_cell" "$beh_cell" "$note"
done <"$CORPUS_FILE"

echo
echo "## Summary ($total cases)"
echo "compile : both ok=$((bc_same + bc_diff)), sh-only-fail=$sh_only_fail, bs-only-fail=$bs_only_fail, both-fail=$both_fail"
echo "bytecode: identical=$bc_same, DIFFER=$bc_diff"
echo "behavior: identical=$beh_same, DIFFER=$beh_diff, n/a=$beh_na"
echo
echo "(snapshot only — see tests/differential/run.sh for gating cases)"

exit 0
