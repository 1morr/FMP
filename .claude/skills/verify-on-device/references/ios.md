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
- 收尾：`xcrun simctl terminate`、`xcrun simctl shutdown <UDID>`。不要用 `orca emulator kill`：它不分裝置，同時有別的人在用模擬器時會一起關掉。

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
- 重設資料（設定 → Debug → 重設資料）：對話框寫「App 會關閉，請自己重新開啟」，確認後行程消失
  （`xcrun simctl spawn <UDID> launchctl list | grep fmp.dev` 沒有結果），再開時資料是空的。
- 深淺色：`xcrun simctl ui <UDID> appearance dark|light`。
- 旋轉：`orca emulator rotate landscape_left|portrait`；旋轉後 `orca emulator tap` 的座標仍是目前畫面的 0..1。鍵盤開著時點空白處
  不會收，點鍵盤右上角的收合鈕，或 `xcrun simctl terminate` 後重開（橫向加鍵盤時搜尋頁頂部只剩約 100pt，會有 overflow 條）。
- iPad：機型選 13 吋或 11 吋都行；直向是窄側欄（medium），橫向的設定頁是左右兩欄。診斷包的「分享」（設定 → Debug → 概覽 → 分享 →
  送出前提醒按「繼續」）在 iPad 是 popover，箭頭要指著「分享」鈕（`origin`，ADR 0037 §決定 14）；點空白處關掉。
- 分割畫面與台前調度：`simctl` 與 `orca emulator` 都不能叫出，要在 Simulator 視窗手動拖（iPad 的 Dock 拖出第二個 App）；
  做不到時在回報裡寫「沒驗」，版面跟寬度換由 `WindowClass` 的 widget 測試守。
- 外接鍵盤的 ⌘ 快捷鍵：Simulator 選單 I/O → Keyboard → Connect Hardware Keyboard，再在視窗內按；`orca emulator type` 不送修飾鍵。
- 圖示：`xcrun simctl terminate <UDID> com.personal.fmp.dev` 後截主畫面（App 的圖示與名稱 `FMP Dev` 在最後一頁）。
- 啟動畫面不閃白：`xcrun simctl ui <UDID> appearance dark`，terminate、launch 之後連續 `xcrun simctl io <UDID> screenshot`
  多張，讀 `LaunchScreen` 那幾張的像素（深色是 `systemBackgroundColor` 的純黑，不是白）。裝置在連拍中途被別的流程關掉時
  `screenshot` 會報 `Timeout waiting for screen surfaces`，重新 `boot`。

## 回報

不寫 UDID、裝置名稱、Team ID；路徑寫 `<資料目錄>`。寫明機型與 iOS 版本、模式（重播）、做了哪些請求。
