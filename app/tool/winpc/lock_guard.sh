# Source this first in every script that changes winpc:C:\fmp-wt (plan section 4).
# Without the shared-device lock held by an ancestor process (the full gate,
# or an outer tool/device_lock.dart), re-run the calling script under
# tool/device_lock.dart, which takes the lock (waiting if needed) first.
lock_tool="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/device_lock.dart"
lock_repo="$(cd "$(dirname "$0")" && pwd)"
if ! dart "$lock_tool" --repo "$lock_repo" --held; then
  exec dart "$lock_tool" --repo "$lock_repo" -- "$0" "$@"
fi
unset lock_tool lock_repo
