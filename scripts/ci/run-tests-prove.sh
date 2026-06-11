#!/usr/bin/env bash
# Prove CI tier: Shadow vs Ref parity (round-trip + differential).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT"
echo "KINGLET_BOOTSTRAP=$KINGLET_BOOTSTRAP"
echo "KINGLET (VM)=$KINGLET_BIN"

bash "$ROOT/scripts/ci/setup-fixtures.sh"
bash "$ROOT/kinglet" prove
