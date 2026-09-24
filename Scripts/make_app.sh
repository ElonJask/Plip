#!/bin/bash
# 编译 release 并组装 Plip.app。
# 默认 ad-hoc 签名，只能本机调试，不能作为开机自启的发布包。
# 发布签名：CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" bash Scripts/make_app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${CODESIGN_IDENTITY:--}"
APP="artifacts/Plip.app"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/craftaudio.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

swift build -c release --disable-sandbox
swift test --disable-sandbox
bash Scripts/check_version.sh

mkdir -p "$STAGE/Plip.app/Contents/MacOS" "$STAGE/Plip.app/Contents/Resources"
cp .build/release/CraftAudio "$STAGE/Plip.app/Contents/MacOS/Plip"
# 不把 AppleDouble (._*) 和 .DS_Store 打进包
rsync -a --exclude '.DS_Store' --exclude '._*' Soundpacks "$STAGE/Plip.app/Contents/Resources/"
cp Info.plist "$STAGE/Plip.app/Contents/"
xattr -c "$STAGE/Plip.app/Contents/Info.plist"

# 签名失败必须中止，不能带一个签坏的包出去
codesign --force --sign "$IDENTITY" "$STAGE/Plip.app"
codesign --verify --deep --strict "$STAGE/Plip.app"

rm -rf "$APP"
mv "$STAGE/Plip.app" "$APP"
trap - EXIT

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
ZIP="artifacts/Plip-v${VERSION}.zip"
rm -f "$ZIP"
# ditto 不会写入 AppleDouble
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Built $APP"
echo "Archive $ZIP"
if [[ "$IDENTITY" == "-" ]]; then
  echo "签名：ad-hoc。开机自启需要 Developer ID，并把应用放到 /Applications。"
fi
