#!/bin/bash
# 從 Mac 經 SSH，在 Windows 使用者登入中的桌面工作階段跑一支 PowerShell 腳本，印回它的輸出（references/windows.md § 從 Mac 遠端）。
#
#   wrun.sh <本機 .ps1> [timeout 秒] [PowerShell 參數...]
#
# 環境變數：FMP_WIN_HOST（~/.ssh/config 的 Host，預設 winpc）、FMP_WIN_TOOLS（Windows 上放腳本的目錄，
# 用正斜線，預設 D:/Temp/fmp-verify-tools）。第一次用之前把 insession.ps1 複製到那個目錄。
#
# 腳本與一個帶參數的呼叫檔都存成 UTF-8 帶 BOM 再上傳：PowerShell 5.1 讀沒有 BOM 的 .ps1 用系統碼頁（繁中是
# cp950），中文會變亂碼。參數照字面寫進呼叫檔，含空白的值自己加單引號（"'menu item'"）。
set -euo pipefail
host="${FMP_WIN_HOST:-winpc}"
tools="${FMP_WIN_TOOLS:-D:/Temp/fmp-verify-tools}"
f="$1"; t="${2:-120}"; shift 2 || shift $#
b=$(basename "$f" .ps1)
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
tools_win="${tools//\//\\}"
if [ "$(head -c3 "$f" | xxd -p)" = efbbbf ]; then cp "$f" "$d/$b.ps1"; else { printf '\xEF\xBB\xBF'; cat "$f"; } > "$d/$b.ps1"; fi
printf '\xEF\xBB\xBF[Console]::OutputEncoding = [Text.Encoding]::UTF8\n& %s %s\nexit $LASTEXITCODE\n' \
  "'$tools_win\\$b.ps1'" "$*" > "$d/call_$b.ps1"
scp -q "$d/$b.ps1" "$d/call_$b.ps1" "$host:$tools/"
ssh "$host" "powershell -NoProfile -ExecutionPolicy Bypass -File $tools_win\\insession.ps1 -Script $tools_win\\call_$b.ps1 -Timeout $t"
