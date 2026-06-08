#!/usr/bin/env bash
# Build backend/vm kinglet (bytecode VM host for selfhost test suites).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SCRIPT_DIR/out/kinglet"
mkdir -p "$SCRIPT_DIR/out"

g++ -std=c++17 -O2 -Wall -Wextra \
  -I"$SCRIPT_DIR/.." \
  "$SCRIPT_DIR/chunk.cc" \
  "$SCRIPT_DIR/cow.cc" \
  "$SCRIPT_DIR/value.cc" \
  "$SCRIPT_DIR/vm.cc" \
  "$SCRIPT_DIR/vm_main.cc" \
  -o "$OUT"

echo "built $OUT" >&2
