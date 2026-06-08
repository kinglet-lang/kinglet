#!/usr/bin/env bash
# Property tests: round-trip stability + fuzz-lite (decision 0012 phase 5).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bash "$ROOT/tests/property/run_roundtrip.sh" && bash "$ROOT/tests/property/run_fuzz.sh"
