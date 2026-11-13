#!/bin/bash
# 經 SSH 把 app/（追蹤與未追蹤的檔，排除 gitignore 的）和 winpc 腳本複製到
# winpc:C:\fmp-wt，不靠 git push。先刪掉舊的 C:\fmp-wt\app，下一次建置從乾淨的
# 目錄開始。在共用裝置鎖裡跑（lock_guard.sh）。
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
source "$here/lock_guard.sh"
repo=$(git -C "$here" rev-parse --show-toplevel)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
(cd "$repo" && git ls-files -co --exclude-standard app |
  COPYFILE_DISABLE=1 tar -cf "$tmp/app.tar" -T -)
# C:\fmp-wt\app 不在時（例如照 docs/development.md〈平台〉 清掉整個工作樹之後），Remove-Item 即使
# -EA SilentlyContinue 也讓 PowerShell 以 1 結束，所以先 Test-Path。
ssh winpc 'New-Item -ItemType Directory -Force C:\fmp-wt | Out-Null; if (Test-Path C:\fmp-wt\app) { Remove-Item -Recurse -Force C:\fmp-wt\app }'
scp -q "$tmp/app.tar" "$here/build.ps1" "$here/test.ps1" "$here/shot.ps1" winpc:C:/fmp-wt/
ssh winpc 'cd C:\fmp-wt; tar -xf app.tar; Remove-Item app.tar'
