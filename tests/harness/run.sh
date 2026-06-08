#!/usr/bin/env bash
# Unified test harness (decision 0012). Parses per-case directives and runs pipelines.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

KINGLET_BIN=""
BOOTSTRAP_BIN=""
CLI_KBC=""
TMP=""
FAILURES=0
PASSED=0
SKIPPED=0

# Per-case state (bash 3.x — no associative arrays).
RUN=""
COMPILE_FAIL=0
EXPECT_STDOUT=""
EXPECT_STDERR=""
EXPECT_EXIT=""
CHECK_LINES=""
CHECK_NOT_LINES=""
CHECK_ERR_LINES=""
CHECK_ERR_AT=""

cleanup() { [[ -n "$TMP" ]] && rm -rf "$TMP"; }
trap cleanup EXIT

reset_case() {
  RUN=""
  COMPILE_FAIL=0
  EXPECT_STDOUT=""
  EXPECT_STDERR=""
  EXPECT_EXIT=""
  CHECK_LINES=""
  CHECK_NOT_LINES=""
  CHECK_ERR_LINES=""
  CHECK_ERR_AT=""
}

trim() { echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

is_directive_line() {
  case "$1" in
    //\ RUN:*|//\ EXPECT-*|//\ CHECK:*|//\ CHECK-NOT:*|//\ CHECK-ERR:*|//\ CHECK-ERR-AT:*|//\ COMPILE-FAIL*) return 0 ;;
    *) return 1 ;;
  esac
}

