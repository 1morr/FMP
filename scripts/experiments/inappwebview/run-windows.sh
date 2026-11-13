#!/usr/bin/env bash
# 實驗用（M0 票 04）：把 probe 同步到 winpc 的 C:\fmpx\inappwebview，在桌面工作階段
# 建置、開頁、截圖，取回 results/windows.json 與截圖。
#
#   ./run-windows.sh                 結果在 results/windows.json；MODE=release 建 release（windows-release.json）；VERBOSE=1 讓 flutter build 加 -v
#   FMPX_WIN_PATCH=0 ./run-windows.sh   不套 probe/windows/CMakeLists.txt 的補丁（重驗 W8）
#
# 整段持有共用裝置鎖（docs/app-development.md〈平台〉）：winpc 的桌面是幾個 worktree 共用的。不經 git push。
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
# 沒持鎖就經 app/tool/device_lock.dart 重跑自己（同一個 worktree 已持鎖時直接往下）。
source "$repo/app/tool/winpc/lock_guard.sh"

mode=${MODE:-debug}
out="$here/results"
shots=${SHOT_DIR:-$(mktemp -d)}
mkdir -p "$out" "$shots"
tmp=$(mktemp -d)
# 中途失敗也要清掉 winpc 上的使用者環境變數（見下面的 FMPX_WIN_PATCH）。
cleanup() {
  rm -rf "$tmp"
  ssh winpc "[Environment]::SetEnvironmentVariable('FMPX_WIN_PATCH', \$null, 'User')" || true
}
trap cleanup EXIT
trap 'echo "run-windows.sh: failed at line $LINENO" >&2' ERR

# 只帶 git 認得的檔（含未追蹤、不含 gitignore 的建置產物）。
(cd "$repo" && git ls-files -co --exclude-standard scripts/experiments/inappwebview/probe scripts/experiments/inappwebview/windows |
  sed 's#^scripts/experiments/inappwebview/##' | (cd "$here" && COPYFILE_DISABLE=1 tar -cf "$tmp/x.tar" -T -))
ssh winpc 'New-Item -ItemType Directory -Force C:\fmpx\inappwebview | Out-Null; Remove-Item -Recurse -Force C:\fmpx\inappwebview\probe -EA SilentlyContinue; exit 0'
scp -q "$tmp/x.tar" winpc:C:/fmpx/inappwebview/
ssh winpc 'cd C:\fmpx\inappwebview; tar -xf x.tar; Remove-Item x.tar'

# CMake 在 configure 時讀環境變數；排程工作不繼承 SSH 的環境，所以寫成使用者環境變數再清掉。
ssh winpc "[Environment]::SetEnvironmentVariable('FMPX_WIN_PATCH', '${FMPX_WIN_PATCH:-1}', 'User')"
"$repo/app/tool/winpc/run_task.sh" fmpxwebview C:/fmpx/inappwebview/windows/probe.ps1 -Mode "$mode" ${VERBOSE:+-VerboseBuild}

ssh winpc 'Get-Content C:\fmpx\inappwebview\results\raw-windows.log' | iconv -c -f utf-8 -t utf-8 >"$out/raw-windows.log" || true
scp -q winpc:C:/fmpx/inappwebview/results/windows.png "$shots/windows.png" && echo "screenshot: $shots/windows.png" || echo "no screenshot"
# debug 的結果寫 windows.json，release 寫 windows-release.json，互不覆蓋。
suffix=""; [[ $mode == release ]] && suffix=-release
result_json="$out/windows$suffix.json"
rm -f "$result_json"
if scp -q winpc:C:/fmpx/inappwebview/results/windows.json "$result_json"; then
  cat "$result_json"
else
  echo "no result; see $out/raw-windows.log" >&2
  exit 1
fi
