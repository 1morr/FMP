# 08b: 實跑不搶擁有者的游標

Status: done
Blocked by: None
讀: `docs/development.md`〈平台〉四節的「實跑」與〈開發環境與閘門〉；`ARCHITECTURE.md`〈測試策略〉（integration_test、零聯網）；`app/tool/winpc/shot.ps1`；`app/test/architecture/integration_test_guard_test.dart`；票 05b、05d、08 的 Comments（實跑怎麼點的）；spec〈共同規則〉

2026-11-17 協調者插票（擁有者定）：實跑時 Windows 用 `shot.ps1` 的 `-Click`、`-TypeAt`（`SetCursorPos` 加 `SendInput`），macOS 用 CGEvent，會把擁有者正在用的游標移走。擁有者定兩點：實跑優先用不碰游標的方式驅動 App；真滑鼠只留給 Flutter 看不到的原生視窗行為。四平台用同一套做法。排在 08 之後、09 之前。

## What to build

- **實跑驅動**：用 integration_test 在 Flutter 裡送點擊與輸入（系統游標不動），打真的音源（匿名，照 spec〈共同規則〉的聯網規則），每一步截圖或讀回畫面文字，存到 `<暫存目錄>`。四平台同一個情境檔、同一種跑法（`flutter test <檔> -d <裝置>`，Windows 經 `tool/winpc/run_task.sh`）。這張票提供：
  - 骨架，以及截圖與讀回的輔助。
  - 指令。
  - 一個範例情境：啟動後不動視窗先截一張，搜一次，播一首，進佇列頁讀回順序。

  之後每張票照它寫自己的情境，例如加幾首、開隨機、讀回佇列。
- **零聯網守門**：`integration_test/` 的每個檔都要裝 no-network guard，由 `test/architecture/integration_test_guard_test.dart` 守著。實跑驅動要聯網，放在哪、閘門怎麼不跑到它、守門測試怎麼改，選一種並說明理由。動到 ARCHITECTURE〈測試策略〉的話，先用 AskUserQuestion 給擁有者看草稿。
- **規則寫進 `docs/development.md`**：實跑一律先用這個驅動，平台工具只用在 Flutter 看不到的原生行為：
  - 桌面：拖頂列、雙擊縮放、Snap Layouts、拉邊緣、紅綠燈。用真滑鼠：Windows 是 `SendInput`，macOS 是 CGEvent。
  - 手機：系統手勢、軟鍵盤、系統媒體控制。用 simctl、adb、`orca emulator`，這些不動 Mac 的游標。

  各平台的「實跑」段改成先寫驅動、再列例外。`shot.ps1` 的 `-Click`／`-TypeAt` 留給例外用，或者沒人用就刪掉。
- 截圖照舊要包含「啟動後不動視窗先截一張」（票 05d 的教訓）。integration_test 開視窗時一樣會搶前景，這點不在這張票的範圍。

## 驗收

- [x] 範例情境在四平台各跑一次，截圖和讀回的文字對得上。跑的過程中 Mac 與 `winpc` 的游標位置不變：跑前、跑後各讀一次游標座標比對，Mac 用 `CGEventGetLocation`、winpc 用 `GetCursorPos`。
- [x] 完整閘門不跑實跑驅動；零聯網守門照舊擋得住其他沒裝 guard 的 integration_test 檔：手動造一個違規確認會紅，這一步不 commit。
- [x] `docs/development.md` 的規則與四平台指令已更新；提到實跑方式的其他文件（spec〈共同規則〉、AGENTS.md）一致。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments

