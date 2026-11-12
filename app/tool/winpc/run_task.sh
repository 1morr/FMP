#!/bin/bash
# 用法：run_task.sh <名稱> <遠端 .ps1 路徑> [參數…]
# 以排程工作在互動桌面工作階段跑腳本，等它結束。winpc 要有人登入桌面；
# 參數不能含雙引號。查詢狀態失敗（例如 SSH 逾時）就重試：工作還在跑時刪掉
# 會連帶終止腳本。連續 12 次查詢失敗才以 1 結束。在共用裝置鎖裡跑（lock_guard.sh）。
source "$(cd "$(dirname "$0")" && pwd)/lock_guard.sh"
NAME=$1; PS1=$2; shift 2; ARGS="$*"
ssh winpc "schtasks /Create /F /TN $NAME /SC ONCE /ST 00:00 /RL LIMITED /IT /TR \"powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PS1 $ARGS\"" || exit 1
ssh winpc "schtasks /Run /TN $NAME" || exit 1
failures=0
while true; do
  sleep 5
  S=$(ssh -o ConnectTimeout=20 winpc "schtasks /Query /TN $NAME /FO LIST" | iconv -c -f cp950 -t utf-8 | grep -iE 'Status|狀態' | head -1)
  if [ -z "$S" ]; then
    failures=$((failures + 1))
    echo "status query failed ($failures)"
    [ "$failures" -ge 12 ] && exit 1
    continue
  fi
  failures=0
  echo "$S"
  echo "$S" | grep -qiE 'Running|執行中' || break
done
ssh winpc "schtasks /Delete /F /TN $NAME" >/dev/null
