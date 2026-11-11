#!/usr/bin/env bash
# 實驗用：持共用裝置鎖模擬一次媒體鍵（mediakey.swift 的包裝；直接跑 swift 檔不會拿鎖）。
#
#   ./mediakey.sh <play|next|previous>
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lock_guard.sh"
here=$(cd "$(dirname "$0")" && pwd)
exe="$here/build/mediakey"
if [[ ! -x $exe || $here/mediakey.swift -nt $exe ]]; then
  mkdir -p "$here/build"
  swiftc -O -o "$exe" "$here/mediakey.swift"
fi
exec "$exe" "$@"
