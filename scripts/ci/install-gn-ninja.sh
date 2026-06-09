#!/usr/bin/env bash
# Install GN and Ninja for bootstrap kinglet builds (same sources as kinglet-lang/bootstrap CI).
set -euo pipefail

mkdir -p "$HOME/bin"

case "${RUNNER_OS:-Linux}" in
  Windows)
    curl -fsSL -o gn.zip "https://chrome-infra-packages.appspot.com/dl/gn/gn/windows-amd64/+/latest"
    unzip -o gn.zip -d "$HOME/bin"
    ;;
  macOS)
    arch="$(uname -m)"
    if [[ "$arch" == "arm64" ]]; then
      curl -fsSL -o gn.zip "https://chrome-infra-packages.appspot.com/dl/gn/gn/mac-arm64/+/latest"
    else
      curl -fsSL -o gn.zip "https://chrome-infra-packages.appspot.com/dl/gn/gn/mac-amd64/+/latest"
    fi
    unzip -o gn.zip -d "$HOME/bin"
    chmod +x "$HOME/bin/gn"
    ;;
  Linux|*)
    curl -fsSL -o gn.zip "https://chrome-infra-packages.appspot.com/dl/gn/gn/linux-amd64/+/latest"
    unzip -o gn.zip -d "$HOME/bin"
    chmod +x "$HOME/bin/gn"
    ;;
esac

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$HOME/bin" >> "$GITHUB_PATH"
fi
export PATH="$HOME/bin:$PATH"
