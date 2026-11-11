#!/bin/bash
# usage: run_task.sh <name> <remote .ps1 path> [args...]  -- runs script in interactive desktop session, waits for completion
# Needs winpc console user logged in. Args must not contain double quotes.
# A failed status query (e.g. SSH timeout) is retried; deleting the task while
# it still runs would kill the script. Exits 1 after 12 failed queries in a row.
# Runs under the shared-device lock (lock_guard.sh).
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
