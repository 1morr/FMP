#!/usr/bin/env bash
# 實驗用（M0 票 04）：在 macOS、iOS 模擬器或 Android 模擬器建置 probe，開頁、截圖，
# 結果存到 results/<平台>.json（release 是 <平台>-release.json），截圖存到 SHOT_DIR（預設一個新的暫存目錄，不進 repo）。
#
#   ./run.sh <macos|ios|android>      MODE=release 建 release（iOS 模擬器只有 debug）
#
# 環境變數：IOS_DEVICE（模擬器 UDID，預設 booted）、IOS_SHOT_ARGS（例如 iPhone Duo 要
# --display=1）、ANDROID_SERIAL（預設 adb 唯一的裝置）。Windows 用 run-windows.sh。
# 建置只寫這個 worktree 的 build/，在鎖外做；裝 App 到截圖整段持有共用裝置鎖（docs/development.md〈平台〉）。
set -euo pipefail

plat=${1:?platform: macos | ios | android}
mode=${MODE:-debug}
[[ $plat == ios ]] && mode=debug  # iOS 模擬器只能建 debug
here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
app="$here/probe"
out="$here/results"
shots=${SHOT_DIR:-$(mktemp -d)}
mkdir -p "$out" "$shots"
bundle=com.personal.fmpx.inappwebviewProbe
android_id=com.personal.fmpx.inappwebview_probe

(cd "$app" && flutter pub get >/dev/null)
case $plat in
  macos) (cd "$app" && flutter build macos "--$mode") ;;
  ios) (cd "$app" && flutter build ios --simulator --debug) ;;
  android) (cd "$app" && flutter build apk "--$mode") ;;
  *) echo "unknown platform: $plat" >&2; exit 2 ;;
esac

cfg=$([[ $mode == release ]] && echo Release || echo Debug)
# debug 的結果寫 <平台>.json，release 寫 <平台>-release.json，互不覆蓋。
suffix=""; [[ $mode == release ]] && suffix=-release
result_json="$out/$plat$suffix.json"
rm -f "$result_json"
export plat mode cfg app out shots bundle android_id result_json
export IOS_DEVICE=${IOS_DEVICE:-booted} IOS_SHOT_ARGS=${IOS_SHOT_ARGS:-}
# 以下碰共用裝置：經包裝指令持鎖（同一個 worktree 已持鎖時直接執行）。
# 逾時不中止：照樣截圖、關 App，最後由外層判斷有沒有結果。
(cd "$repo/app" && dart run tool/device_lock.dart -- bash -c '
set -uo pipefail
raw="$out/raw-$plat.log"
wait_for() { for ((i = 0; i < 90; i++)); do eval "$1" && return 0; sleep 1; done; echo "timed out: $1" >&2; return 1; }
# App 印出的最後一行 PROBE_RESULT（JSON）。
last_result() { grep -ao "PROBE_RESULT .*" "$raw" | tail -1 | sed "s/^PROBE_RESULT //" | tr -d "\r"; }
case $plat in
  macos)
    exe="$app/build/macos/Build/Products/$cfg/inappwebview_probe.app/Contents/MacOS/inappwebview_probe"
    "$exe" >"$raw" 2>&1 &
    pid=$!
    wait_for "grep -q PROBE_RESULT \"$raw\""
    sleep 2
    orca computer get-app-state --app "$bundle" --json >"$shots/macos-state.json"
    shot=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))[\"result\"][\"screenshot\"][\"path\"])" "$shots/macos-state.json")
    [[ -n $shot ]] && cp "$shot" "$shots/macos.png"
    kill "$pid" 2>/dev/null
    last_result >"$result_json"
    ;;
  ios)
    xcrun simctl install "$IOS_DEVICE" "$app/build/ios/iphonesimulator/Runner.app"
    # iOS 的 print 進系統 log、不進 stdout：改等 App 容器裡的結果檔。
    result="$(xcrun simctl get_app_container "$IOS_DEVICE" "$bundle" data)/tmp/inappwebview-probe.json"
    rm -f "$result"
    xcrun simctl launch --terminate-running-process "$IOS_DEVICE" "$bundle" >/dev/null
    wait_for "[[ -s \"$result\" ]]"
    sleep 2
    xcrun simctl io "$IOS_DEVICE" screenshot $IOS_SHOT_ARGS "$shots/ios.png" >/dev/null
    xcrun simctl terminate "$IOS_DEVICE" "$bundle"
    [[ -s $result ]] && cp "$result" "$result_json"
    ;;
  android)
    adb install -r "$app/build/app/outputs/flutter-apk/app-$mode.apk" >/dev/null
    adb logcat -c
    adb shell am start -n "$android_id/.MainActivity" >/dev/null
    wait_for "adb logcat -d -s flutter:I >\"$raw\" 2>/dev/null; grep -q PROBE_RESULT \"$raw\""
    sleep 2
    adb exec-out screencap -p >"$shots/android.png"
    adb shell am force-stop "$android_id"
    last_result >"$result_json"
    ;;
esac
exit 0
')
echo "screenshots: $shots"
if [[ -s $result_json ]]; then
  cat "$result_json"
else
  rm -f "$result_json"
  echo "no result; see $out/raw-$plat.log" >&2
  exit 1
fi
