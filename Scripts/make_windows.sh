#!/bin/bash
# 编译 Windows x64 托盘程序，并把音效包打进 zip。可在 macOS 交叉编译。
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v go >/dev/null; then
  echo "missing go" >&2
  exit 1
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/plip-win.XXXXXX")"
cleanup() { rm -rf "$ROOT"; }
trap cleanup EXIT

mkdir -p "$ROOT/Plip/Soundpacks"
(
  cd windows
  go test ./...
  GOOS=windows GOARCH=amd64 go build -ldflags "-H windowsgui -s -w" -o "$ROOT/Plip/Plip.exe" .
)
cp windows/plip.ico "$ROOT/Plip/plip.ico"
	cp ui/panel.html "$ROOT/Plip/panel.html"
cp -R Soundpacks/. "$ROOT/Plip/Soundpacks/"
find "$ROOT/Plip" -name '.DS_Store' -delete
find "$ROOT/Plip" -name '._*' -delete

mkdir -p artifacts
ZIP="artifacts/Plip-v${VERSION}-windows-x64.zip"
rm -f "$ZIP"
python3 - "$ROOT/Plip" "$ZIP" <<'PY'
import os, sys, zipfile
src, dest = sys.argv[1], sys.argv[2]
parent = os.path.dirname(src)
with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for dirpath, _, files in os.walk(src):
        for name in files:
            full = os.path.join(dirpath, name)
            archive.write(full, os.path.relpath(full, parent).replace(os.sep, "/"))
PY
test -f "$ZIP"
echo "Archive $ZIP"
