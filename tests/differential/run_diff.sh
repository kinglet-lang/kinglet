#!/usr/bin/env bash
# Differential test: self-host (sh) vs bootstrap (bs).  [Phase 3b of
# handoff/02-test-suite-plan.md]
#
# This is the authoritative *measurement* of the sh<->bs gap. All prior gap
# analysis (handoff/01-capability-matrix.md) was static source tracing -- this
# actually builds nothing, but runs BOTH already-built compilers head to head.
#
# For each corpus .kl file it compiles with both compilers and compares:
#   (1) bytecode byte-identity   -- cmp of `--save-bytecode` output
#   (2) runtime behavior         -- stdout + exit code of running the .kl
# treating the bootstrap as the reference (source of truth for the language).
#
# It is a SNAPSHOT, not a gate: it always exits 0 and prints a matrix + summary
# so the real, measured gap is visible. (Turn the final `exit 0` into a check on
# $sh_only_fail / $bc_diff if you want it to gate CI.)
#
# Binaries:
#   sh = self-host host binary  -- KINGLET env (same as the rest of the suite)
#   bs = bootstrap reference     -- KINGLET_BOOTSTRAP env, else the conventional
#        sibling path kinglet-bootstrap/out/Debug/kinglet
# Corpus (override with DIFF_CORPUS=/path/to/dir):
#   bootstrap's own cli + probe cases -- the authoritative corpus.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

# --- resolve both compilers -------------------------------------------------
SH=$(resolve_kinglet "$ROOT") || exit 2

BS="${KINGLET_BOOTSTRAP:-}"
if [[ -z "$BS" ]]; then
  cand="$ROOT/../kinglet-bootstrap/out/Debug/kinglet"
  if [[ -x "$cand" || -f "$cand" ]]; then BS="$cand"
  elif [[ -x "$cand.exe" || -f "$cand.exe" ]]; then BS="$cand.exe"; fi
fi
if [[ -z "$BS" || ! ( -x "$BS" || -f "$BS" ) ]]; then
  echo "SKIP differential: bootstrap compiler not found." >&2
  echo "  build it:  (cd kinglet-bootstrap && gn gen out/Debug && ninja -C out/Debug)" >&2
  echo "  or set:    KINGLET_BOOTSTRAP=/path/to/kinglet-bootstrap/out/Debug/kinglet" >&2
  exit 0   # skip cleanly -- core CI stays self-contained
fi

echo "# Kinglet differential matrix  (sh = self-host, bs = bootstrap reference)"
echo "# sh: $SH"
echo "# bs: $BS"
echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo

