#!/usr/bin/env bash
# Stamp helpers for kinglet build (ADR 0014 M0).
# Sourced by stamp.sh and later build scripts.

set -euo pipefail

# Fingerprint of the bootstrap compiler binary.
bootstrap_compiler_id() {
  local bootstrap="$1"
  local ver
  if ver=$("$bootstrap" --version 2>/dev/null); then
    printf 'version:%s' "$ver"
  else
    shasum -a 256 "$bootstrap" | awk '{print "bin:" $1}'
  fi
}

# Sorted content hashes for compiler source trees.
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

# Stamp for the toolchain compiler artefact (ADR 0014).
compute_compiler_stamp() {
  local root="$1" bootstrap="$2"
  local tmp
  local strip_debug="${KINGLET_STRIP_DEBUG:-0}"
  tmp=$(mktemp)
  {
    printf 'target:compiler\n'
    printf 'root:core/main.kl\n'
    printf 'engine:ref\n'
    printf 'backend:vm\n'
    printf 'strip_debug:%s\n' "$strip_debug"
    printf 'bootstrap:%s\n' "$(bootstrap_compiler_id "$bootstrap")"
    if [[ -f "$root/kinglet.toml" ]]; then
      printf 'kinglet.toml:%s\n' "$(shasum -a 256 "$root/kinglet.toml" | awk '{print $1}')"
    fi
    compiler_source_manifest "$root"
  } >"$tmp"
  shasum -a 256 "$tmp" | awk '{print $1}'
  rm -f "$tmp"
}
