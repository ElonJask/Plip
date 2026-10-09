#!/bin/bash
# 用 Electron 打包当前系统。macOS 只打本机架构，Windows 在 Windows runner 上打。
set -euo pipefail
cd "$(dirname "$0")/.."

bash Scripts/check_version.sh
VERSION="$(tr -d '[:space:]' < VERSION)"
export PYTHON="${PYTHON:-/usr/bin/python3}"
cd electron
npm ci
npm test
mkdir -p ../artifacts
if [[ "$(uname -s)" == "Darwin" ]]; then
  case "$(uname -m)" in
    arm64) EB_ARCH="arm64"; OUT_ARCH="arm64" ;;
    x86_64) EB_ARCH="x64"; OUT_ARCH="x86_64" ;;
    *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
  esac
  npx electron-builder --mac zip --"$EB_ARCH" \
    --config.extraMetadata.version="$VERSION"
  cp "dist/Plip-v${VERSION}-macos-${EB_ARCH}.zip" "../artifacts/Plip-v${VERSION}-macos-${OUT_ARCH}.zip"
else
  npx electron-builder --win zip --x64 \
    --config.extraMetadata.version="$VERSION"
  cp "dist/Plip-v${VERSION}-windows-x64.zip" "../artifacts/Plip-v${VERSION}-windows-x64.zip"
fi
echo "Archive ready"
