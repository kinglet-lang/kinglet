#!/usr/bin/env bash
# Gating differential tests: bootstrap vs selfhost must match (decision 0012 phase 2).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "$ROOT/tests/harness/run.sh" "$ROOT/tests/differential/cases"
