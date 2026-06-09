#!/usr/bin/env bash
# Local CI reproduction: fast tier (same as GitHub Actions test-fast job).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "$ROOT/scripts/ci/run-tests-fast.sh"
