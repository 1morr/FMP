# iOS 模擬器

iOS 平台任務（ADR 0037）的驗證。只用 dev（`com.personal.fmp.dev`，主畫面顯示 `FMP Dev`）。實機（擁有者的 iPhone）
的做法在平台任務的驗收 PR 補上。

## 選機型、建置、安裝

- 機型：`xcrun simctl list devices available`。iPhone 選有動態島的，iPad 選 13 吋。開機：`xcrun simctl boot <UDID>`。
  開機後用 `orca emulator attach <UDID>` 讓 Orca 操作它（`open -a Simulator` 在這台 Mac 找不到 App，不需要）。
- 建置與安裝（在 `app/`）：

  ```bash
  flutter build ios --simulator --flavor dev --debug
  xcrun simctl install <UDID> build/ios/iphonesimulator/Runner.app
  xcrun simctl launch <UDID> com.personal.fmp.dev
  ```

- 跑過 `flutter test integration_test/…` 之後，`build/ios/iphonesimulator/Runner.app` 是測試用的建置，直接裝
  會是空白畫面：要手動操作時重跑上面的 `flutter build`。整合測試一次一個檔：
  `flutter test integration_test/<檔>.dart -d <UDID> --flavor dev`（`secure_storage_test.dart` 只在本機跑，CI 不跑）。
- 收尾：`xcrun simctl terminate`、`xcrun simctl shutdown <UDID>`、`orca emulator kill`。

## 資料、log

- `xcrun simctl get_app_container <UDID> com.personal.fmp.dev data` 是容器；`<資料目錄>` 是它的
  `Library/Application Support`，log 在 `logs/fmp.jsonl`，資料庫 `fmp.db`（格式見 `runtime-state.md`）。
  重新安裝會換新的容器。
- 系統 log：`xcrun simctl spawn <UDID> log stream --predicate 'process == "Runner"'`。

## 開發入口在 iOS 不能用

iOS 上 Dart 的 `Platform.environment` 是空的，`main()` 的參數也是空的：`SIMCTL_CHILD_FMP_DEV_PLUGIN`、
`--fmp-dev-plugin`、`flutter run --dart-entrypoint-args`（只支援桌面）都到不了 Dart。改用編譯期的 dart-define
（模擬器讀得到 Mac 的檔案，不必複製進容器）：

```bash
flutter build ios --simulator --flavor dev --debug --dart-define=FMP_DEV_PLUGIN=$PWD/test/fixtures/plugins/test_plugin/test_plugin.js
xcrun simctl install <UDID> build/ios/iphonesimulator/Runner.app
```

`flutter run -d <UDID> --flavor dev --dart-define=…` 同理。舊資料副本用 `--dart-define=FMP_LEGACY_DIR=<資料夾>`。
實機不可用（路徑在 Mac 上，裝置讀不到）。整合測試 `install_search_play_test.dart` 不靠它。

## 操作與讀畫面

- `orca emulator`（`orca skills get orca-emulator`）：座標是 0..1 的比例；`ax` 列出無障礙樹與每個元件的框，
  用元件的中心點點按。讀回畫面才算數：`xcrun simctl io <UDID> screenshot <暫存目錄>/x.png`。
- 模擬器預設接硬體鍵盤，輸入法若是中文，`orca emulator type` 的英數會被組成中文字（`tone` 變成「陳日君」）。測試插件
  對任何關鍵字都回三首，所以字不重要；送出要傳兩次換行（`orca emulator type` 傳 `\n`，中間等一秒）：第一次確認組字，第二次送出。
- 背景：`orca emulator button home`；回來用 `xcrun simctl launch <UDID> com.personal.fmp.dev`。
- 背景換曲：佇列兩首、按播放、立刻按 home，log 的 `Track audible` 在背景仍會出現第二首（`UIBackgroundModes: audio`）。
- Now Playing：模擬器沒有可截圖的鎖定畫面與控制中心媒體卡（Simulator.app 在這台 Mac 找不到，無法鎖屏）。改讀系統 log：
  `xcrun simctl spawn <UDID> log show --last 2m --predicate 'process == "Runner" AND eventMessage CONTAINS[c] "PlaybackRate"'`
  有 `NPIC: setNowPlayingInfo` 與曲名（`item:<…/曲名/PlaybackRate: …>`），停止後出現 `Clearing nowPlayingInfo`。
  `PlaybackRate` 播放中仍是 0（audio_service 在 iOS 不設 `playbackState`，上游 #1139）；顯示以實機為準。
- 重設資料（設定 → Debug → 重設資料）：對話框寫「App 會關閉，請自己重新開啟」，確認後行程消失
  （`xcrun simctl spawn <UDID> launchctl list | grep fmp.dev` 沒有結果），再開時資料是空的。
- 深淺色：`xcrun simctl ui <UDID> appearance dark|light`。

## 回報

不寫 UDID、裝置名稱、Team ID；路徑寫 `<資料目錄>`。寫明機型與 iOS 版本、模式（重播）、做了哪些請求。
