#!/usr/bin/env bash
# Print the current compiler build stamp.
# Usage: stamp.sh [project_root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

ROOT="${1:-}"
if [[ -z "$ROOT" ]]; then
  ROOT=$(find_project_root "$(pwd)") || {
    echo "stamp.sh: no kinglet.toml found" >&2
    exit 2
  }
fi
ROOT=$(cd "$ROOT" && pwd)

# shellcheck source=/dev/null
source "$ROOT/tests/common.sh"
BOOTSTRAP=$(resolve_bootstrap "$ROOT") || exit 2

compute_compiler_stamp "$ROOT" "$BOOTSTRAP"
