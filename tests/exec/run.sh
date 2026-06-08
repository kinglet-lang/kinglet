#!/usr/bin/env bash
# End-to-end tests via the selfhost pipeline (decision 0012).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "$ROOT/tests/harness/run.sh" "$ROOT/tests/exec/cases"