# --- corpus -----------------------------------------------------------------
declare -A SEEN
CORPUS=()
add_dir() {
  local d="$1" f b
  [[ -d "$d" ]] || return 0
  shopt -s nullglob
  for f in "$d"/*.kl; do
    b=$(basename "$f")
    [[ -n "${SEEN[$b]:-}" ]] && continue   # de-dupe by basename
    SEEN[$b]=1; CORPUS+=("$f")
  done
}
if [[ -n "${DIFF_CORPUS:-}" ]]; then
  add_dir "$DIFF_CORPUS"
else
  add_dir "$ROOT/../kinglet-bootstrap/tests/cli/cases"
  add_dir "$ROOT/../kinglet-bootstrap/tests/probe/cases"
fi
if [[ ${#CORPUS[@]} -eq 0 ]]; then
  echo "no corpus .kl files found (set DIFF_CORPUS=/path/to/dir)" >&2
  exit 2
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# compile: $1=bin $2=src $3=out.kbc ; prints exit code, stderr -> $3.err
compile() { "$1" --save-bytecode "$3" "$2" >/dev/null 2>"$3.err"; echo $?; }
# run a .kl: $1=bin $2=src $3=tag ; stdout -> $3.out, stderr -> $3.err ; returns rc
run_prog() { "$1" "$2" >"$3.out" 2>"$3.err"; return $?; }

printf '| %-26s | %-7s | %-10s | %-9s | %s |\n' "case" "compile" "bytecode" "behavior" "note"
printf '|%s|%s|%s|%s|%s|\n' "----------------------------" "---------" "------------" "-----------" "--------------------"

total=0; bc_same=0; bc_diff=0; sh_only_fail=0; bs_only_fail=0; both_fail=0
beh_same=0; beh_diff=0; beh_na=0
divergent=()

for src in "${CORPUS[@]}"; do
  name=$(basename "$src" .kl)
  total=$((total + 1))
  bskbc="$TMP/$name.bs.kbc"; shkbc="$TMP/$name.sh.kbc"

  ec_bs=$(compile "$BS" "$src" "$bskbc")
  ec_sh=$(compile "$SH" "$src" "$shkbc")

  compile_cell=""; bc_cell="-"; beh_cell="-"; note=""

  if [[ "$ec_bs" == 0 && "$ec_sh" == 0 ]]; then
    compile_cell="both"
    if cmp -s "$bskbc" "$shkbc"; then
      bc_cell="identical"; bc_same=$((bc_same + 1))
    else
      bc_cell="DIFFER"; bc_diff=$((bc_diff + 1))
      sz_bs=$(wc -c <"$bskbc"); sz_sh=$(wc -c <"$shkbc")
      off=$(cmp "$bskbc" "$shkbc" 2>/dev/null | sed -n 's/.*byte \([0-9]*\).*/\1/p')
      note="bc: bs=${sz_bs}B sh=${sz_sh}B @byte${off:-?}"
      divergent+=("$name [bytecode] bs=${sz_bs}B sh=${sz_sh}B first-diff@byte${off:-?}")
    fi

    # behavior diff (only meaningful when both compiled)
    run_prog "$BS" "$src" "$TMP/$name.bs"; rc_bs=$?
    run_prog "$SH" "$src" "$TMP/$name.sh"; rc_sh=$?
    strip_cr "$TMP/$name.bs.out" "$TMP/$name.sh.out"
    if [[ "$rc_bs" == "$rc_sh" ]] && cmp -s "$TMP/$name.bs.out" "$TMP/$name.sh.out"; then
      beh_cell="identical"; beh_same=$((beh_same + 1))
    else
      beh_cell="DIFFER"; beh_diff=$((beh_diff + 1))
      bdesc="exit bs=$rc_bs sh=$rc_sh"
      cmp -s "$TMP/$name.bs.out" "$TMP/$name.sh.out" || bdesc="$bdesc, stdout differs"
      note="${note:+$note; }$bdesc"
      divergent+=("$name [behavior] $bdesc")
    fi

  elif [[ "$ec_bs" == 0 && "$ec_sh" != 0 ]]; then
    compile_cell="sh✗"; sh_only_fail=$((sh_only_fail + 1)); beh_na=$((beh_na + 1))
    msg=$(head -1 "$shkbc.err" 2>/dev/null)
    note="sh: $msg"
    divergent+=("$name [sh-compile-fail] $msg")

  elif [[ "$ec_bs" != 0 && "$ec_sh" == 0 ]]; then
    compile_cell="bs✗"; bs_only_fail=$((bs_only_fail + 1)); beh_na=$((beh_na + 1))
    msg=$(head -1 "$bskbc.err" 2>/dev/null)
    note="bs: $msg"
    divergent+=("$name [bs-compile-fail] $msg")

  else
    compile_cell="both✗"; both_fail=$((both_fail + 1)); beh_na=$((beh_na + 1))
    note="both reject"
  fi

  printf '| %-26s | %-7s | %-10s | %-9s | %s |\n' "$name" "$compile_cell" "$bc_cell" "$beh_cell" "$note"
done

echo
echo "## Summary (sh vs bs over $total cases)"
echo "compile : both accepted=$((bc_same + bc_diff)), sh✗=$sh_only_fail (sh strictly behind), bs✗=$bs_only_fail, both✗=$both_fail"
echo "bytecode: identical=$bc_same, DIFFER=$bc_diff   (of cases both accepted)"
echo "behavior: identical=$beh_same, DIFFER=$beh_diff, n/a=$beh_na"
echo

# Harness sanity hint: if bs rejects (almost) everything, the --save-bytecode
# contract probably differs, not the language.
if [[ "$bs_only_fail" -gt 0 && "$((bc_same + bc_diff + beh_same))" -eq 0 ]]; then
  echo "NOTE: bootstrap rejected every case -- its compile invocation likely differs"
  echo "      from '$BS --save-bytecode <out> <src>'. Check the bs CLI contract." >&2
  echo
fi

if [[ ${#divergent[@]} -gt 0 ]]; then
  echo "## Divergences (the measured sh<->bs gap)"
  for d in "${divergent[@]}"; do echo "  - $d"; done
else
  echo "No divergences: sh matches bs byte-for-byte and behaviorally across the whole corpus."
fi

exit 0
