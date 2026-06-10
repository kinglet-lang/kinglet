#!/usr/bin/env bash
# Incremental native build smoke: per-module object cache reuses unchanged
# modules and re-emits only edited ones before the relink.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT" || exit 2
BOOTSTRAP="${KINGLET_BOOTSTRAP:-}"
TMP_DIR="$(mktemp -d)"
CACHE_DIR="$TMP_DIR/objcache"
FAILURES=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

probe_native() {
  local err="$TMP_DIR/probe.err"
  local out="$TMP_DIR/probe.bin"
  local probe="$ROOT/tests/native/cases/just42.kl"
  if "$BOOTSTRAP" --native "$out" "$probe" 2>"$err"; then
    return 0
  fi
  if grep -q 'native backend not built' "$err"; then
    echo "SKIP incremental smoke: bootstrap built without enable_llvm=true" >&2
    exit 0
  fi
  echo "native probe failed:" >&2
  cat "$err" >&2
  exit 1
}

fail() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

probe_native

cat >"$TMP_DIR/util.kl" <<'EOF'
pub int triple(int x) {
  return x * 3;
}
EOF
cat >"$TMP_DIR/main.kl" <<'EOF'
import { "util.kl" }

int main() {
  return util::triple(14);
}
EOF

build() {
  "$BOOTSTRAP" --native "$TMP_DIR/prog" --obj-cache "$CACHE_DIR" "$TMP_DIR/main.kl" \
    2>"$TMP_DIR/build.err" || {
    echo "build failed:" >&2
    cat "$TMP_DIR/build.err" >&2
    exit 1
  }
}

run_prog() {
  local ec=0
  "$TMP_DIR/prog" || ec=$?
  printf '%s' "$ec"
}

object_snapshot() {
  ls "$CACHE_DIR"/*.o 2>/dev/null | while IFS= read -r f; do
    printf '%s %s\n' "$f" "$(date -r "$f" +%s 2>/dev/null || stat -c %Y "$f")"
  done | LC_ALL=C sort
}

# 1. Cold build populates one object per module.
build
[[ "$(run_prog)" == "42" ]] || fail "cold build: expected exit 42"
count=$(ls "$CACHE_DIR"/*.o 2>/dev/null | wc -l | tr -d ' ')
[[ "$count" == "2" ]] || fail "cold build: expected 2 cached objects, got $count"
snap1=$(object_snapshot)

# 2. No-change rebuild reuses every cached object.
sleep 1
build
snap2=$(object_snapshot)
[[ "$snap1" == "$snap2" ]] || fail "no-change rebuild touched cached objects"

# 3. Editing one module re-emits only that module.
cat >"$TMP_DIR/util.kl" <<'EOF'
pub int triple(int x) {
  return x * 3 + 3;
}
EOF
sleep 1
build
[[ "$(run_prog)" == "45" ]] || fail "incremental build: expected exit 45"
count=$(ls "$CACHE_DIR"/*.o 2>/dev/null | wc -l | tr -d ' ')
[[ "$count" == "3" ]] || fail "incremental build: expected 3 cached objects, got $count"
snap3=$(object_snapshot)
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if ! grep -qxF "$line" <<<"$snap3"; then
    fail "incremental build replaced unchanged cached object: $line"
  fi
done <<<"$snap1"

if [[ "$FAILURES" -ne 0 ]]; then
  echo "Incremental native smoke failed: $FAILURES" >&2
  exit 1
fi
echo "Incremental native smoke passed."
