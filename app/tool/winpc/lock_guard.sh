# Source this first in every script that changes winpc:C:\fmp-wt (plan section 4).
# Unless this worktree already holds the shared-device lock (the full gate,
# or an outer or background tool/device_lock.dart), re-run the calling script
# under tool/device_lock.dart, which takes the lock (waiting if needed) first.
lock_tool="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/device_lock.dart"
lock_dir="$(cd "$(dirname "$0")" && pwd)"
if ! dart "$lock_tool" --repo "$lock_dir" --held; then
  exec dart "$lock_tool" --repo "$lock_dir" -- "$lock_dir/$(basename "$0")" "$@"
fi
unset lock_tool lock_dir
