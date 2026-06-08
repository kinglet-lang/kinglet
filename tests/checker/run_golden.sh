#!/usr/bin/env bash
# Deprecated: checker tests moved to tests/sema/ (decision 0012).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
echo "NOTE: tests/checker/ is retired; running tests/sema/run.sh" >&2
exec bash "$ROOT/tests/sema/run.sh"
