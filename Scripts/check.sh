#!/bin/bash
# 本地检查：版本、语法、单元测试。提交或推送前运行。
set -euo pipefail
cd "$(dirname "$0")/.."

bash Scripts/check_version.sh
for f in electron/*.js ui/*.js; do
  node --check "$f"
done
(cd electron && npm test)
echo "check passed"
