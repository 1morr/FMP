#!/usr/bin/env bash
# 實跑的系統動作（docs/development.md〈實跑驅動〉）：情境經 RealRun.system 向宿主要，
# tool/real_run.dart 跑這支腳本。印出讀回的文字，失敗時以非零結束。不動 Mac 的游標：
# macOS 走輔助使用的動作與合成的媒體鍵，模擬器走 simctl 與 adb。
#
#   real_run_system.sh <平台> <裝置> <App 的 pid> <截圖路徑> <動作> [參數]
#
# macOS:   background | foreground | panel | press <previous|toggle|next>
#          | seek <秒> | close-panel | key <play|next|previous>
#          | resize <寬>x<高>（App 的視窗；System Events，不動游標）
#          | shortcut <comma|字母>（App 拉到前景再送 ⌘＋鍵，經過主選單；System Events，
#            不動游標）
#          | press-key <tab|shift-tab>（App 拉到前景再送一下真的按鍵，經過輸入法；
#            System Events，不動游標）
# iOS:     background | screen
# Android: background | foreground | notification | session
#          | tap <標籤[:標籤...]> | seek-bar <比例>
#          | dispatch <play|pause|play-pause|next|previous> | collapse
#
# Android 的 uiautomator 在媒體播放器的進度條一直動時讀不到畫面（"could not get idle
# state"），所以要先暫停再讀通知：tap 與 seek-bar 讀得到就用新讀的，讀不到就用上一次
# 讀到的，按鈕的位置不變（播放、暫停是同一顆）。tap 給按鈕的 content-desc，不分大小寫，
# 空白寫成 _，多個候選用 : 隔開（Play:Pause、Next_track）。
#
# 呼叫的人（tool/real_run.dart）已經持有共用裝置鎖，下面的實驗腳本直接跑（它們的
# lock_guard.sh 看得到鎖已持有）。
set -euo pipefail

platform=$1 device=$2 pid=$3 shot=$4 action=$5
arg=${6:-}
here=$(cd "$(dirname "$0")" && pwd)
np="$here/../../scripts/experiments/macos-now-playing"

# 上一次讀到的畫面，播放中點按時用。
last_dump="$(dirname "$shot")/.android-ui.xml"

# 畫面的 UI 樹，另存成 $last_dump；播放中會失敗（見開頭）。
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

# 讀到的 UI 裡每個文字與 content-desc，一行一個。
ui_labels() {
  python3 -I -c '
import re, sys
xml = sys.stdin.read()
for text, desc in re.findall(r"text=\"([^\"]*)\"[^>]*content-desc=\"([^\"]*)\"", xml):
    for label in (text, desc):
        # 別的通知可能顯示帳號名稱，略過。
        if label.strip() and "@" not in label:
            print(label)
'
}

# content-desc 是 $1 其中一個標籤的第一個節點的中心點。
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
  macos:shortcut)
    # 宿主只收字母數字的參數，標點用名字。
    key=$arg
    [ "$arg" = comma ] && key=,
    osascript \
      -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" \
      -e "delay 0.3" \
      -e "tell application \"System Events\" to keystroke \"$key\" using command down"
    echo "pressed cmd+$arg"
    ;;
  macos:press-key)
    case $arg in
      tab) using='' ;;
      shift-tab) using=' using shift down' ;;
      *) echo "unknown key: $arg" >&2; exit 2 ;;
    esac
    osascript \
      -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" \
      -e "delay 0.3" \
      -e "tell application \"System Events\" to key code 48$using"
    echo "pressed $arg"
    ;;
  macos:resize)
    w=${arg%x*} h=${arg#*x}
    osascript -e "tell application \"System Events\" to set size of window 1 of (first process whose unix id is $pid) to {$w, $h}"
    echo "resized to ${w}x${h}"
    ;;

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
    # 這個 App 的媒體工作階段：曲目資訊與播放狀態。
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
    # 點通知進度條寬度的某個比例處。
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
    # 送一個媒體鍵給目前的媒體工作階段（耳機鍵、藍牙）。
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
