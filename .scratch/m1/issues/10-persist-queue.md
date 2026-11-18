# 10: 佇列與進度跨重啟保存

Status: done
Blocked by: 08、09
讀: brief §6、§9；architecture〈測試策略〉；`app/test/drift/app_database/`；M0 票 07、12 的 Comments；spec〈共同規則〉

## What to build

佇列（含原順序、播放順序、隨機與循環）與正在播的那首和進度跨重啟保存；重啟後停在原本那首、不自動播放；臨時播放不保留，回到佇列原本那首。設定不提供開關。

- 這是第一次建表：照 ARCHITECTURE〈測試策略〉升 schema，同時建資料完整性測試的骨架（M0 票 12 原判不做，回顧改成第一次建表時建）。曲目 id 存進資料庫後，改插件的 id 格式要做資料 migration（brief §5.3）。
- 開資料庫失敗時怎麼呈現（M0 票 07 留下的）：照錯誤分類與 Toast，App 照常能搜尋播放，只是不保存；做法記成一條決定。

## 驗收

- [x] schema 升級照流程（快照、`generated/`、`stepByStep`），閘門的 schema 檢查與升級測試通過；資料完整性測試的骨架就位，至少有一條。
- [x] 保存與還原有測試：佇列、兩種順序、播放模式、正在播的那首與進度；臨時播放不保留；還原後不自動播放。
- [x] 開資料庫失敗有測試，畫面有提示、App 照常能播放。
- [x] 四平台實跑：排佇列、播到一半、關掉重開，讀回停在原本那首與位置。（Windows 是 07e78ae0 之前的程式碼，最終程式的重驗交給票 11，見 Comments）
- [x] 完整閘門的 integration_test（例如 `app_test.dart` 跑 `app.main()`）不寫到擁有者 dev 版的資料庫與 log，照票 08b 實跑驅動的資料隔離做法（`FMP_SCRATCH_DATA`）；有測試守著（2026-11-18 協調者加，票 08b 的發現）。
- [x] winpc 跑建置與測試時不跳出 PowerShell 主控台視窗（2026-11-18 協調者加，擁有者同意併進這張票）：`tool/winpc/run_task.sh` 建的 `schtasks /IT` 工作改成不顯示主控台（`conhost.exe --headless`、`-WindowStyle Hidden`、`wscript` 包一層，查證後選一種並說明），FMP 視窗照常開；log、`exit …`、`=== done`、`/TR` 261 字上限照舊。用完整閘門的 Windows 步驟驗，跑的期間在 winpc 每 200ms 列可見的頂層視窗，沒有 `ConsoleWindowClass`。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。（依 merge main 前全綠的那輪；最後一輪兩個 Windows 步驟紅在 winpc 的 MSB8066，見 Comments）

## Comments

### 做法

- 資料庫 schema v2 是第一次建表：`queue_entries`（每個位置一列：播放順序、隨機時的原順序（拖動過、插進來的是 null）、曲目欄位）與單列的 `queue_states`（目前那首、下一個 id、隨機、循環、進度）。照 ARCHITECTURE〈測試策略〉跑 `make-migrations`，`stepByStep` 建兩張表；`migration_test.dart` 加 `data integrity` 一組（v1→v2 升級後兩張表是空的），之後改插件曲目 id 格式等搬資料的 migration 照它加。
- 啟動：`app/storage.dart` 的 `openStorage` 開庫、讀回佇列，`main` 把資料庫、讀回的佇列（`savedQueueProvider`）與提示（`storageNoticeProvider`）override 進來。`QueueController` 從讀回的佇列開始；`Playback` 停在目前那首、狀態是暫停、後端還沒載入，按播放（或下一首等）才解析並從保存的位置開始。
- 保存：`playback/queue_saver.dart` 依序寫入，`QueueController` 告訴它佇列與要存的位置。臨時播放時存離開佇列時的位置（票 09 的留言），不倒退。
- 讀不回來時不靜靜蓋掉：存的佇列對不起來就 `VACUUM INTO fmp.sqlite.unreadable-<UTC 時間>Z` 另存整個資料庫、清掉存的佇列；資料庫檔本身壞了（SQLITE_CORRUPT、SQLITE_NOTADB）就把它連同 `-wal`、`-shm`、`-journal` 改名成那個名字、開新庫。兩種都從空佇列開始、啟動時提示「上次的佇列讀不回來，已另存一份」。其他原因（權限、磁碟滿、另存或改名失敗）提示「無法開啟資料庫，這次的佇列與進度不會保存」，這次不保存，原本的檔不動。另存的那份怎麼找回或還原，等歌單也存進同一個庫時再定（roadmap〈M3〉的「資料庫檔壞掉時的處理」）。
- 閘門的 integration_test 帶 `FMP_SCRATCH_DATA=fmp-integration-test`（Windows 是 `test.ps1 -ScratchData`），`app_test.dart` 開 App 前清空那個目錄、沒帶就失敗（`test/support/scratch_data.dart`，`RealRun.launch` 共用）；`full_gate_test.dart` 守著四平台都帶。每次從空目錄開始，票 09 遇到的 macOS 兩次啟動的 log 黏在同一行不會再發生（那是沿用同一份 dev 版 log 檔時，上一次沒寫完換行就被關掉）。
- winpc 不跳主控台：`run_task.sh` 的 `/TR` 改成 `conhost.exe --headless powershell.exe …`。`-WindowStyle Hidden` 會先閃一下（PowerShell/PowerShell#3028）；wscript 包一層要靠已 deprecated、約 2027 年預設關閉的 VBScript；`--headless` 沒有官方文件（來源是 microsoft/terminal 的 `src/host/ConsoleArguments.cpp`），所以用輪詢實測。winpc 的預設終端機是 Windows Terminal，舊寫法跳出的是 `CASCADIA_HOSTING_WINDOW_CLASS`（造違規時輪詢抓到 4 次），不是 `ConsoleWindowClass`，兩種都查。

