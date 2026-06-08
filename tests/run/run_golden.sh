#!/usr/bin/env bash
# Deprecated: behavioral tests moved to tests/exec/ (decision 0012).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
echo "NOTE: tests/run/ is retired; running tests/exec/run.sh" >&2
exec bash "$ROOT/tests/exec/run.sh"
