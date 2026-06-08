#!/usr/bin/env bash
# Regenerate tests/codegen/cases/*.bytecode from selfhost --bytecode output.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT" || exit 2
CLI_KBC=$(ensure_cli_kbc "$ROOT") || exit 2

CASES_DIR="$ROOT/tests/codegen/cases"
count=0

for src in "$CASES_DIR"/*.kl; do
  name=$(basename "$src" .kl)
  golden="$CASES_DIR/$name.bytecode"
  err="$CASES_DIR/$name.refresh.err"
  if ! run_kbc "$CLI_KBC" --bytecode "$src" >"$golden" 2>"$err"; then
    echo "FAIL $name: --bytecode exited non-zero" >&2
    cat "$err" >&2
    rm -f "$err"
    exit 1
  fi
  strip_cr "$golden"
  rm -f "$err"
  count=$((count + 1))
  echo "wrote $golden"
done

echo "Refreshed $count bytecode golden(s)."
