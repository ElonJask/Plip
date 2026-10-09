#!/bin/bash
# VERSION 是版本的唯一来源，electron/package.json 必须与之一致。
# 发布时 RELEASE_TAG 必须等于 v<VERSION>。
set -euo pipefail
cd "$(dirname "$0")/.."
file="$(tr -d '[:space:]' < VERSION)"
pkg="$(node -p "require('./electron/package.json').version")"
if [[ "$pkg" != "$file" ]]; then
  echo "version mismatch: electron/package.json=$pkg VERSION=$file" >&2
  exit 1
fi
if [[ -n "${RELEASE_TAG:-}" && "$RELEASE_TAG" != "v$file" ]]; then
  echo "tag mismatch: $RELEASE_TAG expected v$file" >&2
  exit 1
fi
echo "version $file"