parse_directives() {
  local f="$1"
  reset_case
  local in_block=1
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$in_block" -eq 1 && -z "$(trim "$line")" ]]; then
      continue
    fi
    if [[ "$in_block" -eq 1 ]] && is_directive_line "$line"; then
      case "$line" in
        //\ RUN:*)
          RUN=$(trim "${line#// RUN:}")
          ;;
        //\ EXPECT-STDOUT:*)
          EXPECT_STDOUT=$(trim "${line#// EXPECT-STDOUT:}")
          ;;
        //\ EXPECT-STDERR:*)
          EXPECT_STDERR=$(trim "${line#// EXPECT-STDERR:}")
          ;;
        //\ EXPECT-EXIT:*)
          EXPECT_EXIT=$(trim "${line#// EXPECT-EXIT:}")
          ;;
        //\ CHECK-NOT:*)
          CHECK_NOT_LINES="${CHECK_NOT_LINES}$(trim "${line#// CHECK-NOT:}")"$'\n'
          ;;
        //\ CHECK-ERR-AT:*)
          CHECK_ERR_AT=$(trim "${line#// CHECK-ERR-AT:}")
          ;;
        //\ CHECK-ERR:*)
          CHECK_ERR_LINES="${CHECK_ERR_LINES}$(trim "${line#// CHECK-ERR:}")"$'\n'
          ;;
        //\ CHECK:*)
          CHECK_LINES="${CHECK_LINES}$(trim "${line#// CHECK:}")"$'\n'
          ;;
        //\ COMPILE-FAIL)
          COMPILE_FAIL=1
          ;;
      esac
      continue
    fi
    in_block=0
    break
  done <"$f"

  local base="${f%.kl}"
  if [[ -z "$EXPECT_STDOUT" && -f "${base}.expected" ]]; then
    EXPECT_STDOUT=$(cat "${base}.expected")
  fi
  if [[ -z "$EXPECT_EXIT" && -f "${base}.exit" ]]; then
    EXPECT_EXIT=$(cat "${base}.exit")
  fi
  if [[ -z "$CHECK_ERR_LINES" && -f "${base}.stderr_contains" ]]; then
    CHECK_ERR_LINES=$(cat "${base}.stderr_contains")$'\n'
  fi
  if [[ -z "$EXPECT_EXIT" ]]; then
    EXPECT_EXIT=0
  fi
}

fail_case() {
  local name="$1"
  shift
  echo "FAIL  $name: $*" >&2
  FAILURES=$((FAILURES + 1))
}

pass_case() {
  local name="$1"
  echo "PASS  $name"
  PASSED=$((PASSED + 1))
}

skip_case() {
  local name="$1"
  local reason="$2"
  echo "SKIP  $name ($reason)" >&2
  SKIPPED=$((SKIPPED + 1))
}

assert_output() {
  local name="$1"
  local label="$2"
  local expect="$3"
  local actual="$4"
  if [[ "$expect" != "$actual" ]]; then
    fail_case "$name" "$label mismatch (want=$(printf '%q' "$expect") got=$(printf '%q' "$actual"))"
    return 1
  fi
  return 0
}

assert_exit() {
  local name="$1"
  local want="$2"
  local got="$3"
  if [[ "$want" != "$got" ]]; then
    fail_case "$name" "exit want=$want got=$got"
    return 1
  fi
  return 0
}

assert_substr() {
  local name="$1"
  local haystack="$2"
  local needle="$3"
  local label="$4"
  if ! grep -qF "$needle" <<<"$haystack"; then
    fail_case "$name" "$label missing $(printf '%q' "$needle")"
    echo "      stderr/stdout was:" >&2
    echo "$haystack" | sed 's/^/        /' >&2
    return 1
  fi
  return 0
}

assert_substr_not() {
  local name="$1"
  local haystack="$2"
  local needle="$3"
  if grep -qF "$needle" <<<"$haystack"; then
    fail_case "$name" "unexpected $(printf '%q' "$needle")"
    return 1
  fi
  return 0
}

assert_check_list() {
  local name="$1"
  local haystack="$2"
  local list="$3"
  local label="$4"
  local ok=0
  local item
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    if ! assert_substr "$name" "$haystack" "$item" "$label"; then
      ok=1
    fi
  done <<<"$list"
  return $ok
}

run_selfhost_pipeline() {
  local src="$1"
  local kbc="$2"
  local stdout="$3"
  local stderr="$4"
  local compile_ec=0
  compile_selfhost "$CLI_KBC" "$src" "$kbc" 2>"$stderr" || compile_ec=$?
  if [[ "$COMPILE_FAIL" -eq 1 ]]; then
    echo "$compile_ec"
    return 0
  fi
  if [[ "$compile_ec" -ne 0 ]]; then
    echo "$compile_ec"
    return 0
  fi
  local run_ec=0
  run_kbc "$kbc" >"$stdout" 2>>"$stderr" || run_ec=$?
  echo "$run_ec"
}

run_bootstrap_pipeline() {
  local src="$1"
  local stdout="$2"
  local stderr="$3"
  local ec=0
  "$BOOTSTRAP_BIN" "$src" >"$stdout" 2>"$stderr" || ec=$?
  echo "$ec"
}

run_check_pipeline() {
  local src="$1"
  local stderr="$2"
  local ec=0
  "$KINGLET_BIN" --run "$CLI_KBC" "$src" --check >/dev/null 2>"$stderr" || ec=$?
  echo "$ec"
}

run_bytecode_pipeline() {
  local src="$1"
  local stdout="$2"
  local stderr="$3"
  local ec=0
  "$KINGLET_BIN" --run "$CLI_KBC" --bytecode "$src" >"$stdout" 2>"$stderr" || ec=$?
  echo "$ec"
}

run_ast_pipeline() {
  local src="$1"
  local stdout="$2"
  local stderr="$3"
  local ec=0
  "$KINGLET_BIN" --run "$CLI_KBC" --ast "$src" >"$stdout" 2>"$stderr" || ec=$?
  echo "$ec"
}

run_one_file() {
  local src="$1"
  local name="${src#$ROOT/}"
  parse_directives "$src"

  if [[ -z "$RUN" ]]; then
    skip_case "$name" "no RUN directive"
    return
  fi

  local stdout="$TMP/out.stdout"
  local stderr="$TMP/out.stderr"
  local kbc="$TMP/out.kbc"
  local ec=0
  local failed=0

  case "$RUN" in
    selfhost)
      ec=$(run_selfhost_pipeline "$src" "$kbc" "$stdout" "$stderr")
      strip_cr "$stdout" "$stderr"
      if [[ "$COMPILE_FAIL" -eq 1 ]]; then
        if [[ "$ec" -eq 0 ]] && ! grep -qE 'compile error|type error' "$stderr" 2>/dev/null; then
          fail_case "$name" "expected compile failure, got exit $ec"
          return
        fi
        assert_check_list "$name" "$stderr" "$CHECK_ERR_LINES" "stderr" && pass_case "$name" || true
        return
      fi
      assert_exit "$name" "$EXPECT_EXIT" "$ec" || failed=1
      if [[ "$failed" -eq 1 && -s "$stderr" ]]; then
        cat "$stderr" | sed 's/^/      /' >&2
      fi
      assert_output "$name" "stdout" "$EXPECT_STDOUT" "$(cat "$stdout")" || failed=1
      if [[ -n "$EXPECT_STDERR" || -z "$CHECK_ERR_LINES" ]]; then
        assert_output "$name" "stderr" "$EXPECT_STDERR" "$(cat "$stderr")" || failed=1
      fi
      assert_check_list "$name" "$(cat "$stdout")" "$CHECK_LINES" "stdout" || failed=1
      while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        assert_substr_not "$name" "$(cat "$stdout")" "$item" || failed=1
      done <<<"$CHECK_NOT_LINES"
      assert_check_list "$name" "$(cat "$stderr")" "$CHECK_ERR_LINES" "stderr" || failed=1
      if [[ -n "$CHECK_ERR_AT" ]]; then
        assert_substr "$name" "$(cat "$stderr")" "${CHECK_ERR_AT}:" "stderr at" || failed=1
      fi
      [[ "$failed" -eq 0 ]] && pass_case "$name"
      ;;

    check)
      ec=$(run_check_pipeline "$src" "$stderr")
      strip_cr "$stderr"
      if [[ "$COMPILE_FAIL" -eq 1 ]]; then
        if grep -q "OK: no type errors" "$stderr"; then
          fail_case "$name" "expected type errors, got OK"
          return
        fi
        assert_check_list "$name" "$stderr" "$CHECK_ERR_LINES" "stderr" || failed=1
        if [[ -n "$CHECK_ERR_AT" ]]; then
          assert_substr "$name" "$stderr" "${CHECK_ERR_AT}:" "stderr at" || failed=1
        fi
        [[ "$failed" -eq 0 ]] && pass_case "$name"
        return
      fi
      if ! grep -q "OK: no type errors" "$stderr"; then
        fail_case "$name" "expected OK: no type errors"
        cat "$stderr" | sed 's/^/      /' >&2
        return
      fi
      pass_case "$name"
      ;;

    diff)
      local bs_out="$TMP/bs.stdout" bs_err="$TMP/bs.stderr"
      local sh_out="$TMP/sh.stdout" sh_err="$TMP/sh.stderr"
      local bs_ec sh_ec
      bs_ec=$(run_bootstrap_pipeline "$src" "$bs_out" "$bs_err")
      sh_ec=$(run_selfhost_pipeline "$src" "$kbc" "$sh_out" "$sh_err")
      strip_cr "$bs_out" "$sh_out" "$bs_err" "$sh_err"
      if [[ "$bs_ec" -ne "$sh_ec" ]]; then
        fail_case "$name" "exit bootstrap=$bs_ec selfhost=$sh_ec"
        failed=1
      fi
      if ! diff -q "$bs_out" "$sh_out" >/dev/null 2>&1; then
        fail_case "$name" "stdout bootstrap vs selfhost differ"
        diff -u "$bs_out" "$sh_out" | sed 's/^/      /' | head -20 >&2
        failed=1
      fi
      [[ "$failed" -eq 0 ]] && pass_case "$name"
      ;;

    bytecode)
      ec=$(run_bytecode_pipeline "$src" "$stdout" "$stderr")
      strip_cr "$stdout" "$stderr"
      local golden="${src%.kl}.bytecode"
      if [[ -f "$golden" ]]; then
        if ! diff -u --strip-trailing-cr "$golden" "$stdout" >/dev/null; then
          fail_case "$name" "bytecode golden mismatch"
          diff -u --strip-trailing-cr "$golden" "$stdout" | sed 's/^/      /' | head -20 >&2
          return
        fi
        pass_case "$name"
        return
      fi
      if [[ -n "$CHECK_LINES" ]]; then
        assert_check_list "$name" "$(cat "$stdout")" "$CHECK_LINES" "stdout" || failed=1
        [[ "$failed" -eq 0 ]] && pass_case "$name"
        return
      fi
      skip_case "$name" "bytecode: no .bytecode golden or CHECK lines"
      ;;

    ast)
      ec=$(run_ast_pipeline "$src" "$stdout" "$stderr")
      strip_cr "$stdout" "$stderr"
      if [[ "$ec" -ne 0 ]]; then
        fail_case "$name" "ast dump failed (exit $ec)"
        cat "$stderr" | sed 's/^/      /' >&2
        return
      fi
      if [[ -n "$CHECK_LINES" ]]; then
        assert_check_list "$name" "$(cat "$stdout")" "$CHECK_LINES" "stdout" || failed=1
        [[ "$failed" -eq 0 ]] && pass_case "$name"
        return
      fi
      skip_case "$name" "ast: no CHECK lines"
      ;;

    *)
      skip_case "$name" "unknown RUN pipeline '$RUN'"
      ;;
  esac
}

