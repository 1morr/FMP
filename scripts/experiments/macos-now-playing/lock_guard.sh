# 會送按鍵、媒體鍵或按「正在播放」面板的腳本開頭 source 這個檔（照 app/tool/winpc/lock_guard.sh）。
# 這個 worktree 還沒持有共用裝置鎖（docs/development.md〈平台〉〈開發環境與閘門〉）時，經 app/tool/device_lock.dart 拿鎖
# （別的 worktree 持有時等待）再重新執行呼叫它的腳本；已持有時（run.py、完整閘門、
# 外層或背景的包裝指令）直接往下跑。
# 為什麼要鎖：Escape 會打到最前面的 App，媒體鍵與面板的按鈕會控制最近出過聲的 App，
# 別的 worktree 的閘門或實跑可能正開著 dev App。
lock_dir="$(cd "$(dirname "$0")" && pwd)"
lock_tool="$(git -C "$lock_dir" rev-parse --show-toplevel)/app/tool/device_lock.dart"
if ! dart "$lock_tool" --repo "$lock_dir" --held; then
  exec dart "$lock_tool" --repo "$lock_dir" -- "$lock_dir/$(basename "$0")" "$@"
fi
unset lock_tool lock_dir
