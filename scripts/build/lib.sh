#!/usr/bin/env bash
# Klos + stamp helpers for kinglet build (ADR 0014 M0).
# Sourced by build.sh and tests/common.sh — do not execute directly.

set -euo pipefail

# Locate project root (directory containing kinglet.toml).
find_project_root() {
  local dir="${1:-$(pwd)}"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/kinglet.toml" ]]; then
      printf '%s' "$(cd "$dir" && pwd)"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# Minimal TOML scalar reader: get_build_config <root> <key> <default>
get_build_config() {
  local root="$1" key="$2" default="${3:-}"
  local file="$root/kinglet.toml"
  local line val
  if [[ ! -f "$file" ]]; then
    printf '%s' "$default"
    return 0
  fi
  case "$key" in
    root)
      line=$(grep -E '^[[:space:]]*root[[:space:]]*=' "$file" 2>/dev/null | head -1 || true)
      ;;
    cache_dir)
      line=$(grep -E '^[[:space:]]*cache_dir[[:space:]]*=' "$file" 2>/dev/null | head -1 || true)
      ;;
    out_dir)
      line=$(grep -E '^[[:space:]]*out_dir[[:space:]]*=' "$file" 2>/dev/null | head -1 || true)
      ;;
    engine)
      line=$(grep -E '^[[:space:]]*engine[[:space:]]*=' "$file" 2>/dev/null | head -1 || true)
      ;;
    default_backend)
      line=$(grep -E '^[[:space:]]*default_backend[[:space:]]*=' "$file" 2>/dev/null | head -1 || true)
      ;;
    shadow_root)
      line=$(grep -E '^[[:space:]]*shadow_root[[:space:]]*=' "$file" 2>/dev/null | head -1 || true)
      ;;
    *)
      printf '%s' "$default"
      return 0
      ;;
  esac
  if [[ -z "$line" ]]; then
    printf '%s' "$default"
    return 0
  fi
  val=$(printf '%s' "$line" | sed -E 's/^[^=]*=[[:space:]]*//' | sed -E 's/^["'\''](.*)["'\'']$/\1/')
  if [[ -n "$val" ]]; then
    printf '%s' "$val"
  else
    printf '%s' "$default"
  fi
}

kinglet_layout_dirs() {
  local root="$1"
  local cache_rel out_rel
  cache_rel=$(get_build_config "$root" cache_dir ".kinglet/cache")
  out_rel=$(get_build_config "$root" out_dir ".kinglet/out")
  KINGLET_CACHE_DIR="$root/$cache_rel"
  KINGLET_OUT_DIR="$root/$out_rel"
  KINGLET_OBJECTS_DIR="$root/.kinglet/objects"
  KINGLET_STAMPS_DIR="$root/.kinglet/stamps"
}

ensure_kinglet_dirs() {
  local root="$1"
  kinglet_layout_dirs "$root"
  mkdir -p "$KINGLET_CACHE_DIR" "$KINGLET_OUT_DIR" "$KINGLET_OBJECTS_DIR" "$KINGLET_STAMPS_DIR"
}

bootstrap_compiler_id() {
  local bootstrap="$1"
  local ver
  if ver=$("$bootstrap" --version 2>/dev/null); then
    printf 'version:%s' "$ver"
  else
    shasum -a 256 "$bootstrap" | awk '{print "bin:" $1}'
  fi
}

# Hash of libkinglet_rt linked by native builds (ABI / runtime changes invalidate stamp).
bootstrap_rt_id() {
  local bootstrap="$1"
  local dir rt
  dir=$(cd "$(dirname "$bootstrap")" && pwd)
  for rt in \
    "$dir/obj/runtime/libkinglet_rt.a" \
    "$dir/libkinglet_rt.a" \
    "$dir/../obj/runtime/libkinglet_rt.a"; do
    if [[ -f "$rt" ]]; then
      shasum -a 256 "$rt" | awk '{print $1}'
      return 0
    fi
  done
  printf 'missing'
}

compiler_source_manifest() {
  local root="$1"
  local f rel
  {
    for f in \
      "$root"/core/*.kl \
      "$root"/parser/*.kl \
      "$root"/compiler/*.kl \
      "$root"/checker/*.kl \
      "$root"/lexer/*.kl; do
      [[ -f "$f" ]] || continue
      rel="${f#"$root"/}"
      printf '%s\t' "$rel"
      shasum -a 256 "$f" | awk '{print $1}'
    done
  } | LC_ALL=C sort
}

compute_compiler_stamp() {
  local root="$1" bootstrap="$2" backend_override="${3:-}"
  local tmp
  local build_root engine backend strip_debug
  build_root=$(get_build_config "$root" root "core/main.kl")
  engine=$(get_build_config "$root" engine "ref")
  backend=$(get_build_config "$root" default_backend "vm")
  if [[ -n "$backend_override" ]]; then
    backend="$backend_override"
  fi
  strip_debug="${KINGLET_STRIP_DEBUG:-0}"
  tmp=$(mktemp)
  {
    printf 'target:compiler\n'
    printf 'root:%s\n' "$build_root"
    printf 'engine:%s\n' "$engine"
    printf 'backend:%s\n' "$backend"
    printf 'strip_debug:%s\n' "$strip_debug"
    printf 'bootstrap:%s\n' "$(bootstrap_compiler_id "$bootstrap")"
    printf 'rt_version:%s\n' "$(bootstrap_rt_id "$bootstrap")"
    if [[ -f "$root/kinglet.toml" ]]; then
      printf 'kinglet.toml:%s\n' "$(shasum -a 256 "$root/kinglet.toml" | awk '{print $1}')"
    fi
    compiler_source_manifest "$root"
  } >"$tmp"
  shasum -a 256 "$tmp" | awk '{print $1}'
  rm -f "$tmp"
}

object_id_for_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

klos_write_object() {
  local root="$1" object_id="$2" src_path="$3" kind="$4" stamp="$5" producer="$6"
  kinglet_layout_dirs "$root"
  local dest="$KINGLET_OBJECTS_DIR/$object_id"
  local meta="$KINGLET_OBJECTS_DIR/$object_id.meta"
  if [[ ! -f "$dest" ]]; then
    cp "$src_path" "$dest"
  fi
  cat >"$meta" <<EOF
kind=$kind
stamp=$stamp
producer=$producer
size=$(wc -c <"$dest" | tr -d ' ')
created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

klos_meta_get() {
  local meta="$1" key="$2"
  grep -E "^${key}=" "$meta" 2>/dev/null | head -1 | cut -d= -f2- || true
}

stamp_read() {
  local root="$1" target="$2"
  kinglet_layout_dirs "$root"
  local f="$KINGLET_STAMPS_DIR/$target"
  if [[ -f "$f" ]]; then
    tr -d '[:space:]' <"$f"
  fi
}

stamp_write() {
  local root="$1" target="$2" stamp="$3" object_id="$4"
  kinglet_layout_dirs "$root"
  printf '%s' "$stamp" >"$KINGLET_STAMPS_DIR/$target"
  printf '%s' "$object_id" >"$KINGLET_STAMPS_DIR/$target.object"
}

stamp_object_id() {
  local root="$1" target="$2"
  kinglet_layout_dirs "$root"
  local f="$KINGLET_STAMPS_DIR/$target.object"
  if [[ -f "$f" ]]; then
    tr -d '[:space:]' <"$f"
  fi
}

install_out_artifact() {
  local root="$1" src="$2" name="$3"
  kinglet_layout_dirs "$root"
  local out="$KINGLET_OUT_DIR/$name"
  rm -f "$out"
  cp "$src" "$out"
  printf '%s' "$out"
}
