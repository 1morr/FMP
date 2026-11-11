#!/bin/bash
# usage: run_task.sh <name> <remote .ps1 path> [args...]  -- runs script in interactive desktop session, waits for completion
# Needs winpc console user logged in. Args must not contain double quotes.
NAME=$1; PS1=$2; shift 2; ARGS="$*"
ssh winpc "schtasks /Create /F /TN $NAME /SC ONCE /ST 00:00 /RL LIMITED /IT /TR \"powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PS1 $ARGS\"" || exit 1
ssh winpc "schtasks /Run /TN $NAME"
while true; do
  sleep 5
  S=$(ssh winpc "schtasks /Query /TN $NAME /FO LIST" | iconv -c -f cp950 -t utf-8 | grep -iE 'Status|狀態' | head -1)
  echo "$S"
  echo "$S" | grep -qiE 'Running|執行中' || break
done
ssh winpc "schtasks /Delete /F /TN $NAME" >/dev/null