做法：`integration_test/real_run/driver.dart` 的 `RealRun` 用 `tester` 在 Flutter 裡點擊與打字（系統游標不動），開真的 App（`main.dart`）打真的 B 站；每一步 `run.step` 先讓畫面畫完，再向宿主要一張系統截圖、等回覆才往下做，讀回畫面上看得到的文字。宿主是 `tool/real_run.dart`：macOS、iOS、Android 在 127.0.0.1 開截圖服務（`tool/src/real_run_host.dart`，Android 經 `adb reverse`），用 `screencapture -l`、`simctl io screenshot`、`adb exec-out screencap`；Windows 的 App 本身就在 `winpc` 的桌面工作階段，驅動直接跑 `shot.ps1 -AppPid` 截自己的視窗，跑完 scp 回來。範例情境 `search_and_play_run.dart`：啟動後不動視窗先截 `01-launch`，搜一次「lofi」、點第一首、進佇列頁讀回。
實跑（2026-11-17，6d23dd14，每平台匿名搜一次、播一首，整串持共用裝置鎖；截圖在本機暫存目錄）：四平台都 `All tests passed`，各 4 張截圖加讀回文字，對得上：macOS 800×600 細欄，紅綠燈在細欄頂端（系統畫的部分有截到）；iOS 模擬器有系統狀態列；Android 模擬器（英文、淺色）有狀態列與手勢列；Windows 1920×1080 實體像素，自繪視窗鈕。佇列頁四平台都讀回 1 首、正在播的就是點的那首（【Lofi｜梦核｜蓝调治愈】…，59:33）。
游標：Mac（`CGEventGetLocation`）在 macOS、iOS、Android 三段前後都是 (1346,1439)；更早的三次也都不變。Windows 那段 Mac 游標從 x=1346 移到 1151，那段 Mac 上只跑 ssh、scp、dart。`winpc`（`GetCursorPos`，在桌面工作階段讀）前後讀數三次都不同；改成每 100ms 取樣：23:00 那次 App 整段（約 23:00:22–37）游標停在 (2172,440) 27 秒沒動，前後都是每 100ms 幾像素的連續軌跡；最終那次 App 跑的期間游標在 y≈1800–1860 抖動，都在 App 視窗（y 到 1095）外，驅動點的位置都在視窗裡。資料隔離那輪 Mac 游標在 macOS、iOS 兩段也有變。協調者轉問，擁有者本人確認 winpc 與 Mac 那段時間的游標移動是自己動的。
零聯網守門：手動加一個沒裝 guard 的 `integration_test/zz_violation_test.dart`，`integration_test_guard_test` 紅（`Actual: ['integration_test/zz_violation_test.dart']`）；把 `integrationTestFiles` 改成收所有 `.dart`，`full_gate_test` 收檔那條紅；兩者都還原、沒 commit。`readBack` 拿掉視窗交集或圖示字過濾，各自的測試紅。
這張票開發中沒用 SendInput、CGEvent、`orca computer` 的點擊。前後加讀游標的那幾次，是把整串放進一個 `device_lock.dart -- bash` 裡，裡面的 `real_run.dart` 認得已持鎖、不另拿，外層等它結束才放。
意外：寫 CLI 的拒收測試時，`integration_test/real_run/real_run.dart`（當時的驅動檔名）本身以 `_run.dart` 結尾，被當成情境拿了共用裝置鎖、在 macOS 跑了一下就失敗退出；驅動因此改名 `driver.dart`，測試守著。
發現：iOS 模擬器播這首 B 站時，迷你播放器一度顯示 `0:05 / 33:10`，佇列頁與搜尋結果是 59:33；macOS、Android、Windows 是 59:32。不在這張票修。協調者插修復票 06b。
發現：`winpc` 上擁有者正在用時，實跑（與閘門）的 App 視窗一開始照樣會搶前景；票面說這點不在範圍，development.md〈實跑驅動〉提醒先說一聲。截圖本身已改成不拉前景（見下）。
資料隔離（協調者要求，d6c835cf）：實跑的 App 帶 `FMP_SCRATCH_DATA=fmp-real-run`，資料庫、log、封面快取整份放裝置系統暫存目錄底下的 `fmp-real-run/`，驅動開 App 前清空、沒帶就不跑。四平台各再跑一次（每平台匿名搜一次）：dev 版的 `fmp.sqlite` 與 `logs/` 大小、時間戳前後一樣（macOS、iOS、Windows 跑前跑後各列一次；Android 的 log 與封面索引停在上一輪 23:15），隔離目錄裡有 `fmp.sqlite`、`logs/`、`cache/fmpCovers*`。這之前今天的實跑寫到了 dev 版的 log（四平台）與封面索引（Windows `fmpCovers.json`、Android `fmpCovers.db`）；資料庫只有空的 schema，沒寫內容。
截圖不拉前景（協調者要求，試一輪）：`shot.ps1 -AppPid` 改用 `PrintWindow(hwnd, PW_RENDERFULLCONTENT)`，不呼叫 `SetForegroundWindow`、不設最上層；`winpc` 實測 4 張都完整（`printwindow=True`），也不再夾到視窗外的桌面。macOS 的 `screencapture -l` 本來就不 activate，實跑工具沒有其他 activate 的步驟。
發現：完整閘門的 `integration_test/app_test.dart` 跑 `app.main()`，在 macOS、iOS 模擬器、Android 模擬器（`--no-uninstall`）與 `winpc` 開的就是 dev 版那份資料庫與 log（這張票沒改它，`appDatabase` 目前沒有表）。留給票 10（第一次建表、佇列跨重啟保存）：閘門的 integration_test 也帶 `FMP_SCRATCH_DATA`，或決定 `app_test` 是否仍要驗 application support 目錄。
code-review 未處理：`real_run.dart` 的「已持鎖就沿用」與「退出碼是情境的結果」沒有自動測試（要開裝置），靠這次四平台實跑驗；只測了不收非情境檔。
code-review 未處理：Windows 排程工作 `/TR` 的 261 字上限沒在程式裡檢查，development.md 寫了情境檔名要短（範例約 165）。
code-review 未處理：`winpc` 的 `C:\fmp-wt\real_run\` 與 `shot-pid.log` 跑完留著；下次實跑先清 `real_run\`，〈Windows〉的清理步驟刪整個 `C:\fmp-wt`。
閘門：`dart run tool/check.dart` 完整版在 d6c835cf 一次全綠（exit=0）：quick 八步、四平台建置、macOS 原生測試、四平台各三個 integration_test（`app_test`、`queue_test`、`search_and_play_test`）、插件打包；清單裡沒有 `real_run` 的情境。
Session 紀錄：2026-11-17 實跑驅動：integration_test 在 Flutter 裡點擊、系統工具截圖、資料放隔離目錄，四平台跑範例情境，游標不動；development.md 改成先用驅動、再列真滑鼠例外
決定：游標移動歸為擁有者自己動，不重量（使用者定）
決定：實跑情境放 `integration_test/real_run/`、檔名 `*_run.dart`，閘門與零聯網守門只收 `*_test.dart`；ARCHITECTURE〈測試策略〉照草稿改（使用者同意）
決定：截圖用系統工具（`screencapture -l`、`simctl io`、`adb screencap`、`shot.ps1` 截視窗矩形），不在 App 裡拍，系統畫的部分才截得到（Agent 定）
決定：驅動走到一步向宿主要截圖、等回覆才繼續：Mac 端在 127.0.0.1 開截圖服務（Android 經 adb reverse），Windows 驅動直接跑 `shot.ps1 -AppPid`（Agent 定）
決定：跑法是 `dart run tool/real_run.dart -d <平台> <情境檔>`，它跑 `flutter test` 並帶截圖用的 dart-define；直接 `flutter test` 情境會報錯指過去（Agent 定）
決定：結果預設存 `app/build/real_run/<平台>/`（gitignore、每個 worktree 各一份），`--out` 改到暫存目錄（Agent 定）
決定：讀回是畫面上看得到的 `RichText` 文字，照元件樹順序，略過視窗外與圖示字（Agent 定）
決定：例外加一條：改到頂列、標題列、側欄頂端、視窗外殼的票，實跑仍用真滑鼠點一次頂端按鈕並讀回（Agent 定）
決定：`shot.ps1` 刪 `-TypeAt`、`-Type`，留 `-Click` 給真滑鼠例外並註明會移游標；只在最小化時還原視窗（Agent 定）
決定：挑模擬器與 `winpc` 建置、跑測試的流程從 `full_gate.dart` 搬到 `tool/src/devices.dart`，閘門與實跑共用（Agent 定）
決定：實跑的資料用 `FMP_SCRATCH_DATA` 指名、放裝置系統暫存目錄底下，不用 Mac 的路徑（沙盒與模擬器碰不到）；封面快取只在這時換位置，正式版不變（Agent 定）
決定：閘門的 integration_test 寫到 dev 版資料這件事記成發現、留給票 10，這張票不改閘門（Agent 定）
決定：`shot.ps1 -AppPid` 用 `PrintWindow` 截、不拉前景；實測畫面完整，不保留拉前景（Agent 定）
決定：換頁的輔助 `openDestination` 放 `test/support/shell.dart`，手機在搜尋頁先點「回到…」圓鈕再點分頁（Agent 定）
變更：無
