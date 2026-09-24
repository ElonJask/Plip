#!/bin/bash
# 编译 release 并组装 Plip.app。
# ARCH 只能是当前机器的 arm64 或 x86_64。另一种架构由对应的 GitHub runner 编译。
# 发布签名：CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" bash Scripts/make_app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${CODESIGN_IDENTITY:--}"
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64) SUFFIX="macos-arm64" ;;
  x86_64) SUFFIX="macos-x86_64" ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

APP="artifacts/Plip-${SUFFIX}.app"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/plip.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

HOST="$(uname -m)"
if [[ "$ARCH" != "$HOST" ]]; then
  echo "ARCH=$ARCH but this machine is $HOST; build on the matching runner" >&2
  exit 1
fi
swift build -c release --disable-sandbox
if [[ "${SKIP_TEST:-}" != "1" ]]; then
  swift test --disable-sandbox
fi
bash Scripts/check_version.sh

BIN="$(swift build -c release --disable-sandbox --show-bin-path)/CraftAudio"
if [[ ! -f "$BIN" ]]; then
  echo "missing binary for $ARCH: $BIN" >&2
  exit 1
fi
mkdir -p "$STAGE/Plip.app/Contents/MacOS" "$STAGE/Plip.app/Contents/Resources"
cp "$BIN" "$STAGE/Plip.app/Contents/MacOS/Plip"
rsync -a --exclude '.DS_Store' --exclude '._*' Soundpacks "$STAGE/Plip.app/Contents/Resources/"
	cp ui/panel.html "$STAGE/Plip.app/Contents/Resources/panel.html"
cp Info.plist "$STAGE/Plip.app/Contents/"
xattr -c "$STAGE/Plip.app/Contents/Info.plist"

codesign --force --sign "$IDENTITY" "$STAGE/Plip.app"
codesign --verify --deep --strict "$STAGE/Plip.app"
ARCHS="$(lipo -archs "$STAGE/Plip.app/Contents/MacOS/Plip")"
if [[ "$ARCHS" != "$ARCH" ]]; then
  echo "binary arch is '$ARCHS', expected $ARCH" >&2
  exit 1
fi

mkdir -p artifacts
rm -rf "$APP"
ditto "$STAGE/Plip.app" "$APP"

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
ZIP="artifacts/Plip-v${VERSION}-${SUFFIX}.zip"
rm -f "$ZIP"
# 磁盘副本带架构后缀，压缩包根目录必须仍是 Plip.app。
SHIP="$(mktemp -d "${TMPDIR:-/tmp}/plip-ship.XXXXXX")"
ditto "$STAGE/Plip.app" "$SHIP/Plip.app"
ditto -c -k --keepParent "$SHIP/Plip.app" "$ZIP"
rm -rf "$SHIP" "$STAGE"
trap - EXIT

echo "Built $APP"
echo "Archive $ZIP"
if [[ "$IDENTITY" == "-" ]]; then
  echo "签名：ad-hoc。开机自启需要 Developer ID，并把应用放到 /Applications。"
fi
