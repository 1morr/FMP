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
ssh winpc 'New-Item -ItemType Directory -Force C:\fmp-wt | Out-Null; Remove-Item -Recurse -Force C:\fmp-wt\app -EA SilentlyContinue'
scp -q "$tmp/app.tar" "$here/build.ps1" "$here/test.ps1" "$here/shot.ps1" winpc:C:/fmp-wt/
ssh winpc 'cd C:\fmp-wt; tar -xf app.tar; Remove-Item app.tar'
