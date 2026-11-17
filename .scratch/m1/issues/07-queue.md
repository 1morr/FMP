# 07: 佇列與佇列頁

Status: ready-for-agent
Blocked by: 02、06
讀: brief §6；`GLOSSARY.md`〈佇列〉；`docs/design/DESIGN.md` §6.1、§6.3；`docs/design/queue.html`；architecture〈依賴規則〉〈測試策略〉；spec〈共同規則〉

## What to build

有佇列：搜尋結果的選單可以「加入佇列」「下一首播放」，播完自動接下一首，迷你播放器、播放膠囊有上一首、下一首；佇列頁照稿列出播放順序，開啟時捲到正在播的那首，點標頭「佇列」捲回去，可以拖動排序、用 × 移除（移除正在播的那首時接著播下一首）、清空（要確認，清空後停止播放），空佇列照稿。

開工前（擁有者在場）：檢查 `winpc` 硬體（Windows 記憶體診斷要重開機），順便追 MSB8066 的根因（`docs/development.md`〈`winpc` 的 Dart 偶發當掉〉）；在四個平台親耳聽一次播放。結果記在 Comments。

佇列的規則是純 Dart，介面用 `mattpocock-skills:codebase-design` 設計，要能接 08 的隨機與循環、09 的臨時播放、10 的持久化；這張票只做不隨機、不循環。搜尋頁照稿在 14，這張票在佔位搜尋加上選單項目即可。

## 驗收

- [ ] 開工前的硬體檢查與四平台親耳聽已做，結果在 Comments。
- [ ] 佇列的規則有單元測試：加入、下一首播放、播完接下一首、上一首、下一首、拖動、移除正在播的那首、清空後停止。
- [ ] 佇列頁的截圖和 `queue.html` 對得上（捲到正在播放、拖動、空佇列、清空確認、桌面右鍵）。
- [ ] 四平台實跑：加入兩首、播完第一首自動接第二首，讀回佇列頁。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
開工前・`winpc` 硬體檢查（2026-11-17，擁有者在場）：重開前今天有兩次 Kernel-Power 41：03:29:46（BugcheckCode 0，沒有藍屏）與 13:24:41（BugcheckCode 59，P1 `0xc0000005`）；13:24:54 BugCheck `0x3B`（`0xc0000005`，`0xfffff800197b9f23`，`0xffffa1803f01e640`，0），minidump `111726-19359-01.dmp`。14 天內 10 次 Kernel-Power 41、9 次藍屏；WHEA 沒有紀錄；今天另有 8 次 `dartaotruntime.exe`（`0xc0000409`，位移 `0x332aa1`）、1 次 `gen_snapshot.exe`、`CL.exe`、`sppsvc.exe`、`powershell.exe`（clr.dll）存取違規。環境：i9-13900HX、BIOS KWCN54WW、microcode `0x12E`、SK Hynix DDR5-5600 16 GB ×2、VBS 開著、背景跑 Lenovo Legion Toolkit
開工前・minidump：用 cdb `!analyze -v` 讀 `C:\Windows\Minidump\` 的 5 個檔，每次落在不同模組：11-12 `0x20001` intelppm!HvRequestIdle（NMI 路徑）、11-13 `0x1E` nt!KeContextFromKframes（NMI 路徑）、11-14 `0x1E` WdFilter、11-15 `0xA` `IP_MISALIGNED_GenuineIntel.sys`、11-17 `0x3B` FLTMGR!FltpPerformPreCallbacksWorker（行程 sshd.exe）。沒有共同的驅動，指令指標錯位、NMI 中斷，像硬體不穩，不像某個驅動的 bug
開工前・記憶體診斷：擁有者同意後經 SSH `bcdedit /bootsequence {memdiag}`、`shutdown /r /t 60`；14:11 關機、14:36 開進 Windows（標準測試約 25 分鐘），擁有者 15:14 登入。`MemoryDiagnostics-Results` 事件沒有寫出（System 與它的 Debug 頻道都是 0 筆；手動執行 `ProcessMemoryDiagnosticEvents` 結束碼 0 也沒寫）。結果只留在 `HKLM\SYSTEM\CurrentControlSet\Control\MemoryDiagnostic` 的 `Results`：開始時間 2026-11-17 14:11:24，兩輪各 6 項測試，每項的錯誤數欄位都是 0（格式沒有官方文件，是 Agent 自己解讀的）
開工前・MSB8066 根因：還沒定位。記憶體標準測試沒找到錯誤、5 個 minidump 不共用驅動，剩下處理器（電壓、microcode）、BIOS 或 Legion Toolkit 的電源設定。可以再查：Lenovo 有沒有比 KWCN54WW 新、帶較新 microcode 的 BIOS；Legion Toolkit 有沒有降壓或超頻；需要時跑延伸記憶體測試或 CPU 壓力測試。閘門照 docs/development.md〈其他已知怪癖〉照實報紅、重跑
開工前・四平台親耳聽（2026-11-17）：每個平台由 Agent 啟動 App、搜尋「lofi」、播第一首（BV1G9sZ6UEQw），再問擁有者聽到的聲音
決定：macOS 有聲音、正常（使用者定）
決定：iOS 模擬器（iPhone 18 Pro）有聲音、正常（使用者定）
決定：Android 模擬器（Medium Phone）選「有聲音，正常」；其實有點雜音和斷續，但舊版在模擬器開發時也這樣、實機正常，所以算正常（使用者定）
決定：Windows（`winpc`）有聲音、正常（使用者定）
發現：macOS 點下到出聲約 18 秒，log 有 `Playback stalled: buffering for over 15000 ms`；屬 M0 留下的「macOS 點下到出聲慢」，交給失敗處理與預載的票
發現：iOS 模擬器的鍵盤是注音，`orca emulator type` 打不了英文；改用 `simctl pbcopy` 再長按欄位（`orca emulator gesture` 的 begin、end 兩點，end 加 `delayMs`）叫出「貼上」，`orca emulator type $'\n'` 送出
