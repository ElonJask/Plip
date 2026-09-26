#!/bin/bash
# 用 Electron 打包当前系统。macOS 只打本机架构，Windows 在 Windows runner 上打。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
export PYTHON="${PYTHON:-/usr/bin/python3}"
cd electron
npm install
if [[ "$(uname -s)" == "Darwin" ]]; then
  case "$(uname -m)" in
    arm64) EB_ARCH="arm64"; OUT_ARCH="arm64" ;;
    x86_64) EB_ARCH="x64"; OUT_ARCH="x86_64" ;;
    *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
  esac
  npx --yes electron-builder@25.1.8 --mac zip --"$EB_ARCH" \
    --config.extraMetadata.version="$VERSION"
  built="dist/Plip-v${VERSION}-macos-${EB_ARCH}.zip"
  mkdir -p ../artifacts
  cp "$built" "../artifacts/Plip-v${VERSION}-macos-${OUT_ARCH}.zip"
else
  npx --yes electron-builder@25.1.8 --win zip \
    --config.extraMetadata.version="$VERSION"
  mkdir -p ../artifacts
  cp "dist/Plip-v${VERSION}-windows-x64.zip" "../artifacts/Plip-v${VERSION}-windows-x64.zip"
fi
echo "Archive ready"