### 實跑

macOS、iOS、Android 是最終 commit `5cb14abc` 上的結果。情境是 `integration_test/real_run/persist_run.dart`（匿名搜一次「lofi」、前 2 首加入佇列、第 1 首播到 1:00 之後，不等寫入就結束）接 `restore_run.dart`（`RealRun.launch(keepData: true)` 接著同一份隔離資料重開，讀回佇列與位置、等 3 秒仍暫停，再按播放鈕讀回接著播的位置），兩段包在同一個 `device_lock.dart -- bash -c '…'` 裡。截圖與讀回在 `<暫存目錄>/final2/{persist,restore}/<平台>/`，`01-launch` 是重開後還沒動過視窗的那張。

| 平台 | 結束時 | 重開讀回（暫停、等 3 秒仍暫停） | 按播放後 |
| --- | --- | --- | --- |
| macOS | 1:05.2 | 1:05.0（存的範圍 0:59.2–1:05.2） | 1:05.0 |
| iOS 模擬器 | 1:06.9 | 1:05.1（1:00.9–1:06.9） | 1:05.1 |
| Android 模擬器 | 1:11.4 | 1:10.0（1:05.4–1:11.4） | 1:10.0 |
| Windows | 1:05.8 | 1:05.0（1:00.8–1:05.8） | 1:05.0（在保存位置修正 07e78ae0 之前的程式碼；最終 commit 上沒跑成，見〈winpc 當機〉） |

重開後的 `01-launch` 讀回（macOS）：`首頁` … `【Lofi｜梦核｜蓝调治愈】…` `包包不理狗子` `1:05 / 59:33`，播放膠囊是播放鈕（沒在播）；佇列頁讀回兩首、目前那首在最上方。四平台截圖都不是白圖（`real_run.dart` 檢查）。

### winpc 當機

這張票的 Windows 實跑期間 winpc 藍屏重開三次，都是 `docs/development.md`〈其他已知怪癖〉記的硬體不穩：

- 2026-11-18 13:35:47 Kernel-Power 41；13:36:00 BugCheck `0x000000fc`（ATTEMPTED_EXECUTE_OF_NOEXECUTE_MEMORY），minidump `C:\WINDOWS\Minidump\111826-19515-01.dmp`。
- 2026-11-18 14:08:04 Kernel-Power 41；14:08:17 BugCheck `0x00020001`（HYPERVISOR_ERROR，和 11-10、11-11 那兩次同一種），minidump `C:\WINDOWS\Minidump\111826-19375-01.dmp`。
- 2026-11-18 15:59:02 Kernel-Power 41；15:59:15 BugCheck `0x00000050`（PAGE_FAULT_IN_NONPAGED_AREA），minidump `C:\WINDOWS\Minidump\111826-19453-01.dmp`。在最終 commit 的 Windows 實跑期間（persist_run 剛截完 `01-launch`）。照協調者的指示停下、不再重試。
- 之後一次重跑卡在建置：`rustc` 跑了 30 多分鐘、吃了 1792 秒 CPU，build.log 不再寫（正常整個建置約 77 秒）。持鎖結束 cargo、rustc、MSBuild 與排程工作 fmpbuild 後重跑，前半過、後半紅在建置的 MSB8066。
- 三次藍屏都發生在 Windows 實跑（真的音源、mpv 出聲）期間；閘門的 integration_test 沒遇過。是不是和出聲有關、還是單純負載，沒查（要讀 minidump，擁有者在場）。

