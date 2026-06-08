#!/usr/bin/env bash
# Deprecated alias for the snapshot matrix.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
echo "NOTE: run_diff.sh renamed to run_matrix.sh" >&2
exec bash "$ROOT/tests/differential/run_matrix.sh"
