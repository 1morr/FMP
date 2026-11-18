#!/usr/bin/env bash
# Real-run system actions (docs/development.md〈實跑驅動〉): a scenario asks the
# host for one through RealRun.system, tool/real_run.dart runs this script.
# Prints what it reads back; exits non-zero on failure. Never moves the Mac
# cursor: macOS goes through accessibility actions and synthetic media keys,
# the simulators through simctl and adb.
#
#   real_run_system.sh <platform> <device> <app pid> <screenshot path> <action> [arg]
#
# macOS:   background | foreground | panel | press <previous|toggle|next>
#          | seek <seconds> | close-panel | key <play|next|previous>
# iOS:     background | screen
# Android: background | foreground | notification | session
#          | tap <label[:label...]> | seek-bar <fraction>
#          | dispatch <play|pause|play-pause|next|previous> | collapse
#
# Android's uiautomator cannot dump the screen while the media player moves
# its seek bar ("could not get idle state"), so dump the notification while
# paused: tap and seek-bar use a fresh dump when there is one and otherwise
# the last one, whose buttons stay where they were (play and pause share a
# spot). tap takes the content description of the button, case-insensitive,
# with _ for a space and : between alternatives (Play:Pause, Next_track).
#
# The caller (tool/real_run.dart) already holds the shared device lock, so the
# experiment scripts below run at once (their lock_guard.sh sees it held).
set -euo pipefail

platform=$1 device=$2 pid=$3 shot=$4 action=$5
arg=${6:-}
here=$(cd "$(dirname "$0")" && pwd)
np="$here/../../scripts/experiments/macos-now-playing"

# The last dump that worked, for taps while playing.
last_dump="$(dirname "$shot")/.android-ui.xml"

# The UI tree of the screen, kept as $last_dump; fails while the media player
# plays (see the top).
dump_android() {
  local out
  for _ in 1 2 3; do
    adb -s "$device" shell rm -f /sdcard/fmp-ui.xml
    out=$(adb -s "$device" shell uiautomator dump /sdcard/fmp-ui.xml 2>&1 || true)
    if [[ $out == *"dumped to"* ]]; then
      adb -s "$device" exec-out cat /sdcard/fmp-ui.xml | tee "$last_dump"
      return
    fi
    sleep 1
  done
  echo "uiautomator dump failed: $out" >&2
  return 1
}

# Text and content descriptions of the dumped UI, one per line.
ui_labels() {
  python3 -I -c '
import re, sys
xml = sys.stdin.read()
for text, desc in re.findall(r"text=\"([^\"]*)\"[^>]*content-desc=\"([^\"]*)\"", xml):
    for label in (text, desc):
        # Other notifications can show account names; leave them out.
        if label.strip() and "@" not in label:
            print(label)
'
}

# Centre of the first node whose content-desc is one of the labels in $1.
node_centre() {
  python3 -I -c '
import re, sys
labels = {l.replace("_", " ").lower() for l in sys.argv[1].split(":")}
for desc, x1, y1, x2, y2 in re.findall(
        r"content-desc=\"([^\"]*)\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"",
        sys.stdin.read()):
    if desc.lower() in labels:
        print((int(x1) + int(x2)) // 2, (int(y1) + int(y2)) // 2)
        sys.exit(0)
sys.exit("no node with content-desc " + sys.argv[1])
' "$1"
}

case "$platform:$action" in
  macos:background)
    osascript -e "tell application \"System Events\" to set value of attribute \"AXMinimized\" of every window of (first process whose unix id is $pid) to true"
    echo "minimized"
    ;;
  macos:foreground)
    osascript -e "tell application \"System Events\" to set value of attribute \"AXMinimized\" of every window of (first process whose unix id is $pid) to false"
    echo "restored"
    ;;
  macos:panel)
    "$np/np-panel.sh" state
    "$np/np-panel.sh" shot "$shot" >/dev/null
    ;;
  macos:press) "$np/np-panel.sh" press "$arg" ;;
  macos:seek) "$np/np-panel.sh" seek "$arg" ;;
  macos:close-panel) "$np/np-panel.sh" close; echo "closed" ;;
  macos:key) "$np/mediakey.sh" "$arg"; echo "media key $arg" ;;

  ios:background)
    xcrun simctl launch "$device" com.apple.Preferences >/dev/null
    echo "Settings in front"
    ;;
  ios:screen)
    xcrun simctl io "$device" screenshot "$shot" >/dev/null 2>&1
    echo "screenshot"
    ;;

  android:background)
    adb -s "$device" shell input keyevent KEYCODE_HOME
    echo "home"
    ;;
  android:foreground)
    adb -s "$device" shell am start -n com.personal.fmp.dev/.MainActivity >/dev/null
    echo "activity in front"
    ;;
  android:notification)
    adb -s "$device" shell cmd statusbar expand-notifications
    sleep 2
    xml=$(dump_android)
    ui_labels <<<"$xml"
    adb -s "$device" exec-out screencap -p >"$shot"
    ;;
  android:session)
    # The media session of this app: its metadata and playback state.
    adb -s "$device" shell dumpsys media_session |
      awk '/package=com.personal.fmp.dev/{on=1} on{print; n++} n>=25{exit}' |
      grep -v '@' || true
    ;;
  android:tap)
    xml=$(dump_android 2>/dev/null || cat "$last_dump")
    read -r x y < <(node_centre "$arg" <<<"$xml")
    adb -s "$device" shell input tap "$x" "$y"
    echo "tapped $arg at $x,$y"
    ;;
  android:seek-bar)
    # Taps the notification's seek bar at a fraction of its width.
    xml=$(dump_android 2>/dev/null || cat "$last_dump")
    read -r x1 y1 x2 y2 < <(python3 -I -c '
import re, sys
m = re.search(r"class=\"android.widget.SeekBar\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"", sys.stdin.read())
if not m: sys.exit("no seek bar")
print(*m.groups())
' <<<"$xml")
    x=$(python3 -I -c "print(int($x1 + ($x2 - $x1) * float('$arg')))")
    y=$(( (y1 + y2) / 2 ))
    adb -s "$device" shell input tap "$x" "$y"
    echo "tapped the seek bar at $arg ($x,$y)"
    ;;
  android:dispatch)
    # A media key to the active media session (headset buttons, Bluetooth).
    adb -s "$device" shell cmd media_session dispatch "$arg"
    echo "media key $arg"
    ;;
  android:collapse)
    adb -s "$device" shell cmd statusbar collapse
    echo "collapsed"
    ;;
  *)
    echo "unknown system action for $platform: $action" >&2
    exit 2
    ;;
esac
