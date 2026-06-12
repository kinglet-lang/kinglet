#!/usr/bin/env bash
# Shadow vs Ref parity orchestration (ADR 0014 M2).
#
# Usage:
#   prove.sh [--quiet] [project_root]
#
# Runs self-host round-trip and differential suites. Ref compiler artefact comes
# from kinglet build (bootstrap); Shadow path uses compiler.kbc on the VM.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet)
      QUIET=1
      shift
      ;;
    *)
      break
      ;;
  esac
done

ROOT="${1:-}"
if [[ -z "$ROOT" ]]; then
  ROOT=$(find_project_root "$(pwd)") || {
    echo "kinglet prove: no kinglet.toml found" >&2
    exit 2
  }
fi
ROOT=$(cd "$ROOT" && pwd)

# shellcheck source=/dev/null
source "$ROOT/tests/common.sh"
export_kinglet_bins "$ROOT" || exit 2

SHADOW_ROOT=$(get_build_config "$ROOT" shadow_root "core/main.kl")
ENTRY="$ROOT/$SHADOW_ROOT"
if [[ ! -f "$ENTRY" ]]; then
  echo "kinglet prove: shadow_root not found: $ENTRY" >&2
  exit 2
fi

run_step() {
  local name="$1" script="$2"
  if [[ "$QUIET" -eq 0 ]]; then
    echo "=== kinglet prove: $name ===" >&2
  fi
  if bash "$script"; then
    [[ "$QUIET" -eq 0 ]] && echo "✓ $name" >&2
    return 0
  fi
  echo "✗ kinglet prove failed at: $name" >&2
  return 1
}

if [[ "$QUIET" -eq 0 ]]; then
  echo "kinglet prove: shadow_root=$SHADOW_ROOT" >&2
fi

# Ref artefact only (bootstrap via kinglet build); no Shadow compile here.
ensure_build_stamp "$ROOT" >/dev/null || exit 2

FAIL=0
run_step "selfhost round-trip" "$ROOT/tests/selfhost/run_roundtrip.sh" || FAIL=1
run_step "differential (gating)" "$ROOT/tests/differential/run.sh" || FAIL=1

if [[ "$QUIET" -eq 0 ]]; then
  echo "=== kinglet prove: differential matrix (snapshot) ===" >&2
fi
bash "$ROOT/tests/differential/run_matrix.sh" || FAIL=1

if [[ "$FAIL" -eq 0 ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "=== kinglet prove PASSED ===" >&2
  exit 0
fi
exit 1
