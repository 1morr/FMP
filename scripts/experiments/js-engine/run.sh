#!/usr/bin/env bash
# 實驗用：在一個平台上建置並執行一個候選的 probe app，結果存到 results/<候選>-<平台>.json。
#
#   ./run.sh <fjs|flutter_js> <macos|ios|android>
#
# 環境變數：IOS_DEVICE（模擬器 UDID，預設 booted）、ANDROID_SERIAL（預設 adb 唯一的裝置）。
# Windows 用 run-windows.sh。見 README.md。
set -euo pipefail

cand=${1:?candidate: fjs | flutter_js}
plat=${2:?platform: macos | ios | android}
here=$(cd "$(dirname "$0")" && pwd)
app="$here/probe_$cand"
out="$here/results"
raw="$out/raw-$cand-$plat.log"
mkdir -p "$out"
[[ -d $app ]] || { echo "no such candidate: $app" >&2; exit 2; }

ios_bundle() { grep -m1 'PRODUCT_BUNDLE_IDENTIFIER = ' "$app/ios/Runner.xcodeproj/project.pbxproj" | sed 's/.*= \(.*\);/\1/'; }
android_id() { grep -m1 'applicationId' "$app/android/app/build.gradle.kts" | sed 's/.*"\(.*\)".*/\1/'; }

(cd "$app" && flutter pub get >/dev/null)

case $plat in
  macos)
    (cd "$app" && flutter build macos --debug)
    bundle=$(ls -d "$app"/build/macos/Build/Products/Debug/*.app | head -1)
    "$bundle/Contents/MacOS/$(basename "$bundle" .app)" >"$raw" 2>&1 || true
    ;;
  ios)
    dev=${IOS_DEVICE:-booted}
    (cd "$app" && flutter build ios --simulator --debug)
    xcrun simctl install "$dev" "$app/build/ios/iphonesimulator/Runner.app"
    # iOS 的 print 進系統 log、不進 stdout：改等 App 容器裡的結果檔。
    result="$(xcrun simctl get_app_container "$dev" "$(ios_bundle)" data)/tmp/js-engine-probe-$cand.json"
    rm -f "$result"
    xcrun simctl launch --terminate-running-process "$dev" "$(ios_bundle)" >/dev/null
    for ((i = 0; i < 300; i++)); do [[ -s $result ]] && break; sleep 1; done
    sleep 1
    echo "PROBE_FILE $result" >"$raw"
    ;;
  android)
    (cd "$app" && flutter build apk --debug)
    id=$(android_id)
    adb install -r "$app/build/app/outputs/flutter-apk/app-debug.apk" >/dev/null
    adb logcat -c
    adb shell am start -n "$id/.MainActivity" >/dev/null
    # 不維持 adb 連線：輪詢裝置上的 logcat（主機的 adb daemon 中途重啟也不影響 App）。
    for ((i = 0; i < 300; i++)); do
      adb logcat -d -s flutter:I >"$raw" 2>/dev/null || true
      grep -q 'PROBE_FILE' "$raw" && break
      sleep 2
    done
    ;;
  *) echo "unknown platform: $plat" >&2; exit 2 ;;
esac

# 結果以 App 寫的 JSON 檔為準（log 的長行在 Android 會被切段）。
path=$(grep -o 'PROBE_FILE .*' "$raw" | tail -1 | sed 's/^PROBE_FILE //' | tr -d '\r' || true)
if [[ -z $path ]]; then
  echo "no PROBE_FILE; see $raw" >&2
  exit 1
fi
case $plat in
  android) adb exec-out run-as "$(android_id)" cat "$path" >"$out/$cand-$plat.json" ;;
  *) cp "$path" "$out/$cand-$plat.json" ;;
esac
python3 "$here/summarize.py" "$out/$cand-$plat.json"