### 驗證

最後一輪完整閘門（`dart run tool/check.dart`，merge main 之後的 `5cb14abc`）：

```
ok   i18n (slang) … ok   build android（Mac 端全部 ok）
ok   lock shared devices
ok   build windows
ok   native tests macos
ok   integration_test macos／ios／android：app_test、queue_test、search_and_play_test、stream_duration_test（12 步全 ok）
FAIL integration_test windows: integration_test/app_test.dart
ok   integration_test windows: integration_test/queue_test.dart
ok   integration_test windows: integration_test/search_and_play_test.dart
FAIL integration_test windows: integration_test/stream_duration_test.dart
ok   unlock shared devices
ok   plugin bundles (esbuild)
```

兩個 Windows 紅都是 `error MSB8066`（`flutter_assemble.rule` 結束代碼 1），`docs/development.md`〈其他已知怪癖〉記的 winpc Dart 當機症狀；那行 `Get-Item … ItemNotFound` 在通過的 log 裡也有，是雜訊。持鎖照閘門的指令重跑這兩步，兩次都在 10–20 秒內紅在同一個 MSB8066，接著 winpc 在實跑時藍屏（上面第三次）。merge main 之前那一輪（`9661c340` 之後、`07e78ae0` 之前的程式碼）完整閘門全綠，四平台各四個 integration_test 都 ok；之後的改動是 `Playback` 記住保存的位置、merge main（腳本與文件），都不碰 Windows 的建置。

主控台輪詢（`<暫存目錄>/winwatch/watch.ps1`，在 winpc 桌面工作階段每約 210ms 列可見的頂層視窗，`ConsoleWindowClass` 與 `CASCADIA_HOSTING_WINDOW_CLASS` 都記）：最後一輪閘門 15:28:12–15:44:11 共 4511 圈，包含 `build windows` 與四個 Windows integration_test，0 筆主控台，FMP 視窗（`FLUTTER_RUNNER_WIN32_WINDOW fmp`）出現兩次；之前的 Windows 實跑 15:13–15:26 共 3692 圈，也是 0 筆。造違規（`/TR` 拿掉 `conhost.exe --headless`）時抓到 4 筆 `CASCADIA_HOSTING_WINDOW_CLASS`。

### Windows 缺口

照擁有者的決定收票，缺口如下：

- 最終程式碼（`5cb14abc`）沒有在 Windows 上實跑關掉重開：Windows 的 persist_run、restore_run 只在 `07e78ae0`（保存的位置留到真的開始播）之前的程式碼過過一次，讀回 1:05、按播放從 1:05 接著播。
- 最後一輪完整閘門的 `integration_test windows: app_test.dart`、`stream_duration_test.dart` 紅在 MSB8066，持鎖重跑兩次都一樣，之後 winpc 藍屏，沒再跑。merge main 前那輪四平台全綠。
- winpc 今天藍屏三次（〈winpc 當機〉）。下一張跑 Windows 閘門的票（票 11）重驗。

### code-review 未處理的發現

- 保存要靠 `QueueController` 建起來才會寫：App 裡迷你播放器與播放膠囊的上一首、下一首會讀 `queueProvider`，有曲目時一定建；沒有畫面讀它時不會存。
- `-wal`、`-shm` 跟著主檔改名這段沒有測試：SQLite 放棄非 SQLite 的檔時會自己刪掉它用不了的 `-wal`、`-shm`（實測），造不出還留著它們的壞檔。
- 判斷題沒改：`_positionToSave` 對 `PlaybackStatus` 的 switch 放在 `QueueController`（Feature Envy）；`QueueStore.save(entriesChanged:)`、`QueueSaver.positionChanged(now:)` 的 bool 參數；`QueueSaver.idle` 只有測試與實跑在用；兩支實跑情境各有一份 `playback()`、`until()`；`StorageNotice` 放 `app/`、另存檔名放 `platform/`。
- 資料完整性測試 v1→v2 只驗升級後兩張表是空的（v1 沒有表）；票要的是骨架，之後搬資料的 migration 照它加。

