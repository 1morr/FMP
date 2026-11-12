#!/usr/bin/env bash
# 實驗用（M0 票 05b）：把 probe 同步到 winpc 的 C:\fmpx\glass，在桌面工作階段建置（profile）、
# 逐個候選截圖並量捲動幀時間，取回 results/windows.json 與對照圖 results/windows-sheet.jpg。
#
#   ./run-windows.sh                        全部候選
#   VARIANTS=own-refract ./run-windows.sh   部分候選（windows-partial.json）
#   MODE=a11y ./run-windows.sh              只讀無障礙旗標（windows-a11y.json）；debug 建置
#
# 整段持有共用裝置鎖（plan §2）：winpc 的桌面是幾個 worktree 共用的。不經 git push。
# 完整截圖存在 SHOT_DIR（預設新的暫存目錄）。
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
# 沒持鎖就經 app/tool/device_lock.dart 重跑自己（同一個 worktree 已持鎖時直接往下）。
source "$repo/app/tool/winpc/lock_guard.sh"

out="$here/results"
shots=${SHOT_DIR:-$(mktemp -d)}
mkdir -p "$out" "$shots"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

name=windows; mode=profile; defines=""
[[ -n ${VARIANTS:-} ]] && { name=windows-partial; defines="VARIANTS=$VARIANTS"; }
[[ ${MODE:-} == a11y ]] && { name=windows-a11y; mode=debug; defines="MODE=a11y"; }
# APP_ARGS=--plain：不包 liquid_glass_widgets（診斷用，結果檔名加 -plain）。
[[ -n ${APP_ARGS:-} ]] && name="$name-plain"

# 只帶 git 認得的檔（含未追蹤、不含 gitignore 的建置產物）。
(cd "$repo" && git ls-files -co --exclude-standard scripts/experiments/glass/probe scripts/experiments/glass/windows |
  sed 's#^scripts/experiments/glass/##' | (cd "$here" && COPYFILE_DISABLE=1 tar -cf "$tmp/x.tar" -T -))
ssh winpc 'New-Item -ItemType Directory -Force C:\fmpx\glass | Out-Null; Remove-Item -Recurse -Force C:\fmpx\glass\probe -EA SilentlyContinue; exit 0'
scp -q "$tmp/x.tar" winpc:C:/fmpx/glass/
ssh winpc 'cd C:\fmpx\glass; tar -xf x.tar; Remove-Item x.tar'

"$repo/app/tool/winpc/run_task.sh" fmpxglass C:/fmpx/glass/windows/probe.ps1 -Mode "$mode" -Name "$name" ${defines:+-Defines "$defines"} ${APP_ARGS:+-AppArgs "$APP_ARGS"}

ssh winpc 'Get-Content C:\fmpx\glass\results\raw-windows.log' | iconv -c -f utf-8 -t utf-8 >"$shots/raw-windows.log" || true
scp -q 'winpc:C:/fmpx/glass/results/shots/*.png' "$shots/" || echo "no screenshots"
if ! scp -q "winpc:C:/fmpx/glass/results/$name.json" "$out/$name.json"; then
  echo "no result; see $shots/raw-windows.log" >&2
  exit 1
fi
python3 "$here/run.py" --sheet windows "$out/$name.json" "$shots" "$out/$name-sheet.jpg"
echo "screenshots: $shots"
cat "$out/$name.json"
