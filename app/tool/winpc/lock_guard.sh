# 會改動 winpc:C:\fmp-wt 的腳本一開頭都先 source 這支（plan §4）。這個
# worktree 還沒持有共用裝置鎖時（持有的情況：完整閘門、外層或背景的
# tool/device_lock.dart），經 tool/device_lock.dart 重新執行呼叫它的腳本，
# 先拿鎖（必要時等）再跑。
lock_tool="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/device_lock.dart"
lock_dir="$(cd "$(dirname "$0")" && pwd)"
if ! dart "$lock_tool" --repo "$lock_dir" --held; then
  exec dart "$lock_tool" --repo "$lock_dir" -- "$lock_dir/$(basename "$0")" "$@"
fi
unset lock_tool lock_dir
