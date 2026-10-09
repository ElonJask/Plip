#!/bin/bash
# 启用仓库自带的 git 钩子：推送前自动运行 Scripts/check.sh。
set -euo pipefail
cd "$(dirname "$0")/.."
chmod +x .githooks/* Scripts/*.sh
git config core.hooksPath .githooks
echo "hooks enabled"
