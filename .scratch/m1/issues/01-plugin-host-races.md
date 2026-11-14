# 01: 插件宿主的兩個競態

Status: done
Blocked by: None
讀: architecture〈執行形態〉；M0 票 08 的 Comments；spec〈共同規則〉

## What to build

插件宿主在兩種情況下不再出錯：呼叫逾時、宿主關掉並重建引擎的同時又有新的呼叫進來；建引擎失敗一次後，下一次呼叫會重新建，不會一直拿到快取住的失敗 future。照 `AGENTS.md`，先寫出會紅的測試再修；寫不出就在 Comments 記下試過什麼、為什麼重現不了，不改程式。

## 驗收

- [x] 逾時關引擎的競態：有一條改之前紅、改之後綠的測試（真的 fjs 引擎，`loadFjsForTests()`），或在 Comments 記下重現不了的理由。
- [x] 建引擎失敗後重試：有一條改之前紅、改之後綠的測試，或在 Comments 記下重現不了的理由。
- [x] 四平台實跑搜尋一次，結果照常。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments

### 重現與修正

- 逾時的競態：A 卡住逾時，先清掉 `_engine` 再等 `close()`；同一個引擎上排著的 B 接著失敗（被取消，或自己的逾時先到：中斷迴圈要幾毫秒，實測 B 的逾時晚 A 3 ms 就先到了，事實 K28）。B 失敗後去關「目前的」引擎，關到的是 C 剛建的新引擎，C 以 `ParseFailure` 失敗。測試在 B 寫失敗 log 的同步段裡發出 C（測試裡包一層 `Log`），時序固定；用真的 fjs、`while (true) {}` 卡住。
- 建引擎失敗：測試自己一個檔，不先 `loadFjsForTests()`，宿主自己 `LibFjs.init()` 在主機上載不到原生庫、丟 `ArgumentError`（不是 `JsError`，事實 K28）。改之前，第二次呼叫丟出快取住的同一個例外；改之後每次都重新初始化（斷言第二次的例外不是同一個物件），`loadFjsForTests()` 之後那次成功。
- 修正：`Plugin._retire(pending)` 只在 `_engine` 還是這次呼叫用的那個 future 時才清掉並關；建引擎失敗時清掉 `_engine`；`_ensureFjs` 每次先問 `initialized`，失敗的初始化不留著。
- 改之前紅、改之後綠：把 `lib/` 的修正反向套掉，兩條新測試各紅 3/3，套回轉綠；再單獨拿掉清 `_fjsReady` 那行，重試測試紅（`Expected: false, Actual: <true>`），加回轉綠。

### 驗證

- 四平台實跑（匿名，各搜一次 `lemon`，持共用裝置鎖；截圖留在暫存目錄）：
  - macOS：列出 B 站結果（標題、作者、時長），log `GET …keyword=lemon -> 200 in 514ms`。
  - iOS 模擬器：硬體鍵盤的注音把 `lemon` 打成組字中的注音，沒送出（log 沒有請求）；重開 App，`simctl pbcopy` 放進剪貼簿、長按欄位貼上，讀回欄位是 `lemon` 才按搜尋。列出 B 站結果，log `-> 200 in 469ms`。
  - Android 模擬器：`adb shell input text lemon`，讀回欄位是 `lemon` 才按搜尋；列出 B 站結果，log `-> 200 in 1095ms`。
  - Windows（`winpc`）：`shot.ps1 -Type lemon`，`foreground_is_fmp=True`，列出 B 站結果，log `-> 200 in 1238ms`，關閉時 `exited_after_close=True`。
- 完整閘門（`dart run tool/check.dart`，commit cb1bc773）第一次就全綠：

```
ok   i18n (slang)
ok   codegen (build_runner)
ok   format
ok   analyze
ok   test
ok   schema snapshot (drift)
ok   doc gate
ok   doc gate tests
ok   build macos
ok   build ios
ok   build android
ok   lock shared devices
ok   build windows
ok   integration_test macos: integration_test/app_test.dart
ok   integration_test macos: integration_test/search_and_play_test.dart
ok   integration_test ios: integration_test/app_test.dart
ok   integration_test ios: integration_test/search_and_play_test.dart
ok   integration_test android: integration_test/app_test.dart
ok   integration_test android: integration_test/search_and_play_test.dart
ok   integration_test windows: integration_test/app_test.dart
ok   integration_test windows: integration_test/search_and_play_test.dart
ok   unlock shared devices
ok   plugin bundles (esbuild)
```

### code-review（a68a92c7 起）

已處理：清 `_fjsReady` 那段原本沒有測試證明（重試前先 `loadFjsForTests()`，走不到），重試測試加一次「沒初始化就再試」並斷言是新的例外；fjs 在主機上初始化失敗與關引擎的行為補成事實 K28，測試註解引用它；`PluginHost.close()` 不再讀 `Plugin` 的私有欄位，留 `Plugin._closeEngine()`；`_retire` 的參數改名 `pending`；測試的 `_HookedLog` 拿掉 `plugin` 欄位、`onLog` 改名 `onWarningOrError`。

未處理：

- 「快取的 future 失敗時若還是同一個就清掉再 rethrow」在 `js_engine.dart` 與 `plugin_host.dart` 各一次：各一行，抽 helper 不划算。
- 重試測試的前提是主機上 `LibFjs.init()` 不帶參數會失敗；哪天 fjs 在預設路徑找得到原生庫，第一個斷言會紅並說明原因（`fjs is not initialized yet`），不會無聲失效。

Session 紀錄：2026-11-15 兩個插件宿主競態各寫出改之前紅的真引擎測試並修好，四平台各搜一次，完整閘門綠
決定：逾時競態的重現在測試裡包一層 `Log`、在 B 寫失敗 log 時發出 C，宿主不為測試加 seam（Agent 定）
決定：只有還是目前引擎的那個 future 才清掉並關，之後才失敗的呼叫不動新引擎（Agent 定）
決定：建引擎與 fjs 初始化失敗都不快取，下一次呼叫重試；`_ensureFjs` 每次先問 `initialized`（Agent 定）
決定：建引擎失敗的測試獨立成檔，以主機上未初始化 fjs 造出非 `JsError` 的失敗（Agent 定）
變更：Fixed｜搜尋｜插件卡住逾時後緊接著的搜尋不會被連帶誤判失敗；插件引擎啟動失敗後，下一次搜尋會重新啟動