collect_files() {
  local path="$1"
  if [[ -f "$path" && "$path" == *.kl ]]; then
    echo "$path"
    return
  fi
  if [[ -d "$path" ]]; then
    find "$path" -name '*.kl' -type f | sort
  fi
}

main() {
  if [[ "$#" -eq 0 ]]; then
    echo "usage: $0 <dir-or-file> ..." >&2
    echo "See tests/harness/directives.md" >&2
    exit 2
  fi

  KINGLET_BIN=$(resolve_kinglet "$ROOT") || exit 2
  BOOTSTRAP_BIN=$(resolve_bootstrap "$ROOT") || exit 2
  export KINGLET_BIN
  CLI_KBC=$(ensure_cli_kbc "$ROOT" "$KINGLET_BIN") || exit 2
  TMP="$(mktemp -d)"

  echo "Harness (selfhost via compiler.kbc; VM $KINGLET_BIN; bootstrap $BOOTSTRAP_BIN)"
  echo "================================="

  local path f
  for path in "$@"; do
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      run_one_file "$f"
    done < <(collect_files "$path")
  done

  echo "================================="
  echo "Passed: $PASSED  Failed: $FAILURES  Skipped: $SKIPPED"
  [[ "$FAILURES" -eq 0 ]]
}

main "$@"
