#!/bin/bash
# Info.plist 是版本的唯一来源。VERSION 必须和 CFBundleShortVersionString 一致。
set -euo pipefail
cd "$(dirname "$0")/.."
plist="$(plutil -extract CFBundleShortVersionString raw Info.plist)"
file="$(tr -d '[:space:]' < VERSION)"
if [[ "$plist" != "$file" ]]; then
  echo "version mismatch: Info.plist=$plist VERSION=$file" >&2
  exit 1
fi
echo "version $plist"
