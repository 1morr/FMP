#!/usr/bin/env bash
# 實驗用：把實驗目錄同步到 winpc，在它的桌面工作階段建置並執行一個候選，取回結果。
#
#   ./run-windows.sh <fjs|flutter_js>          VERBOSE=1 讓 flutter build windows 加 -v
#
# 需要：ssh 主機別名 winpc（預設 shell 是 PowerShell）、對方已登入桌面、裝好 Flutter 與 rustup。
# 遠端目錄是 %USERPROFILE%\fmpx\js-engine。不經 git push（推遠端是寫入動作）。
set -euo pipefail

cand=${1:?candidate: fjs | flutter_js}
here=$(cd "$(dirname "$0")" && pwd)
out="$here/results"
mkdir -p "$out"
tmp=$(mktemp -d)
tgz="$tmp/js-engine.tgz"

# 只帶原始碼：建置產物、Pods、結果都不帶。
tar -czf "$tgz" -C "$here/.." \
  --exclude 'build' --exclude '.dart_tool' --exclude 'Pods' --exclude 'results' --exclude '.gradle' \
  js-engine
scp -q "$tgz" winpc:fmpx-js-engine.tgz
rm -rf "$tmp"
ssh winpc 'New-Item -ItemType Directory -Force fmpx | Out-Null; tar -xzf fmpx-js-engine.tgz -C fmpx; Remove-Item fmpx-js-engine.tgz'
# 先刪上一輪的完成標記與結果，免得一開始輪詢就以為做完了。
ssh winpc "Remove-Item -ErrorAction SilentlyContinue fmpx\\js-engine\\results\\done-$cand-windows, fmpx\\js-engine\\results\\$cand-windows.json; exit 0"
ssh winpc "powershell -NoProfile -ExecutionPolicy Bypass -File fmpx\\js-engine\\windows\\start.ps1 -Cand $cand${VERBOSE:+ -VerboseBuild}"

# 第一次建置要編 Rust，可能十幾分鐘。
for ((i = 0; i < 180; i++)); do
  if ssh winpc "Test-Path fmpx\\js-engine\\results\\done-$cand-windows" | grep -q True; then break; fi
  sleep 10
done
scp -q "winpc:fmpx/js-engine/results/raw-$cand-windows.log" "$out/" || true
if ! scp -q "winpc:fmpx/js-engine/results/$cand-windows.json" "$out/"; then
  echo "no result; see $out/raw-$cand-windows.log" >&2
  exit 1
fi
python3 "$here/summarize.py" "$out/$cand-windows.json"
