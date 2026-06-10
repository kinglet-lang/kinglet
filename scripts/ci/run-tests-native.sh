#!/usr/bin/env bash
# Native smoke tier: bootstrap with LLVM + tests/native/run_smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

BOOTSTRAP="$(bash "$ROOT/scripts/ci/build-bootstrap-llvm.sh")"
export KINGLET_BOOTSTRAP="$BOOTSTRAP"
echo "KINGLET_BOOTSTRAP=$KINGLET_BOOTSTRAP"

bash "$ROOT/tests/native/run_smoke.sh"
bash "$ROOT/tests/native/run_driver_smoke.sh"
bash "$ROOT/tests/native/run_incremental_smoke.sh"
