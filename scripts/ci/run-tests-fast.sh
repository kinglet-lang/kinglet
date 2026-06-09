#!/usr/bin/env bash
# Fast CI tier: Ref build + selfhost suites (no Shadow parity).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT"
echo "KINGLET_BOOTSTRAP=$KINGLET_BOOTSTRAP"
echo "KINGLET (VM)=$KINGLET_BIN"

bash "$ROOT/scripts/ci/setup-fixtures.sh"
bash "$ROOT/backend/vm/build.sh"
bash "$ROOT/tests/run_all.sh"
