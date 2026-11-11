# 02: 完整閘門

**What to build:** 一條指令 `dart run tool/check.dart` 跑完新版合併前要過的全部檢查：quick 之外，在 macOS、iOS 模擬器、Android 模擬器、Windows（`winpc`）建置並跑 `integration_test`。這張票先放一條「App 啟動後看得到佔位畫面」的 `integration_test`，之後的票往裡面加。

讀：plan §2、§3、§4；brief §4；票 01 的 Comments；spec〈共同規則〉

**Blocked by:** 01

**Status:** done

- [x] 完整版依序做：quick、四平台建置、四平台 `integration_test`；任一平台失敗就非零退出，並指出是哪個平台、哪一步。
- [x] Windows 照票 01 的做法經 SSH 同步工作樹（不 push）、在桌面工作階段跑建置與 `integration_test`，結果與輸出取回 Mac。
- [x] 避開 plan §2 列的 `integration_test` 怪癖：一次一個檔；Android 不刪模擬器上同 applicationId 的資料。
- [x] 有一條 `integration_test`：App 啟動後看得到佔位畫面，四平台都通過。
- [x] 留好「插件打包產物是否最新」這一步的位置，由票 08 填入；這張票不做假的檢查。
- [x] plan §2 每個平台一節：框架與套件、建置指令、實跑驗證的方式。
- [x] 貼一次完整版綠燈的輸出。

## Comments

### 決定與取捨

- **做法**：`tool/check.dart` 只解析參數，步驟由 `tool/src/gate.dart` 的 `gateSteps` 組，平台步驟在 `tool/src/full_gate.dart` 的 `platformSteps`。外部指令都經 `Shell`（`tool/src/steps.dart`），測試換成假的 `Shell`，不必真的建置就能驗順序、失敗時的步驟名稱與 Windows log 的判斷。步驟名稱帶平台與檔名（`build ios`、`integration_test windows: integration_test/app_test.dart`），沿用票 01 的 `runSteps`：前面失敗也照跑完，最後列出 `ok`／`FAIL`。
- **選裝置**：從 `flutter devices --machine` 挑第一台 `emulator: true` 的 iOS／Android 裝置，找不到就讓那個平台的 integration_test 失敗，不自動開模擬器，也不會挑到連著的實機（開發機連著一台實體 iPhone）。iOS 也加了 `--no-uninstall`（票只要求 Android，對 iOS 無害，行為一致）。
- **Windows**：新增 `tool/winpc/test.ps1`（一次一個檔跑 `flutter test <檔> -d windows`），`sync.sh` 一起同步。每次執行前先刪遠端 log，避免工作沒跑起來時讀到上一次的結果；log 每個 `exit <階段>=<碼>` 都是 0 且有 `=== done` 才算過，取回存在 `app/build/winpc/`。腳本用 `Out-File -Encoding ascii` 寫 log，取回時不需要 cp950 轉碼（非 ASCII 字元會變成 `?`，不影響判斷）。故意讓 Windows 的 integration_test 失敗時，log 是 `exit test=1`，退出碼確實傳回來。
- **插件打包產物**：`gate.dart` 的平台步驟後面留一行註解標出位置，沒有假的步驟；票 08 接上時在 `gate_test.dart` 補一個步驟名稱。
- **建置模式**：四平台都建 debug（和 integration_test 一致）；release 建置不在閘門裡，票 01 實測過四平台 release 都建得起來。
- **文件**：plan §2 各平台補「框架與套件／閘門／實跑」，§1.4 補 `integration_test`，§4 寫完整版的步驟、`FAIL` 格式與前置條件（在 Mac 上跑、模擬器先開好、`winpc` 桌面有人登入）。這些是描述做法，沒有改 §4 的決定。`AGENTS.md`〈目錄〉與流程第 3 步原本寫「票 02 接上完整版之前跑 `--quick`」，接上後改成完整版。
- **`run_task.sh` 的修正**：原本輪詢時一次 SSH 失敗就當成工作結束、刪掉排程工作，連帶終止還在跑的建置（`winpc` 藍屏時遇到）。改成查詢失敗就重試，連續 12 次才回傳非零；寫進 plan §2。
- **撤掉的測試**：票 01 的「`check.dart` 不帶 `--quick` 時拒跑」測試刪掉，由 `test/tool/gate_test.dart` 接手（`--quick` 只有五步、完整版接上八個平台步驟）。中途加過「非 Mac 拒跑完整版」，沒有測試也不必要（在別的平台跑會在 `build macos` 失敗並指名），code-review 後拿掉。

### 驗證輸出

`cd app && dart run tool/check.dart`（完整版，2026-11-11 第四次，2 分 52 秒）：

```text
ok   i18n (slang)
ok   format
ok   analyze
ok   test                     # 00:02 +70: All tests passed!
ok   doc gate
ok   build macos
ok   build ios
ok   build android
ok   build windows            # exit pubget=0、exit slang=0、exit build=0
ok   integration_test macos: integration_test/app_test.dart     # +1: All tests passed!
ok   integration_test ios: integration_test/app_test.dart       # +1: All tests passed!
ok   integration_test android: integration_test/app_test.dart   # +1: All tests passed!
ok   integration_test windows: integration_test/app_test.dart   # +1: All tests passed!、exit test=0
gate_exit=0
```

第一次（code-review 前）也全綠。第二、三次閘門照實報了兩步失敗，都是環境問題，不是程式：

- `FAIL build windows`：`flutter_assemble` 的 MSB8066。擁有者告知 `winpc` 那段時間藍屏過；重開後乾淨同步、以排程工作建置就成功了。
- `FAIL integration_test android`：Mac 上的 adb daemon 被停掉（同時有別的 session 在用同一台模擬器），`flutter devices` 看不到模擬器。`adb devices` 重啟 daemon 後恢復；做法寫進 plan §2〈其他已知怪癖〉。

另外故意讓 Windows 的 integration_test 失敗，log 是 `exit test=1`，退出碼確實傳回 Mac。

### code-review 未處理的發現

- Spec（判斷題）：quick 失敗時仍照跑四平台，要幾分鐘才結束；沿用票 01 `runSteps`「一次看到全部問題」的行為，plan §4 已寫明。
- Standards（判斷題）：平台用字串表示（`'ios'`、`'android'`），沒有另立 enum；四個平台、只有一個模組用到。
- Standards（判斷題）：`C:\fmp-wt` 與 log 檔名同時寫在 Dart、`sync.sh` 與 `.ps1`；`.ps1` 必須是純 ASCII 的獨立腳本，沒有共用設定。Dart 端已改成明寫遠端 log 名稱，不再從腳本名推。
- Standards（判斷題）：`_Winpc._task` 的五個字串參數總是成組出現（建置一組、測試一組），只有兩個呼叫端，沒有另立型別。