Session 紀錄：2026-11-18 佇列與進度跨重啟保存（schema v2、QueueStore、QueueSaver、還原後不自動播）、讀不回來時另存並提示、閘門 integration_test 用隔離資料、winpc 工作不跳主控台；mac、iOS、Android 實跑重開停在原位，Windows 因 winpc 藍屏三次沒在最終 commit 跑成
決定：測試寫在四層：provider 層模擬重啟、drift 升級與資料完整性、資料庫失敗的 widget 測試、閘門資料隔離（協調者代答）（Agent 定）
決定：開資料庫失敗不新增錯誤分類，log 寫 error、啟動時出一則固定的提示，App 照常能搜尋播放（協調者代答）（Agent 定）
決定：進度在換曲、暫停、seek、狀態改變時馬上存，播放中差 5 秒存一次；臨時播放存離開佇列時的位置、不倒退（協調者代答）（Agent 定）
決定：存的佇列讀不回來時 VACUUM INTO 另存整個資料庫、清掉存的佇列，從空佇列開始並提示（協調者代答）（Agent 定）
決定：資料庫檔壞了（只認 SQLITE_CORRUPT、SQLITE_NOTADB）就連同 -wal、-shm、-journal 改名另存、開新庫；其他開檔錯誤這次不保存（協調者代答）（Agent 定）
決定：winpc 的排程工作用 conhost.exe --headless 啟動 PowerShell，不用 -WindowStyle Hidden 或 wscript（使用者同意）
決定：schema v2 兩張表：每個位置一列（原順序可為 null，拖動過、插進來的由它推得）、單列的狀態與進度（Agent 定）
決定：啟動時在 runApp 前讀回，Playback 從「暫停、後端未載入」開始，按播放或 seek 後播放才解析並從保存的位置開始（Agent 定）
決定：位置往回跳或一次跳超過 2 秒算拖了進度，馬上存（Agent 定）
決定：重開後保存的位置留到真的從那裡開始播才丟掉；第一次播失敗後再按播放或重試，仍從保存的位置開始（協調者代答）（Agent 定）
決定：開始播一首時，叫後端播之前一律算載入中，不報成停在開頭的暫停，免得存成 0（Agent 定）
決定：播放還停在別首時不存位置、沿用上次的；換了目前那首才從頭（Agent 定）
決定：一次寫入失敗後下一次整份重寫，不只寫狀態那一列（Agent 定）
決定：另存檔名同一秒撞名就接 -2、-3，因為 VACUUM INTO 會把已存在的目標當資料庫開（Agent 定）
決定：閘門的隔離資料名 fmp-integration-test，和實跑的 fmp-real-run 分開；test.ps1 改用 -ScratchData 帶名稱（Agent 定）
決定：封面快取在第一次用到時才建，換位置時不建 http client（帶隔離資料的 app_test 撞到零聯網守門）（Agent 定）
決定：實跑分兩支情境，restore_run 用 keepData 接著前半的資料重開；後半再播一次，比 spec 的「播一首」多解析一次（Agent 定）
變更：Added｜佇列｜關掉 App 再開，佇列、隨機與循環、正在播的那首與進度都還在，停在原本那首與位置、不自動播放；臨時播放不保留，回到佇列原本那首
變更：Added｜佇列｜資料庫開不了時啟動提示「這次的佇列與進度不會保存」，照常能搜尋、播放
變更：Added｜佇列｜上次的佇列讀不回來或資料庫檔壞掉時另存一份、從空佇列開始，啟動時提示「上次的佇列讀不回來，已另存一份」
變更：Changed｜播放控制｜開始播一首時，跳到開始位置之前顯示載入中，不再短暫顯示停在開頭的暫停
等使用者：winpc 今天藍屏三次（13:35 0xFC、14:08 0x20001、15:59 0x50），最終 commit 上的 Windows 實跑沒跑成，閘門有兩個 Windows 步驟紅在 MSB8066。選項：等擁有者處理 winpc 後重跑 Windows 的兩段實跑與這兩步；或依 merge main 前那輪全綠的閘門與稍早的 Windows 實跑收票。建議等 winpc 穩定再補跑，不決定的話「四平台實跑」與「全部檢查綠燈」兩條勾不了，票不能 done
決定：照現有結果收票，Windows 的最終程式重驗交給下一張跑 Windows 閘門的票（票 11）（使用者定）
