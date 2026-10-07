# M2 執行計畫

「design §n」指本任務的 `design.md`；「決定 n」指 `prd.md` 的擁有者決定。

## 通用規則（每個 PR 子任務）

- **開工**：
  - 從最新的 `main` 開分支；
  - 以 `task.py create "<標題>" --slug <slug> --parent .trellis/tasks/10-01-m2-full-playback --package app` 建子任務；
  - prd 只寫做什麼與驗收（ADR 0026 §決定 1），在已核准的範圍內直接做，遇到未定的事才問。
- **合併條件**：
  - `app/` 可編譯、`flutter test` 全綠；
  - CI 彙總 job `CI Result` 通過；
  - PR 描述附 review 指南。
- **實機驗證**：
  - 使用者看得到的 PR 在 Android 模擬器與 Windows 都照 `verify-on-device` skill 驗，回報寫明平台與模式（ADR 0027）。
  - 預設重播（dev flavor＋測試插件 `fmp-test`）。
  - 改動本身是插件、網路層，或要看真實封面、真實 CDN 時才用真實連線（B 站），只做最少的操作。
- **改播放後端**（`lib/playback/backends/`）：照 `app/AGENTS.md:18` 在 Windows 與 Android 模擬器各跑一次 `integration_test/audio_backend_contract_test.dart`。
- **動到外殼或提示**：照 `app/AGENTS.md:19` 跑 `toast_layering_test.dart`。
- **改 schema**：照 `.trellis/spec/app/data/index.md` § 改 schema 做完整流程（快照、`stepByStep`、三種 migration 測試），design §3.5 的版本號以合併順序為準。
- **收尾**：
  - 子任務 `finish` 與 `archive --no-commit --skip-branch-validation`；
  - 手動 commit；
  - repo 慣例以 merge commit 合併。
- **文件**：
  - 每個 PR 更新 `app/AGENTS.md` 中自己那一層：只寫查不到的契約與有閘門的規則，每條寫出它的閘門；
  - 需要時更新 `.trellis/spec/app/<layer>/`；
  - design §11 列的 ADR 更正在對應的 PR 加。
- **套件版本**：
  - 以 design 開頭與 `research/m2-scope-digest.md` §3 為起點，加依賴時到 pub.dev 核對一次；
  - 裝當前 stable（`audio_service_mpris` 的 beta 不用，Linux 不在 M2）。
- **lint**：新的匯入規則與擁有者表的改動，照 `.trellis/spec/app/lints/index.md` 寫雙向變異案例，並在 `tool/lint_sentinel.dart` 加違規行。
- **子代理模型**：
  - 實作用 sonnet：PR 0、5、6，以及里程碑驗收的文件更新。都是照既有模式的機械性工作。
  - 實作用 opus：其餘全部（播放核心、網路、快取、資料、平台、介面）。
  - `trellis-check` 一律 opus；研究代理一律 sonnet。

## 進度與交接（compact 後從這裡接）

- **狀態**：2026-10-01 擁有者核准（`prd.md` 決定 8，design §12 八條全部照設計）。
- **擁有者決定**：1–9 在 `prd.md`。
- **已合併進 `main`**：
  - PR 0：#195。
  - PR 1：#196（`08449b17`）。`PlaybackSession`、`routePlaybackEvent`（純函數）從控制器拆出；`fmp_layer_imports` 加 `restrictedImports`。
  - PR 2：#197（`35077a47`）。網路狀態、離線提示與搜尋頁離線畫面；`connectivity_plus ^7.3.1`；Windows 的 `/utf-8` 改在 `windows/CMakeLists.txt` 的 `APPLY_STANDARD_SETTINGS`，連插件一起套用。
- **PR 3 已合併**：#198（`02c70fbb`，媒體 client）。審查兩輪：第一輪找到網址 userinfo 會變成 `Authorization`；第二輪（第一輪中途藍屏、紀錄遺失後重審）找到已關閉的 client 被算成「連不上」。兩者都先寫失敗測試再修。
- **PR 4 已合併**：#199（`b28fd138`）。審查兩輪（第一輪中途兩次藍屏）；第二輪修好幽靈列、索引大小、`files/` 被刪後的 `clear()`。實機兩平台真實連線通過（清空快取後第一次 13 張、重開同搜尋 0 張）。
- **PR 5 已合併**：#201（`85ef2cc6`）。審查修了 7 項（data → settings 的反向 import 並補 lint、用量改即時、看不見的設定頁仍攔返回鍵、`clearLiveImages` 的測試、byte size 進位等）；修正後兩平台實機重驗通過。
- **PR 6 已合併**：#202（`6dbf7656`）。審查找到保留期限在 `LogFile` 佇列外刪檔、會和輪替競態，改成 `LogFile.deleteExpired()` 排進寫入佇列；修正後兩平台實機重驗通過。
- **PR 7 已合併**：#203（`06353122`）。審查找到插件更新後仍沿用舊插件解析的網址，快取鍵加上插件實例；兩平台實機重播：兩首解析 2 次，重播兩首都 `from: cache`。
- **PR 9 已合併**：#204（`232e4185`）。審查補了 4 個測試與 `app/AGENTS.md` 三處閘門宣稱；擁有者決定隨機時一輪的第一首按上一首回到開頭、不往回繞。
- **PR 10 已合併**：#205（`c0a87b40`）。審查修了「被換掉的前瞻在佇列沒有下一首時仍出聲」；兩平台實機重播通過。
- **PR 11 已合併**：#206（`73853671`）。兩個真後端契約 14/14；Android 拿不到 HTTP 狀態碼（design §7.6 更正、§7.5 新列）。
- **PR 12 已合併**：#208（`6ed45ee3`）。審查修了「佇列一首時臨時曲目失敗直接停下」「單曲循環捷徑把上一首設成前瞻」；擁有者定了提示文字、停下兩種提示、試聽提示、「只要連不上就等」（design §7.5、§7.9）。
- **PR 8 已合併**：#209（`f84c8b00`）、fmp-plugins#3（`33caa3a`）。遮蔽名單不再拿掉 B 站 `deadline`；擁有者定 B 站備援先往下降；實機真實連線兩平台音質「低」`bitrate: 65551`。
- **PR 13 已合併**：#210（`a137dc54`）。審查修了「duck 中被來電打斷後輸出停在一半」；擁有者定了中斷續播、靜音分開記、裝置清單只列 Windows 裝置（design §7.6）；拔耳機與 Windows 裝置失敗實機未驗。
- **PR 14 已合併**：#211（`1dc53529`）：
  - 實作期定案：`queue_entries.track_key` 建索引（清 1 萬孤兒 9.3 s → 14 ms）；存的資料讀不回來就清掉從空佇列開始。
  - 審查修了「拖曳越過目前這首把位置歸零」「恢復完成前先動了佇列，舊位置套到新的那首」，並補了「寫入失敗，下一次補寫」的閘門。
  - 擁有者定：恢復後還沒播就先臨時播放，結束後按播放仍從恢復的位置開始（design §7.7）。同時修了兩條重複倒退。
  - 實機兩平台（重播／測試插件）通過：五首（有重複曲目）、隨機、循環全部 → 關掉重開，`Playback restored` 欄位正確、啟動不解析，按播放 `restored: true`、從存的位置接著播、照存的隨機順序走；Android 另驗了倒退 10 秒＋臨時播放後，存的位置不被覆寫。音量與靜音沒有 UI（PR 17），只有單元測試。
- **PR 15 已合併**：#212（`7862559e`）：擁有者定了移除單筆、列的副標、只有清除全部提示。審查修了「讀下一頁時剛好記了一筆，清單重複一列、漏掉新的」「dispose 後仍寫入」；主對話另定讀取失敗不顯示成「沒有紀錄」（design §7.8）。實機兩平台（重播）通過：恢復後第一次不記、交接與單曲循環每圈一筆、臨時播放一筆、回到佇列不記，歷史頁「今天」分組、點一列臨時播放、移除單筆、清除全部（確認框、取消不清、提示）、重開仍在。
- **PR 16a 已合併**：#213（`e5cfa91b`）：擁有者定停止＝暫停。審查修了「啟動恢復那首在通知上一直沒有封面」，並把 `pickArtwork` 移到 domain、加了 playback→ui 的 lint。實機（Android，重播＋一次真實 B 站搜尋與播放看封面）通過；鎖定畫面沒驗（模擬器沒設螢幕鎖）。
- **PR 17 已合併**：#214（`bab877df`）：擁有者定輸出裝置失敗改用系統預設。審查修了「臨時播放後進度條顯示錯的位置」「Shift+←／→ 在恢復狀態無效或蓋掉恢復位置」「滑鼠打開的選單按 Esc 關不掉」，並把提示分成兩句。實機兩平台（重播）通過；Windows 的裝置停用要系統管理員權限，裝置失敗的退回沒有實機驗。
- **PR 18a 已合併**：#215（`cfde4a16`）。主對話定佇列分頁先做唯讀清單＋點選跳到、「切換右側面板」延到 PR 19（`layout_state` 這次就含面板兩欄）、左上角收合鈕關閉；實作期推定的決定（預設歌詞分頁、route 自己設開關狀態、遮罩用 `surface`、「⋯」在控制列最後、compact 的切換不寫記憶、佇列分頁捲到目前這首前兩列）主對話接受，記在 design §9.3 末段。審查（opus）修了「關閉轉場中又開一頁，狀態被舊頁設成沒開、焦點被搶走」「第一幀前佇列就空了，留下關不掉的空白頁」「播放列點擊區沒有按鈕語意」，補了五條文件宣稱卻沒有測試的閘門。`flutter test` 1712 通過、2 跳過；Windows 的 `toast_layering_test.dart`、`install_search_play_test.dart` 與 Android 的 `toast_layering_test.dart` 通過。實機兩平台（重播）通過：Windows 點曲名與 Ctrl+Q 開頁、compact（700 px）／medium／expanded（1500 px）／large（1920 px）／extraLarge（2450 px）五種版面、compact 點封面切歌詞且不覆寫記憶、Esc 先關選單再關頁、焦點回到播放列、速度 1.5× 打勾、播放頁上的試聽提示貼底；Android 直向五個控制、點封面切歌詞、返回鍵只關播放頁。F6 只有 widget 測試。
- **PR 18b 已合併**：#216（`a54b194a`）。擁有者定佇列入口在播放頁右上角；主對話定 `moveToNext`（移除再以下一首播放加回，隨機時排序也移過去）、移除不提示清空才提示、三處列選單共用 `TrackRowMenu`、底部面板包 `PlaybackShortcuts`（design §7.3 末段）。審查（opus）修了「compact 清空後提示壓在底部導覽上」「拖曳被取消後自動捲動永遠失效」，並補了幾條原本沒驗到東西的測試。`flutter test` 1772 通過、2 跳過；Windows 兩個整合測試通過。實機兩平台（重播）通過：Windows 隨機下「下一首播放」後 Ctrl+→ 播的就是它、拖曳目前這首仍是目前這首、F6／Tab 到列 Enter 跳到、焦點在列上空白鍵是暫停、移除不提示、清空確認後頁面關閉並提示、medium（1100 px）Ctrl+Q 開頁加面板、面板內空白鍵播放暫停、Esc 只關面板；Android 右上角入口開面板、把手拖曳、長按選單的「下一首播放」、「⋯」移除、返回鍵只關面板、清空的提示在導覽列之上。
- **PR 16b 已合併**：#217（`54fa81b0`），CI 的 Windows runner 內建 Rust、不用改 `ci.yml`。實機（Windows）抓到三件，修好並重驗：`flutter_rust_bridge` 被解析成 2.13.0、與 `smtc_windows` 的 Rust 端 2.11.1 不符，啟動就初始化失敗（直接釘 2.11.1，加比對 lock 與 `Cargo.toml` 的閘門）；`file:///` 封面讀不到，改交 `https`（`NowPlaying.artworkUrl`）；停止鈕沒啟用，停止指令到不了 App。審查（opus）另修「下一首沒有上傳者時留著上一首的」「連接埠 > 65535 的封面網址讓 Rust panic」，補了 SMTC 呼叫順序的測試與 skill 的 `smtc_command.ps1`（只對 FMP 的 AUMID 送指令）。決定記在 design §8.4 末段。`flutter test` 1808 通過、2 跳過。實機：Windows（重播＋一次真實 B 站：搜尋 1、縮圖 10、`nav`／`wbi/view`／`playurl` 各 1；從歷史重播同一首再 `wbi/view`、`playurl` 各 1）idle 沒有工作階段、播放後曲名／上傳者／封面／狀態、toggle／next／stop、位置約每 5 秒；Android（重播）媒體工作階段與 MediaStyle 通知照常。
- **PR 19 完成、待合併**（2026-10-08；分支 `feat/app-now-playing-panel`，子任務 `.trellis/tasks/10-08-now-playing-panel`）。擁有者定收起後從播放列的圖示鈕展開；其他決定記在 design §9.4 末段。審查（opus）修了「視窗 > 4000dp 時寬度寫不進資料庫（CHECK ≤ 1600）」，並更正四處與實測不符的文件與註解（1000 寬時頁面是 compact、`OrderedTraversalPolicy` 沒有閘門、寫失敗回退沒有測試）。實機抓到把手的線 0 高看不到，紅→綠修好。`flutter test` 1853 通過、2 跳過；Windows 與 Android 的 `toast_layering_test.dart` 通過。實機兩平台（重播）通過：Windows（縮放 150%）拖寬寫入一次、拖過上限停在 40%、游標是左右調整、Tab 到把手 ←／→ 各 16dp 每按寫入、線平時灰聚焦變主色、三個入口（標題列、播放列圖示鈕、播放頁「⋯」）都寫 `panel_expanded`、收起重啟後仍收起（連拍 60 張沒看到面板閃出）、寬度重啟後還在、785dp 時面板與開關都消失、885dp 時面板夾到 354 且播放列「⋯」的勾選項可切換、放大回來仍是 490；Android `Medium_Phone` 橫向（914dp）面板 366dp、空狀態、加歌後是詳細、播放列「⋯」與標題列收起鈕切換、觸控拖曳寫入一次。
- **下一步**：PR 19 合併後做 M2 里程碑驗收（本檔「里程碑驗收」一節）。
- **本機環境備忘**（2026-10-03 建、10-07 補）：
  - **模擬器**：`Medium_Phone`，序號會變：開機順序不同時是 `emulator-5554` 或 `emulator-5556`，先 `adb devices` 看。`ax_flatten.py` 要加 `--device <序號>`，`adb` 加 `-s <序號>`。藍屏或重開機後模擬器會關掉，要以分離程序重開（skill 的 android.md）。
  - **adb 可能多出別的裝置**（10-07 出現 `127.0.0.1:16384`，不是我們的模擬器）：一律 `export ANDROID_SERIAL=emulator-5554` 或 `adb -s`，`ax_flatten.py` 加 `--device`，不要碰別的裝置。
  - **PR 16a 之後**：播放中 uiautomator 會「could not get idle state」，先送 `adb shell input keyevent MEDIA_PAUSE` 再讀畫面；媒體狀態用 `dumpsys media_session`、通知用 `dumpsys notification --noredact`。模擬器沒設螢幕鎖，看不到鎖定畫面控制。**跑完 Android 整合測試後，`build/app/outputs/flutter-apk/app-dev-debug.apk` 已被換成整合測試的版本**（它的 `main()` 等測試工具連進來，裝上去會停在啟動畫面、isolate 閒置、堆疊是空的）：重裝前一定先 `flutter build apk --flavor dev --debug`。10-07 因此誤判過一次「全新安裝卡住」。
  - **Windows 同一個坑**：`flutter test integration_test/... -d windows` 也把 `build/windows/x64/dev/runner/Debug/fmp.exe` 換成整合測試入口，直接執行是一個沒有視窗、log 沒有 `App started` 的程序；實機前先 `flutter build windows --flavor dev --debug`（或 `flutter run` 一次）。
  - **送鍵前確認 FMP 在前景**：`SetForegroundWindow` 會被 Windows 的前景鎖擋下，鍵就送到別的視窗（10-07 擁有者看到空白鍵沒進 FMP）。送鍵前先點 FMP 視窗內的空白處（`KX`／`KY`），之後以截圖的標題列或 log 確認有反應。
  - **`smtc_probe.ps1` 一律帶 `-AppFilter fmp`**：不帶會列出擁有者其他 App 的媒體工作階段（含曲名）。
  - **模擬器上的狀態**：dev 版裝著測試插件（`files/test.js`）與 B 站插件（`files/bilibili.js`），介面語言 English，快取上限設成 512 MB。跑過 Android 整合測試會解除安裝 dev，要重裝並以 `run-as` 放回兩個插件，各帶 `--fmp-dev-plugin` 啟動一次。
  - **Windows dev**：跑過 Windows 整合測試要再 `flutter build windows --flavor dev --debug`。dev 的快取上限設成 128 MB。快取在 `%LOCALAPPDATA%/com.personal/fmp-dev/fmp_cache`；同層的 `fmp/`（舊版的 `lyrics`）不要動。
  - **搜尋來源每次啟動都回到 Bilibili**：重播驗證前先點 `FMP Test Plugin` chip，截圖確認選中，否則會對 B 站發真實請求。
  - **Windows 的自動輸入**：
    - 前景鎖常擋住 `SetForegroundWindow`。可行的做法：把 FMP Dev 視窗最小化再還原取得前景，在同一個 PowerShell 程序裡點擊、輸入（`WScript.Shell.SendKeys`）；Enter 另外送，必要時重試。
    - Ctrl+A 全選不可靠，會把字附加上去（例如打成 `lofilofi`），送出前截圖看關鍵字。
    - 腳本在 session 暫存目錄的 `fgtype.ps1`，compact 後還在，換 session 就沒了。
    - **擁有者在用電腦時不要跑會動滑鼠鍵盤的步驟**；被拒絕後要先確認 App 還開著、來源 chip 是哪個。
  - **Windows 送快捷鍵**：用 `keybd_event` 而且掃描碼給 0 時，Flutter 認不出 Ctrl，之後連空白鍵都會失效（修飾鍵狀態被弄亂，要重開 App）。用 session 暫存目錄的 `combo.ps1`（`SendInput`，帶虛擬鍵碼與 `MapVirtualKey` 的掃描碼，方向鍵加 extended 旗標，`-X -Y` 先在同一個程序裡點一下取得焦點），配 `k.sh <VK,VK> <秒> <標籤>` 印出新的 log。停用音訊裝置（`Disable-PnpDevice`）要系統管理員權限，做不到。
  - **msaa_tree.ps1** 要用 Windows PowerShell 5.1（`powershell.exe`）跑，pwsh 7 編不過它的 C#。
  - **藍屏的教訓**（10-02 兩次，都在子代理跑重負載測試時）：
    - 重開後先 `git status`；`index file corrupt` 時把 `.git/index` 移到暫存目錄，`git reset` 重建，`git fsck` 檢查。
    - 再掃改動與新增檔有沒有整檔變成 NUL；能從子代理紀錄的 Read／cat 輸出或 Write／Edit 重放救回，產生碼重新產生比對。
    - 子代理的紀錄尾端會遺失，續跑的代理對藍屏前的事記憶不完整，結論要重驗。
  - **殘留的測試行程**：子代理有時留下卡住的 `flutter test`（`dart.exe` 的命令列是 `flutter_tools.snapshot test …`）。派新的代理或自己跑測試前，先用 `Get-CimInstance Win32_Process` 看建立時間與命令列，只停掉確定殘留的那一個。
  - **產生檔只差換行**時，`git diff --name-only` 的迴圈有時判斷不到；`git diff --ignore-all-space --ignore-cr-at-eol` 為空就直接 `git checkout -- app/linux/flutter app/windows/flutter app/macos/Flutter/GeneratedPluginRegistrant.swift`。新增原生插件的 PR 例外，有真正的註冊要保留。
  - F6 焦點的實機讀法：`msaa_tree.ps1` 加上 `accState` 的 `STATE_SYSTEM_FOCUSED`（0x4）；做法記在 M1 的 `research/m1-acceptance.md` § F6。
  - **10-06／10-07 新增的備忘**：
    - **Android 跑過整合測試會清掉 dev 的資料**（插件也沒了）：`adb push "C:/Users/…/test_plugin.js" /data/local/tmp/test.js`（加了 `MSYS_NO_PATHCONV=1` 時本機路徑要寫 `C:/…`，不能寫 `/c/…`），`run-as` 複製進 `files/`，再帶 `--fmp-dev-plugin` 啟動。
    - **資料庫裡的插件可能是舊版**：改過插件（含測試插件）後，兩平台都要帶 `--fmp-dev-plugin` 重新啟動一次才會更新。
    - **模擬器可能停在上次的橫向**（`user_rotation`）：每次先 `adb shell settings get system user_rotation`，座標一律從 `ax_flatten.py` 讀，不要沿用上一輪的數字。PR 11 就因此誤點 B 站、送出真實請求。按返回鍵時鍵盤沒開會直接退出 App。
    - 歌名多行的節點，取座標用 `grep -o "center=([0-9]*,[0-9]*)"`，不要用 `sed` 整行替換。
    - **Android 音訊中斷**：`adb emu gsm call 5551234`／`adb emu gsm cancel 5551234` 可觸發暫停類中斷；`AUDIO_BECOMING_NOISY` 廣播被系統擋（`SecurityException`）。
    - **Windows 中文輸入法**：`fgtype.ps1` 打完關鍵字要再送一次 Enter 才會搜尋。session 暫存目錄另有 `logsince.sh <log> <起始行>`（濾掉 debug 的 log 摘要）、`restart_win.sh <關鍵字>`、`dbq.sh "<SQL>"`（拉 Android dev 的 `fmp.db` 查詢，已指定 `emulator-5554`）、`k.sh <VK,VK> <秒> <標籤>`＋`combo.ps1`（Windows 送快捷鍵並印新 log，`KX`／`KY` 環境變數指定先點的位置；已加 `-Raise` 先把 FMP Dev 帶到前景，但前景鎖仍可能擋，送鍵前一律給 `KX`／`KY` 點視窗內的空白處，再看截圖標題列或 log）、`drag.ps1 -X1 -Y1 -X2 -Y2`（真滑鼠拖曳，佇列把手用過）、`clickat.ps1`、`resize.ps1 -W -H`（`-W 0` 是最大化，會跑到別的螢幕尺寸，別用）。Windows 縮放 150%：dp × 1.5 = 視窗 px（extraLarge 要 2400 px 以上，`resize.ps1` 可以超出螢幕）。SMTC 改用 skill 的 `smtc_command.ps1`、`smtc_probe.ps1 -AppFilter fmp`。這些換 session 就沒了（skill 裡的除外），PR 描述在 `pr-m2-*.md`。
    - **盯 CI**：PR 剛開時 run 還沒建立，用迴圈等 `gh run list` 拿到 id 再 `gh run watch`。
    - **擁有者全域規則更新（10-07）**：push 分兩種（照核可計畫做的可直接推）；子代理預設 sonnet，只有設計、根因未知的 debug、審查用 opus。
  - **repo 外的待辦**：#207 是 Dependabot 對舊版根目錄 `pubspec` 的升級（`archive`、`flutter_cache_manager`、`go_router`），舊版凍結，留給擁有者決定。
- **每個 PR 的固定流程**：
  1. 從最新 `main` 開分支（Conventional Commits 的英文分支名，例如 `feat/app-queue-model`）；
  2. `task.py create … --parent .trellis/tasks/10-01-m2-full-playback --package app --no-start`；
  3. 寫 prd（繁中，列做什麼與驗收）與 `implement.jsonl`／`check.jsonl`，把 design 的相關節與 `.trellis/spec/app/<layer>/index.md` 列進去；
  4. `task.py start`；
  5. 依上面的模型分配派 `trellis-implement`。驗證清單固定為：
     - `dart format --output=none --set-exit-if-changed .`
     - `build_runner` 後沒有實質變動
     - `dart run slang`（動到翻譯時）
     - `dart analyze --fatal-infos`、`flutter analyze`、`flutter test`
     - `dart run tool/lint_sentinel.dart`（動到 lint 時）
     - 需要時建置（`flutter build apk --flavor dev --debug`、`flutter build windows --flavor dev`）
  6. 使用者看得到的改動，由主對話照 `verify-on-device` skill 實機驗證：Android 與 Windows，回報含平台與模式；
  7. 派 opus `trellis-check`，要它試著攻破安全相關的部分（媒體 client、遮蔽、快取目錄、manifest、插件 API）；
  8. 把後續待辦寫進本檔的「留下的後續」；
  9. `git checkout --` 還原只有換行差異的產生檔（`generated_plugin*`、`*.g.dart`、`GeneratedPluginRegistrant.swift`）。
     - **逐檔**以 `git diff --ignore-all-space --ignore-cr-at-eol` 確認是空的才還原；
     - 加了原生插件的 PR（4、13、16a、16b、2）有真正新增的註冊，整批還原會弄丟（M1 PR 10 踩過）；
  10. 分開 commit（subject ≤ 72 字元，Conventional Commits）；
  11. `task.py finish`，再 `archive <slug> --no-commit --skip-branch-validation`，把 archive commit 掉；
  12. push，`gh pr create`（繁中描述＋review 指南）；
  13. 背景跑 `gh pr checks --watch`；
  14. 全綠後 `gh pr merge --merge`，main 快轉。
- **fmp-plugins 的 PR**（PR 8）：
  - 在同層的 `fmp-plugins/` clone 開分支；
  - 改完以 FMP 的 `FMP_PLUGIN_DIR=<絕對路徑>/bilibili flutter test test/plugins/contract/contract_test.dart` 重播驗證（PowerShell 寫法見 `app/AGENTS.md:47`，跑完刪環境變數）；
  - 在該 repo 開 PR 並合併（擁有者的 repo，直接做）；
  - FMP 的 PR 描述附 fmp-plugins 的 PR 連結。
- **地雷**（M1 帶來的，仍適用）：
  - 文件或程式碼引用子任務的研究檔時，一律寫 archive 後的路徑 `.trellis/tasks/archive/<年-月>/<任務>/…`。
  - CI 的 `app` job 工作目錄已經是 `app/`，路徑不要再加 `app/`。
  - 子代理有時用不了 context7 或 WebFetch，改用 pub cache 原始碼查證是可以的。
  - 子代理因 API 403 或 rate limit 中斷時，用 SendMessage 對同一個 agent 續跑。
  - 桌面裝置一次 `flutter test` 只能跑一個整合測試檔（`app/AGENTS.md:30-32`）。
- **M2 新的地雷**：
  - PR 16a 之後 Android 的 `MainActivity` 繼承 `AudioServiceActivity`。實機驗證帶 `--fmp-dev-plugin` 的 `am start` 前，先確認 design §8.3 的 `provideFlutterEngine` 覆寫仍在。
  - 少了它，參數被靜默忽略、測試插件裝不上，看起來像插件壞了。

## 順序與相依

| PR | 依賴 | PR | 依賴 |
|---|---|---|---|
| 1 | 0 | 12 | 2、7、10、11 |
| 2 | 0 | 13 | 1、8 |
| 3 | 2 | 14 | 6、10、13 |
| 4 | 3 | 15 | 10、14 |
| 5 | 4 | 16a | 4、10 |
| 6 | 0 | 16b | 16a |
| 7 | 1 | 17 | 10、13 |
| 8 | 7 | 18a | 4、17 |
| 9 | 1 | 18b | 10、18a |
| 10 | 9 | 19 | 18a |
| 11 | 1 | | |

- 可以平行的：
  - 2–6 與 1、7、9、11（不同目錄）；
  - 15、16a、17 互不依賴。
- 最長的鏈是 1 → 9 → 10 → 12（或 13）→ 14 → 15。
- 同時開兩個以上分支時，各自的 schema 版本號在後合併的那個 PR 重排。

## 0. 規劃檔與文件更正

- [x] 本任務的 `prd.md`（補上 design §12 的確認結果）、`design.md`、`implement.md`、`research/` commit。
- [x] design §11 標「PR 0」的更正：
  - ADR 0025 §決定 5；
  - ADR 0026 §決定 3；
  - ADR 0019 §決定 1 與 ADR 0018 §決定 4（確認後）；
  - `milestones.md` § M2、§ M3（範圍、驗收的調整）。
- [x] `09-26-fmp-rewrite/task.json` 的子任務清單（目前工作區有未提交的改動，一併整理）。
- 驗證：`main` 上有本任務目錄；`milestones.md` 的 M2 範圍與 design §1 一致。
- 依賴：擁有者核准。模型：sonnet。

## 1. 播放核心拆分與兩條匯入規則（design §7.1、§2）

- [ ] 從 `PlaybackController` 拆出 `PlaybackSession`（唯一碰 `AudioBackend`）與 `PlaybackEventRouter`（純函數）；控制器仍是唯一入口與狀態寫入者。
- [ ] `fmp_layer_imports` 加 `restrictedImports` 機制：
  - `audio_backend.dart` 只給後端目錄、`playback_session.dart`、`playback_providers.dart`；
  - `backend_rules.dart`（結束原因）只給後端目錄與 `playback_event_router.dart`。
- [ ] `app/AGENTS.md` § 播放與 § Lint 改寫（拿掉「等 M2」那句）；`.trellis/spec/app/playback/index.md` 的實機驗證段改成指向 skill（M1 follow-up 6）。
- 測試：
  - 既有 `playback_controller_test.dart` 不改期望全綠（證明行為不變）；
  - `playback_event_router_test.dart` 逐一餵事件；
  - lint 的報與不報案例：同前綴的 `backends_helpers.dart` 也報；改名、註解裡提到不報。
- 實測：Windows 與 Android 各跑一次真後端契約（`app/AGENTS.md:18`）；從搜尋頁播兩首確認交接（重播）。
- 依賴：0。模型：opus。

## 2. 網路狀態與離線呈現（design §5）

- [ ] 平台層 `lib/platform/connectivity/`（`connectivity_plus`），宣告 `networkInterfaces`；`platform_test.dart` 每平台一個斷言。
- [ ] `lib/core/network/network_status.dart`：狀態機。`SourceHttpClient` 回報結果（PR 3 的媒體 client 接同一個入口）。
- [ ] `appLifecycleProvider`（`lib/app/`）；回到 `resumed` 時重查介面。
- [ ] 外殼的全域離線提示；共用的離線空狀態元件；搜尋頁的 `noInterface`／`unreachable` 行為（design §5.4）。
- 測試：
  - 狀態轉換表逐列；`fakeAsync` 下斷言沒有待執行的計時器；
  - 搜尋頁在兩種離線狀態下各一個 widget 測試（兩者都照送，失敗時才顯示離線空狀態；擁有者決定 9）；
  - 全域提示在離線時出現、回到 `online` 時消失；
  - guideline 測試加離線狀態。
- 實測：
  - Android 模擬器切飛航模式 → 全域提示與搜尋頁的離線狀態 → 關掉飛航模式恢復；
  - Windows 停用網路介面再啟用。
  - 模式：重播。
- 依賴：0。模型：opus。

## 3. 媒體 client（design §4.1，決定 1）

- [ ] `lib/core/network/media_http_client.dart`：
  - 每插件一個，不帶憑證、只有媒體標頭；
  - 每跳 `allowedHosts`、最多 5 跳；
  - `maxBytes`；連線 10、間隔 15、總計 30 秒逾時；
  - 錯誤對應；
  - 寫網路紀錄（加 `client` 欄位，`SourceHttpClient` 同步）；
  - 回報網路狀態。
- [ ] `PluginRegistry` 在插件載入時與 `SourceHttpClient` 一起建立。
- 測試（`test/core/network/`，假 adapter）：
  - 請求沒有 `Cookie`／`Authorization`（ADR 0012 §如何確認）；
  - 轉址出網域、`http`、第 6 跳失敗；
  - `Content-Length` 過大與串流中超過上限都中止，且不留暫存檔；
  - 逾時是 `NetworkError`；
  - `network log` 群組的欄位比對（含 `client`）；
  - 結果進網路狀態。
- 實測：沒有使用者看得到的改動（PR 4 才接上畫面），不做。
- 依賴：2。模型：opus。

## 4. 統一快取庫與封面磁碟快取（design §4.2–§4.4）

- [ ] 平台層 `lib/platform/cache_directory/`；宣告快取上限預設與記憶體 `ImageCache` 大小（Android 128 MB、100 張／50 MB；Windows 256 MB、200 張／80 MB）；`main()` 套用 `ImageCache`。
- [ ] `lib/data/cache/`：
  - `cache.db`（第二個 drift 資料庫、快照在 `drift_schemas/cache_database/`、自己的 `schema_test`、開不起來就重建、升級清空）；
  - `CacheStore`（寫入時淘汰、用量、清除、`removePlugin`）。
- [ ] `FmpImageCacheManager`：`flutter_cache_manager` 的 `CacheInfoRepository`、`FileSystem`、`FileService` 三個轉接。
- [ ] `artworkCacheManagerProvider(pluginId)`（`lib/plugins/plugin_artwork.dart`）。
- [ ] `ArtworkImage` 改用 `CachedNetworkImage`，多收 `pluginId`。
- [ ] `fmp_layer_imports`：
  - `flutter_cache_manager` → `lib/data/cache`；`cached_network_image` → `lib/ui/artwork`；
  - `cache_directory` 的限定匯入者。
- [ ] `app/AGENTS.md` § 介面的封面段、§ 網路的媒體 client 段改寫。
- 測試（ADR 0016 §如何確認）：
  - 跨類別淘汰到上限以下；
  - 檔案被刪視為未命中（含 `CacheStore` 不回傳不存在的檔）；
  - 清除後用量為 0；
  - 移除插件只刪它的項目；
  - 損壞的 `cache.db` 開啟時重建；
  - cache manager 的 `get`／`put`／`touched` 對到 `last_access`；
  - `ArtworkImage` 以假 cache manager 的 widget 測試；
  - lint 案例。
- 建置檢查：`flutter build apk --flavor dev --debug` 後以 `zipalign -c -P 16` 確認新增的原生庫（`sqflite` 經 `flutter_cache_manager` 帶入）仍是 16KB 對齊（design §8.3）。
- 實測（真實連線：改動是網路與快取，ADR 0027 §決定 2）：
  - 兩平台搜尋 B 站一次，封面顯示；
  - 重啟 App 後同一頁的封面不再發請求（網路紀錄沒有 `client: media` 的新紀錄）；
  - 檢查 `fmp_cache/` 下有檔案與 `cache.db`。
- 依賴：3。模型：opus。

## 5. 「網路」設定組：快取上限、用量、清除（design §3.3、§4.4、§9.8）

- [ ] `network_settings` 表（schema bump）、repository、Notifier（空＝平台預設）。
- [ ] 設定頁改成分組，expanded 以上 list-detail；「網路」組：快取上限、封面用量、「清除快取」（含 `ImageCache`）。
- [ ] 改上限時淘汰一次。
- 測試：
  - `.trellis/spec/app/settings/index.md` 第 6 步的五種；
  - migration 三種；
  - 清除後用量顯示 0；
  - 設定頁在 400／1000 寬的 guideline；
  - list-detail 的版面測試。
- 實測：兩平台改上限、看用量、清除後封面重新下載（真實連線，延續 PR 4 的最少操作）。
- 依賴：4。模型：sonnet。

## 6. 啟動維護清單與 log 保留 7 天（design §6）

- [ ] `lib/app/startup_maintenance.dart`：有序清單、第一幀後跑一次、各項失敗不影響下一項。
- [ ] 第一項：`logs/` 最後修改超過 7 天的 `fmp*.jsonl` 刪除（`lib/core/logging/` 提供函式）。
- 測試：
  - 順序、只跑一次、在第一幀之後（widget 測試以 `pump` 確認 `runApp` 當下未跑）；
  - 一項丟錯時下一項照跑且錯誤進錯誤歷史；
  - 超過 7 天的檔被刪、未滿 7 天的保留、目前的 `fmp.jsonl` 不刪，大小與天數同時作用（ADR 0025 §如何確認；`File.setLastModified` 造時間）。
- 實測：Windows 在 dev 資料目錄放一個改過修改時間的舊 log 檔，啟動後被刪（log 有一筆維護紀錄）；Android 以 `run-as` 做同樣的事。
- 依賴：0。模型：sonnet。

## 7. 串流網址快取（design §7.4）

- [ ] `StreamResolver` 內的記憶體快取：
  - 鍵＝曲目鍵＋音質＋格式偏好（PR 8 之前偏好固定），LRU 64；
  - `expiresAt − 5 分鐘`，空值 5 分鐘；
  - 播放失敗作廢；進行中的請求共用。
- [ ] `ResolvedStream.expiryMargin` 30 秒改成同一個 5 分鐘常數；控制器的前瞻刷新與交接檢查跟著改。
- 測試（ADR 0016 §如何確認）：
  - 安全邊界、`expiresAt` 為空、作廢、上限 64 的淘汰；
  - **預取後播放只解析一次**；
  - 前瞻解析慢於目前這首結束時只解析一次（M1 follow-up 4 的後半）；
  - `expiry` 群組改成 5 分鐘。
- 實測：Windows 與 Android 從搜尋頁連播兩首，log 的 `resolveStream` 次數＝曲目數（重播）。
- 依賴：1。模型：opus。

## 8. 音質與格式偏好、`expiresAt` 契約（design §7.4、§10，決定 4）

- [ ] `playback_settings` 表已在 PR 10 建好（design §3.3 全部欄位）；這個 PR 只在 Notifier 加音質與格式偏好的 setter。
- [ ] 設定頁「播放」組的兩列。
- [ ] `StreamRequest.quality`（可選）、依格式偏好重排 `formats`；`fmp-plugin.d.ts`、`sourceDtoShapes`。
- [ ] 契約執行器支援 `checks.json` 的 `expiresAtPattern`；`FmpChecks` 型別。
- [ ] `_bilibiliSigned` 拿掉 `deadline`；`app/` 內既有 fixture 照舊通過「再遮一次不變」。
- [ ] **fmp-plugins PR**：
  - B 站讀 `quality`；
  - `checks.json` 加 `quality` 與 `expiresAtPattern`；
  - 重錄 `resolveStream` fixture（真實連線，一個案例）；
  - 人工逐檔確認沒有憑證。
- [ ] ADR 0014 §決定 5 的一行補充。
- 測試：
  - settings 五種與 migration 三種；
  - 快取鍵含偏好（換偏好後重新解析）；
  - `formats` 的順序；
  - `type_definitions_test.dart`；
  - `contract_runner_test.dart` 的 `expiresAtPattern`（不一致會紅、改無關欄位不紅）；
  - `fixture_scan_test.dart`。
- 實測：兩平台把音質切到「低」播一首 B 站，`Opening stream` 的 `bitrate` 是最低層（真實連線：改動是插件）。
- 依賴：7。模型：opus。

## 9. 完整 `QueueModel`（design §7.2）

- [ ] 純 Dart。`QueueEntry(TrackInfo)`、`TrackInfo`（`lib/domain/`）與 `TrackSummary` 的轉換。
- [ ] 規則：
  - 模式 `queue`、`temporary`；
  - 循環三種；
  - 位置式隨機（開、關、拖曳、下一首播放、附加、跳到、一輪結束）；
  - 上一首 3 秒；
  - 10,000 上限整批拒絕；
  - 移除、清空；
  - 臨時播放的快照與回到佇列。
- 測試（ADR 0018 §如何確認的 `QueueModel` 部分，Mix 修剪除外）：
  - 隨機位置語意；
  - 拖進已播位置本輪不再播；
  - 連續「下一首播放」依加入順序；
  - 臨時播放保留最早快照；
  - 臨時播放中單曲循環仍回到快照；
  - 上限（剛好 10,000 可、10,001 整批拒絕）；
  - 以固定種子的隨機操作序列比對不變式（每個位置在一輪內恰好播一次）。
- 實測：沒有使用者看得到的改動，不做。
- 依賴：1。模型：opus。

## 10. 控制器的佇列操作、臨時播放與入口（design §7.2、§7.3，D1）

- [ ] 控制器 API：
  - `playTemporary`、`addToQueue`、`playNext`、`removeAt`、`move`、`jumpTo`、`clear`；
  - `setLoopMode`、`setShuffle`；
  - 上一首 3 秒；
  - 單曲循環以同一份解析結果當前瞻（design §7.6 末段）；
  - `events` stream 的 `QueueFull`。
- [ ] 刪 `queueTracksProvider`；播放列改讀 `QueueEntry` 的顯示資料。
- [ ] 搜尋頁：點一下＝臨時播放；選單「播放、下一首播放、加入佇列」（右鍵、長按、「⋯」）。
- [ ] `playback_settings` 的「記住播放位置」「臨時播放回佇列倒退秒數」接上 setter 與設定頁兩列。
- [ ] 改寫 `search_page_test.dart` 的 `tapping a result plays the whole list from it` 與 `install_search_play_test.dart` 的期望。
- 測試：
  - 臨時播放結束、按下一首、按上一首都回到佇列，倒退秒數與「記住播放位置」的四種組合，原本暫停時只載入不播；
  - 單曲循環不重解析；
  - 加入超過上限發 `QueueFull` 並由外殼提示；
  - 搜尋頁三個選單項目。
- 實測：
  - 兩平台：搜尋→點 A（臨時播放）→ 選單把 B、C 加入佇列 → 播放列下一首；
  - 回到佇列時位置與倒退正確；
  - 單曲循環兩圈；
  - 模式：重播。
- 依賴：9。模型：opus。

## 11. 後端契約補齊：前瞻失敗、HTTP 狀態碼（design §7.6，M1 follow-up 4）

- [ ] 兩個後端：前瞻開不起來時，目前這首照常播完並發 `SourceEnded`，失敗以前瞻的 id 回報；Windows 不卡在 Playing。
- [ ] `SourceFailed.httpStatus`：`backend_rules.dart` 從 ExoPlayer 例外與 mpv log 行解析。
- [ ] 控制器把前瞻失敗當成下一首的開流失敗（作廢快取，到那首時重解析）。
- 測試：
  - 契約的兩個新案例（假後端在 `flutter test`）；
  - 狀態碼解析以錄下的兩種錯誤文字做單元測試（含不含狀態碼的反例）。
- 實測：
  - Windows、Android 各跑真後端契約（`app/AGENTS.md:18`）；
  - 測試插件加一個關鍵字讓第二首的網址開不起來，連播時第一首完整播完、第二首走恢復（重播）。
- 依賴：1。模型：opus。

## 12. `RecoveryPolicy` 完成與播放提示（design §5.3、§7.5、§7.9，M1 follow-up 1、2、9）

- [ ] `decideRecovery`：
  - 加網路狀態、「跳過試聽片段」、重解析次數三個輸入；
  - 加 `WaitForNetwork`、`PlayAsPreview`、`ReResolve` 三種結論；
  - 10 秒歸零；
  - 緩衝飢餓 15 秒；
  - HTTP 403／404／410 的重解析與對應；沒有狀態碼的開流失敗（Android 一律）也先重解析一次（擁有者 2026-10-06，design §7.5 新列）；
  - 跳過的去處依模式。
- [ ] `Retrying.delay` 可空（等網路）；`Unavailable.reason` 可空；ADR 0013 一行更正。
- [ ] `StreamResult.previewOnly`（可選）；測試插件加會回傳它的關鍵字；`d.ts`、shapes。
- [ ] 控制器的 `events`：`TrackSkipped`、`PlaybackStopped`、`PreviewPlaying`；外殼 listener 轉成 `Toaster`；M1 的 `Failed` 提示併入。
- [ ] 「跳過試聽片段」的設定頁一列；播放列的「重試中／等待網路連線／試聽」標示。
- 測試（ADR 0018 §如何確認的 `RecoveryPolicy` 部分）：
  - 每類錯誤的處理；
  - 離線暫停計數、恢復後立刻重試；
  - 正常播放 10 秒歸零（以位置前進，沒有計時器）；
  - 連續跳過停止並提示一次；
  - `temporary` 中跳過回到佇列；
  - 403 先重解析；沒有狀態碼的開流失敗也先重解析；
  - 試聽兩種設定；
  - 離線期間沒有提示；
  - `app_shell_test.dart` 的提示案例。
- 實測：
  - 兩平台：測試插件 `fail` 關鍵字的提示；
  - 播放中切斷網路 → 顯示等待網路 → 恢復後自動續播；
  - 試聽關鍵字在設定開與關各一次（重播）。
- 依賴：2、7、10、11。模型：opus。

## 13. E19：音量、速度、輸出裝置與 Android 音訊中斷（design §7.6，決定 3）

- [ ] `AudioBackend.setVolume`、`setSpeed`、`outputDevices`；`PlaybackSupport.outputDeviceSelection`（Windows 真、Android 假），組裝點的 `assert`。
- [ ] `JustAudioBackend`：
  - `handleInterruptions: false`；
  - 自己聽 `audio_session`：duck 內部減半；中斷與拔耳機發事件，由控制器暫停或續播；
  - `audio_session` 加為直接依賴，擁有者 `lib/playback/backends`。
- [ ] `MediaKitBackend`：音量、速度、裝置清單與選擇；`ao` 錯誤 → `OutputDeviceFailed` → 暫停並提示。
- [ ] 控制器 API：`setVolume`、`toggleMute`、`setSpeed`、`selectOutputDevice`。
- [ ] 偏好裝置存 `playback_settings`，裝置清單第一次就緒時套用一次。
- 測試：
  - 契約的音量、速度案例（開流前設定、換來源與交接後維持、速度夾取）；
  - 控制器的中斷事件 → 暫停與續播（只有暫停類中斷結束才續播）；
  - 拔耳機只暫停；
  - 宣告與 `outputDevices` 一致（`platform_test.dart`）；
  - 偏好裝置不在清單時用預設且不清掉偏好。
- 實測：
  - Windows：調音量、速度 1.5 跨兩首仍是 1.5、切換輸出裝置（有兩個裝置時；只有一個時記錄只驗了 `auto`）；
  - Android：調音量；以 `adb shell cmd media_session dispatch` 或另一個 App 播放觸發焦點中斷，確認暫停與續播；
  - 兩平台跑真後端契約；
  - 模式：重播。
- 依賴：1、8。模型：opus。

## 14. 佇列持久化與啟動恢復（design §3.1、§3.2、§7.7）

- [ ] `tracks`、`queue_entries`、`player_state` 表（schema bump）、repository（差量寫入、外鍵 `RESTRICT`）。
- [ ] `queue_store.dart`：
  - 佇列操作當下寫入；
  - 播放中每 10 秒；
  - 暫停、seek、`hidden`／`paused` 時寫位置；
  - 音量；
  - 臨時播放期間不覆寫快照。
- [ ] 啟動恢復：`Idle` 帶佇列與位置、按播放才解析、恢復後第一次不記歷史；「重啟恢復時倒退秒數」的 setter 與設定頁一列。
- [ ] 孤兒曲目登記到啟動維護清單。
- 測試：
  - repository 以固定種子的隨機操作序列比對 `QueueModel`；
  - 一萬筆整份取代的耗時上限（記錄數字，超過 500 ms 在 PR 描述說明）；
  - `RESTRICT` 反例；
  - migration 三種；
  - 恢復的四種組合（記住位置開關 × 倒退秒數）；
  - 臨時播放中重啟回到快照；
  - 孤兒清理只刪無人參照的列。
- 實測：
  - 兩平台：建一個五首的佇列、開隨機與循環、播到第三首中間 → 關掉 App → 重開，佇列、隨機順序、循環、音量、位置都回來，而且沒有發解析請求（log）→ 按播放從倒退後的位置開始；
  - 模式：重播。
- 依賴：6、10、13。模型：opus。

## 15. 播放歷史與「歷史」頁（design §7.8、§9.7，決定 5）

- [ ] `play_history` 表（schema bump）、repository（分頁查詢、裁切、刪一筆、全部清除）。
- [ ] 控制器在「開始一首」第一次 `ready` 時寫入。
- [ ] 「播放歷史保留筆數」的 setter 與設定頁一列（改小時當下裁切）。
- [ ] 外殼加「歷史」導覽項（搜尋｜歷史｜設定）。
- [ ] 歷史頁：日分組、臨時播放、選單、清除全部（確認框）。
- 測試：
  - 寫入時機：換歌、前瞻接上、單曲循環每圈各一筆；重試、換候選、啟動恢復、回到佇列不寫（ADR 0018 §如何確認「單曲循環每圈一筆歷史且不重解析」）；
  - 保留筆數的裁切；
  - 寫入失敗不影響播放；
  - migration 三種；
  - `navigation per window class` 三個導覽項；
  - 歷史頁的 guideline 與離線案例。
- 實測：兩平台播三首（其中一首單曲循環兩圈）→ 歷史頁有四筆、日分組正確 → 點一筆臨時播放 → 清除全部（重播）。
- 依賴：10、14。模型：opus。

## 16a. 系統媒體控制：Android 與返回鍵（design §8.1–§8.3、§9.1，決定 7）

- [ ] `lib/platform/media_controls/`：介面、Android 實作（`audio_service` 0.18.19），宣告 `mediaControls`（`supportsSeek: true`）；初始化失敗時宣告改為沒有。
- [ ] `NowPlayingPublisher`（`lib/playback/`）：
  - 只在改變時推、依序；
  - 按鈕依能力；
  - 封面經 `artworkCacheManagerProvider` 拿本機檔交 `file://`。
- [ ] `AndroidManifest.xml`：三個權限、`AudioService`、`MediaButtonReceiver`。
- [ ] `MainActivity` 繼承 `AudioServiceActivity`：
  - 覆寫 `provideFlutterEngine`（帶 `dart_entrypoint_args`）；
  - 覆寫 `popSystemNavigator`（`moveTaskToBack(true)`）。
- [ ] 外殼的 `PopScope`：不在第一個分頁時回到第一個分頁。
- [ ] `verify-on-device` 的 Android 參考若需要就改；`app/AGENTS.md` § App 身分或 § 平台層寫明兩個覆寫的理由。
- 測試：
  - `NowPlayingPublisher` 去重與排隊（假平台實作）；
  - 系統指令經控制器；
  - `android_manifest_test.dart`（XML 解析：權限、服務、receiver）；
  - `platform_test.dart`；
  - 外殼返回的三種情況（widget 測試以 `handlePopRoute` 模擬）。
- 實測（Android 模擬器）：
  - 以 `--fmp-dev-plugin` 啟動，確認測試插件仍裝得上（`provideFlutterEngine` 覆寫有效）；
  - 播放中下拉通知：曲名、封面、上一首／播放／下一首、進度條可拖；
  - 鎖定畫面控制；
  - 返回鍵：在「歷史」分頁按返回 → 回到「搜尋」→ 再按 → App 退到背景、音樂繼續 → 從最近使用回來，狀態不變；
  - 播放頁開著時（PR 18a 之後再驗一次）按返回只關播放頁；
  - `dumpsys media_session` 有 FMP 的工作階段；
  - 跑 `integration_test/audio_backend_contract_test.dart` 確認整合測試在 `AudioServiceActivity` 下照常執行。
  - Windows：沒有改動（只跑整合測試確認不受影響）。
  - 模式：重播。
- 依賴：4、10。模型：opus。

## 16b. 系統媒體控制：Windows SMTC（design §8.4）

- [x] `media_controls_windows.dart`（`smtc_windows` 1.1.0），宣告 `supportsSeek: false`。
- [x] 封面先試快取檔的 `file:///`，不行就交 `https` 原網址；交出前 `Uri.tryParse` 檢查。
- [x] `app/AGENTS.md` § 驗證：Windows 建置需要 `rustup`。
- [x] CI 的 Windows 建置與整合測試確認仍綠（runner 內建 Rust）；缺時才在 `ci.yml` 加步驟。
- 測試：`platform_test.dart`；Windows 實作的轉換函式（`NowPlaying` → SMTC 的 metadata 與 timeline、按鈕）單元測試。
- 實測（Windows）：
  - 播放中按鍵盤媒體鍵（播放／暫停、下一首）；
  - 音量浮層的媒體卡片有曲名、封面；
  - 暫停與恢復時卡片同步；
  - 記錄 `file:///` 封面是否可用，結論寫進 `app/AGENTS.md`。
  - 模式：重播（封面要真實 B 站時另做一次最少操作）。
- 依賴：16a。模型：opus。

## 17. 播放列三段與快捷鍵全表（design §9.2、§9.5）

- [ ] 播放列三段的完整控制項：
  - 隨機、循環；
  - 輸出裝置（依宣告）；
  - 音量滑桿／圖示＋彈出滑桿；
  - 靜音；
  - 「⋯」；
  - 點空白處開播放頁（PR 18a 前先接到一個佔位路由，或與 18a 同時合併時直接接）。
- [ ] `PlaybackShortcuts` 抽出共用；加 Ctrl+↑／↓、Ctrl+S、Ctrl+R、Esc、Ctrl+L／Q（播放頁的部分在 18a 接）；輸入框規則（導覽類有效、其餘讓出）。
- [ ] tooltip 附按鍵（翻譯檔 `*Tooltip`），三語言。
- 測試：
  - `controls per width` 的邊界與 Android 沒有輸出裝置鈕；
  - 曲名 ≥ 160dp；
  - golden 三段（`--update-goldens` 後人工看圖）；
  - `shortcuts` 群組的新鍵與輸入框案例；
  - guideline。
- 實測：
  - Windows：每個快捷鍵各按一次（含在搜尋框內按 Ctrl+S 不切隨機、Esc 有效）；
  - 拖寬視窗經過 600、840 兩個邊界，看控制項換段；
  - Android：三段在直向與橫向；
  - 模式：重播。
- 依賴：10、13。模型：opus。

## 18a. 播放頁 B（design §9.3、§9.6）

- [x] 全螢幕路由；外殼得知它在最上層時提示貼底部安全區。
- [x] 三種版面（手機與 medium、B 兩欄、extraLarge 三欄）；左欄控制；「⋯」的速度與右側面板切換。
- [x] 歌詞空狀態；`TrackDetails`；毛玻璃（高對比時不透明）。
- [x] `layout_state` 表（schema bump，含右側面板的兩欄）；分頁記憶。
- [x] 頁內 F6 區、Esc 關閉、Ctrl+L／Q。
- [x] ADR 0024 §決定 1 的一行更正。
- 測試：
  - guideline（淺色、深色 × 最淺、最深的測試封面）；
  - golden 1000、1400、1800；
  - Esc、F6、Ctrl+L／Q；
  - 分頁記憶（extraLarge 記住歌詞時的行為）；
  - `toast_layering_test.dart` 加播放頁；
  - migration 三種。
- 實測：
  - Windows：從播放列開播放頁、三種寬度、Esc 關閉、速度選單、在播放頁上觸發一個提示（`fail` 關鍵字）確認提示可見且貼底；
  - Android：手機版的封面與歌詞切換、返回鍵只關播放頁（補 16a 的那一項）；
  - 兩平台跑 `toast_layering_test.dart`；
  - 模式：重播。
- 依賴：4、17。模型：opus。

## 18b. 佇列分頁與底部面板（design §7.3）

- [x] 播放頁的佇列分頁、手機與 medium 的底部面板：
  - 目前這首標示、點選跳到；
  - 拖曳把手重排、移除、下一首播放；
  - 清空（確認框）；
  - 隨機時的說明文字。
- [x] 「切歌時捲到目前歌曲」的 setter 與設定頁一列。
- [x] 一萬筆時以 `ListView.builder`／`ReorderableListView.builder` 不一次建出。
- 測試：
  - 各動作經控制器；
  - 隨機開啟時拖曳後的「接下來」與 `QueueModel` 一致；
  - 自動捲動開關；
  - guideline。
- 實測：
  - 兩平台：在佇列分頁或底部面板拖曳、移除、清空、點選跳到；
  - 開隨機後拖曳，確認接下來播的與畫面一致；
  - Windows 以鍵盤操作佇列（Tab、Enter）；
  - 模式：重播。
- 依賴：10、18a。模型：opus。

## 19. 右側「正在播放」面板（design §9.4，決定 6）

- [ ] 外殼在 expanded 以上的面板：
  - 展開、收起（標題列與播放頁「⋯」）；
  - 拖曳把手（鍵盤左右鍵也可）；
  - 寬度 320–視窗 × 0.4，預設 412、extraLarge 480；
  - 拖曳結束寫 `layout_state`；
  - 內容是 `TrackDetails`。
- [ ] 播放列橫跨內容與面板，分段依那個寬度。
- 測試：
  - 面板只在 ≥ 840 出現；
  - 收起與寬度記憶；
  - 夾取（資料庫裡的壞值）；
  - 開關面板不改變播放列的分段；
  - guideline 與 golden（1000、1800 的外殼）。
- 實測：
  - Windows：拖寬、收起、重啟後維持；
  - 縮到 < 840 面板消失、放大回來仍是記住的寬度；
  - Android（平板尺寸的模擬器或橫向大螢幕）至少看一次 expanded；
  - 模式：重播。
- 依賴：18a。模型：opus。

## 留下的後續

PR 1 留下的：

- [ ] `fmp_layer_imports` 不正規化含 `..` 的 package URI（`package:fmp/playback/../…`），既有限制，這次的 `restrictedImports` 一樣抓不到。
- [ ] `audioBackendProvider` 不經 import 也能 `ref.watch` 拿到後端實例；lint 只管 import，這半條沒有閘門（`app/AGENTS.md` § 播放已註明），review 時看。

PR 2 留下的（沒有 repro，不修）：

- [ ] 啟動時 `NetworkStatusNotifier.build()` 的 `check()` 還沒回來就先來一筆介面變化，晚到的舊結果可能蓋掉新狀態。
- [ ] 離線時搜尋失敗會同時出現錯誤 toast 與 `OfflineMessage`；ADR 不禁止，擁有者覺得重複再決定。
- [ ] Windows 停用網路卡的實機驗證沒做（會切斷驗證用的工作階段）；M2 驗收的離線步驟補做。

PR 3 留下的：

- [ ] 同一個 `destination` 同時下載兩次會共用 `.part`（只有 dartdoc 寫明）；PR 4 接 `flutter_cache_manager` 時確認它不會同時對同一個檔下載兩次。
- [ ] dart:io 預設解壓 gzip：單一網路塊解壓時可能短暫佔用大量記憶體，磁碟大小仍守得住；沒有 repro，不修。
- [ ] 總計逾時在收到第一塊之後的情況沒有測試（fakeAsync 裡跑不了檔案 I/O），走的是和取消同一條路。

PR 4 留下的：

- [ ] B 站插件回傳原圖網址（實測每張最大約 885 KB、2–5 秒）：應由插件回傳多種尺寸（hdslb 的 `@160w` 這類後綴），宿主的 `pickArtwork` 已會挑；在 fmp-plugins 處理（PR 8 一起，或另開 issue）。宿主不組 B 站專用參數。
- [x] ~~`flutter_cache_manager` 背景更新最後存取時間造成的幽靈列~~：第二輪審查（第一輪兩次藍屏後重審）寫出重現測試並修好（寫索引與清除、淘汰同一條隊伍，寫前先看檔案）；同輪另修索引大小取磁碟實際大小、`files/` 被系統刪掉後 `clear()` 丟例外。
- [ ] 第二次 `_open` 也失敗的那一支沒有測試（造不出清空後仍開不起來的目錄）。
- [x] PR 5「清除快取」要另外清 Flutter 的 `ImageCache`；`CacheStore.clear()` 不碰它。
- [ ] 本機 Windows 在 `make-migrations` 時把 checkout 的快照當成已存在且不同；暫時把快照轉成 LF 再跑（寫在 data spec）。

PR 5 留下的：

- [ ] 「快取上限」選過之後回不到「（預設）」：UI 沒有「使用預設」選項，`setCacheLimit(null)` 只有測試在呼叫。平台預設固定時與選同一個值沒有差別；之後若改預設才會分歧。等擁有者決定是否加。
- [ ] 快取庫開不起來時按「清除快取」只清了記憶體裡的圖，仍顯示「已清除快取」。
- [ ] PR 16a：窄版設定頁組內的 `PopScope`（只在設定頁顯示時攔返回鍵）要併進外殼的返回鍵分層（決定 7）。目前在根路由按返回會結束 Activity，回來時設定頁回到分組清單；16a 改成退到背景後，狀態會保留。
- [ ] 「調低上限時用量當場下降」在實機難造（要先有超過 128 MB 的封面，違反真實連線最少操作），只有 widget 測試。

PR 7 留下的：

- [ ] 失敗事件與換歌同時發生、事件因代數不同被丟掉時，壞網址留在快取，到下次播放再失敗一次才作廢（不會一直重播）。
- [ ] 佇列裡同一首連著兩次時，前瞻與目前這首共用同一個解析結果；目前這首失敗作廢後，前瞻仍持有壞網址，接著被跳到時會再失敗一次再恢復。條件很窄。
- [ ] 已關閉的舊插件實例被最多 64 個快取鍵留住，到 LRU 淘汰為止。
- [ ] 「插件更新後重新解析」只有單元測試；M3 有插件頁之後才有實機入口。

PR 9 留下的（PR 10 接控制器時處理）：

- [x] 前瞻以位置索引對應；佇列被拖曳、插入或移除後，已準備的前瞻可能指到別首，控制器要在佇列編輯後重新準備前瞻。
- [x] 臨時播放中 `QueueModel.next` 回傳的是快照那首；若照前瞻交接，會從頭播而不是從 `snapshot.resumeAt(...)`。臨時播放中控制器應跳過前瞻或另外處理。
- [x] 臨時播放中而佇列是空的時，`QueueState.hasNext` 是 true、`QueueModel.next` 是 null：播放列的下一首按鈕可按卻沒反應。
- [x] 空佇列進入臨時播放，快照記「沒在播」；之後在臨時播放中附加或下一首播放，回到佇列時不自動播。對照 design §7.2「佇列原本是空的時停在 `Idle`」確認是否要的行為。
- [x] 單曲循環的重播（模型照循環關走上下一首）要由控制器在一首播完時接上。
- 已定下、PR 10 不必再問：連續「下一首播放」在換歌、拖曳、取代、開隨機後從目前這首之後重新排（ADR 0018 採用的 Namida `insertAfterLatest`）；目前這首被拖曳時新舊位置交換排序（寫在 `app/AGENTS.md`）。

PR 10 留下的：

- PR 9 留下的五件都在 PR 10 處理完（前瞻重新準備、臨時播放不交接、空佇列下一首、空佇列進入臨時播放、單曲循環重播）。
- [ ] `RepeatTrack`（單曲循環時前瞻沒來得及接上）只有路由器測試；控制器層造不出「前瞻來不及」，重播一律從網址快取拿。
- [x] PR 12：單曲循環時換候選之後，前瞻會再開一次開不起來的第一候選，要再走一次換候選才播得起來。
- [x] PR 17：隨機、循環的 tooltip 補上 Ctrl+S、Ctrl+R。
- [x] PR 14：做持久化後改「記住播放位置」的說明（目前只寫臨時播放）。
- [x] PR 18a：compact（手機直向）的播放列沒有隨機、循環入口，要到播放頁 B 才有。
- [ ] `playback_providers.dart` 為了 `PlaybackSettings.empty` import 資料層型別；可改由設定層提供預設值（沒有違反 lint）。
- [x] 搜尋結果「⋯」的語意標籤重複成「更多選項. 更多選項」（tooltip 與 label 同字），Windows MSAA 看得到。
- [ ] 既有、不是 PR 10 造成：Android 橫向（約 411 dp 高）叫出鍵盤時，側邊導覽列與搜尋頁的 Column 底部溢出 3.8–9.9 px（佇列空、沒有播放列時也會；這兩處 PR 10 沒改）。實機 log 記成 `Uncaught Flutter error`。

PR 11 留下的：

- [ ] **Android 上時長未知的前瞻永遠接不上**：just_audio 後端等事件帶時長才確認交接；ExoPlayer 給不出時長的串流（沒有長度資訊）會照樣出聲，但 App 停在上一首、收不到結束。不能改看位置前進（just_audio `ready` 時以時鐘推算位置）。目前的音源都有時長；M3 加 YouTube／直播類插件前要實機找別的載入訊號。
- [ ] 待確認交接期間 `setNext` 換掉前瞻的路徑沒有自動測試（時間點從外面造不出），`app/AGENTS.md` 註明 review 時看。
- [ ] 被換掉的前瞻晚一點才報失敗時 session 不理它，壞網址留在快取，下次輪到再失敗一次才作廢。
- [ ] just_audio 在 Dart 端就失敗的前瞻（asset 不存在）留在 Dart 清單、不在原生清單；之後改佇列移除它可能讓清單修改失敗，只記 warning、那首沒有前瞻。
- [ ] mpv 的 ffmpeg log 只給行程裡第一個活著的 mpv 實例；App 只有一個後端沒事，契約的 403 案例斷言自己是第一個建的後端。

PR 12 留下的：

- [ ] 「等待網路」在 Windows 沒有實機驗（要停用網卡），與 PR 2 留下的那條一起在 M2 驗收補。
- [ ] 在緩衝中按暫停，狀態仍是 `Buffering`（路由器只看後端回報的階段），15 秒計時器照樣觸發、重解析並以暫停狀態重開；同一首第二次就跳過。沒有 repro 測試。
- [ ] 一首一直停在 `Loading`、永遠載入不好時，緩衝飢餓計時不管（design 只寫 `Buffering`）。
- [ ] 連續停下的警告不寫最後一首的具體原因。
- [ ] 組裝點 `playback_providers.dart` 把網路狀態與「跳過試聽片段」交給控制器的幾行沒有測試守（`app/AGENTS.md` 已寫明）。
- [ ] 佇列第二首的第一次解析失敗會被前瞻吃掉（錯誤歷史多一筆 `Look-ahead resolution failed`），輪到它時才重新解析。
- [x] PR 18a：播放頁的「試聽」標示。
- [ ] log 小瑕疵：`Temporary play ended; the queue stays idle` 在佇列空時 `track` 欄位是字串 `"null"`（`playback_controller.dart` 的 `'${track?.key}'`）。

PR 8 留下的：

- [ ] 改音質或格式偏好時，已準備好的前瞻不重新解析，下一首可能還是舊偏好（`app/AGENTS.md` 寫明沒有閘門）。
- [ ] B 站的音質選擇沒有自動測試（契約每個能力一條案例）；審查用 node 離線驗過各種軌數。
- [ ] `expiresAtPattern` 取網址裡先出現的期限，插件先找 `deadline` 再找 `hdnts=exp=`；若以後重錄時某個 Akamai 網址同時有兩者、`hdnts` 在前且時間不同，錄製會拒絕寫檔。
- [ ] `fmp-plugin.d.ts` 沒有規定候選的備援順序（只是 B 站的決定）；M3 寫網易插件時再看要不要成為插件規範。
- [ ] B 站插件 manifest 仍是 0.1.0（還沒有發佈版本）。

PR 13 留下的：

- [x] PR 17：播放列接音量、靜音、輸出裝置；控制器要對外提供裝置清單、目前裝置與音量的 stream。裝置清單只列 Windows 的音訊裝置（擁有者 2026-10-07：不列 mpv 的 `openal` 這類內部輸出，「系統預設」照常有）。
- [x] PR 18a：速度選單（需要速度的 getter 或 stream）。
- [x] PR 14：持久化音量與靜音（靜音與音量分開記，擁有者 2026-10-07 確認）。
- [ ] 裝置失敗前先到的提前結束，在錯誤歷史留一筆 `Stream ended early`。
- [ ] `JustAudioBackend` 接 audio_session、`MediaKitBackend` 接 log 的幾行沒有自動閘門（`flutter test` 裡建不起來）。
- [ ] duck 在 Android 8 以上因系統自動 duck 幾乎不會觸發。
- [x] PR 17：記住的輸出裝置失效後 mpv 仍被強制指定它，按播放會再失敗；決定失敗時要不要自動退回系統預設。
- [ ] `_onOutputDevices` 裡 `_session.selectOutputDevice` 丟錯會變成未捕捉的非同步錯誤（全域 handler 記 error），影響小。
- [ ] 後端的 `volume`、`speed` getter 與 `OutputDevices.selected` 只有契約測試在讀（觀察真引擎狀態的唯一方式，保留）；控制器的 `volume`、`muted` 等 PR 17 的 UI 使用。

PR 14 留下的：

- [x] PR 17：恢復後還沒按播放時，播放列的進度顯示 0:00，不是恢復的位置（按播放後才跳過去）；兩平台實機都看到。
- [ ] 在 `attach` 訂閱之前就已開始播放時，10 秒存檔計時器要等下一次狀態變化才開（時間窗只有幾毫秒，沒有穩定的 repro）。
- [x] PR 15：`play_history` 參照 `tracks` 時照 `queue_entries.track_key` 建索引，否則孤兒清理會慢。
- [x] PR 15：「恢復後第一次播放不記歷史」只留了最小的 `PlaybackController.startedFromRestore`；接歷史時看夠不夠用。（夠用：控制器內部改成「這次開始算不算一次播放」的旗標）
- [ ] 臨時播放期間收著的恢復位置用曲目鍵判斷「佇列那首換了沒」：同一首在佇列出現兩次、臨時播放期間跳到另一個同曲目的項目時，恢復位置不作廢（影響小）。
- [ ] 「重啟恢復時倒退」選回「不倒退」時存成 0 而不是空值，標籤也不再帶「（預設）」；行為相同。
- [ ] 測試插件的曲目鍵不含關鍵字（`fmp-test:tone-220`），不同關鍵字搜到的是同一首；實機湊不出五首不同的曲目。

PR 15 留下的：

- [ ] 歷史頁只在 `play_history` 變動時重讀；曲目標題被別處 upsert 更新後，要等下一次播放才顯示新標題。
- [ ] 沒有 log 行標示「記了一筆歷史」，實機只能查資料庫或看歷史頁。
- [x] 歷史頁與搜尋頁的列選單各寫一份（spec 註明改一邊看另一邊）；PR 18b 的佇列分頁加第三份時考慮抽共用。（PR 18b 抽成 `TrackRowMenu`）
- [x] 「清除全部歷史」的語意標籤重複成「清除全部歷史. 清除全部歷史」（tooltip 與 label 同字），同搜尋結果「⋯」那條。
- [ ] 臨時播放結束、回到佇列並以暫停狀態載入時，log 仍記一行 `Track audible`（不影響歷史，log 語意不準）。
- [ ] 模擬器時區是 UTC，實機看到的時刻比本機少 8 小時；驗日分組時注意。

PR 16a 留下的：

- [x] PR 18a：`NowPlaying.speed` 固定 1.0；加速度選單時 publisher 要接控制器的速度，否則系統推算的進度會偏。
- [ ] `AudioService.init` 的 `configure` 等媒體服務連上才回；一直連不上時 `main()` 會卡在 `runApp` 之前。沒有 repro，沒加 timeout。
- [ ] publisher 建好前（`playbackControllerProvider` 還沒被讀）送來的媒體鍵會被丟掉。
- [ ] 通知頻道名稱固定 `FMP`，沒有翻譯（舊版有）。
- [ ] 通知的小圖示是 Flutter 預設的 `ic_launcher`（dev），要等 App 圖示定案。
- [ ] Android 16 以上的預測返回：實機（API 37）在「搜尋」按返回確實退到背景、Activity 沒被結束，但沒分辨是經 `popSystemNavigator` 還是系統直接處理。
- [ ] 鎖定畫面的媒體控制沒有實機驗（模擬器沒設螢幕鎖）；M2 驗收時在有螢幕鎖的裝置看一次。
- [ ] `plugins/`、`settings/` 也可以擋 import `ui/`（審查建議，這次沒加）。

PR 17 留下的：

- [ ] 輸出裝置失敗改用系統預設沒有實機驗（Windows 停用裝置要系統管理員權限）；M2 驗收時拔一次真的 USB／藍牙裝置。
- [ ] `_useSystemOutput` 在等來源停下的幾毫秒內，使用者剛好選了別的裝置，會被改回系統預設（理論上的競態，寫不出重現條件）。
- [ ] 焦點在播放列按鈕或選單項目上時，空白鍵是播放／暫停，不是觸發那個按鈕（Enter 才是）；照 ADR 字面與 M1，記下。
- [x] PR 18a：點播放列空白處開播放頁、Ctrl+L／Q、Esc 關播放頁；播放頁那層 `PlaybackShortcuts`。

PR 18a 留下的：

- [ ] 播放頁開著時旋轉螢幕或安全區改變，提示的底部位移不更新（外殼只在開頁那一刻讀 `viewPadding.bottom`）。
- [ ] `setSpeed` 選同一個值也發 `speedChanges`（publisher 會去重，沒有實際影響）。
- [ ] 既有、不是 PR 18a 造成：Windows `install_search_play_test.dart` 收尾時偶爾記一筆 `CouldNotRollBackException`（堆疊在 `PlayHistoryRecorder._write`），是第二首交接後 `record` 還在跑時 `close()` 關了資料庫；`main` 的 CI（PR #213、#214 的 run）也有。錯誤若在測試檢查「沒有 error log」之前落地會偶發失敗；可改成 dispose 時等寫入完成。
- [ ] 播放頁的 F6 在實機只靠 widget 測試，沒有逐區確認焦點。

PR 18b 留下的：

- [ ] 交接後馬上暫停、還沒出聲時，`Track audible` 這一行要等下一次佇列編輯（重新準備前瞻）才記，`sinceHandoverMs` 很大；播放歷史不受影響（交接當下已算），只是 log 語意不準（同 PR 15 那條）。
- [ ] 拖曳把手沒有語意標籤（輔助技術用 `ReorderableListView` 的上移、下移動作）；實機的語意樹看不到它。
- [ ] Windows 實機的 debug 標籤蓋住播放頁右上角佇列鈕的一角（只有 debug 建置）。

PR 16b 留下的：

- [ ] Windows 上 publisher 照樣經 cache manager 下載 `artworkFile`，但 SMTC 用的是 `artworkUrl`：每首多一次下載與一次不起作用的推送，無害；要省就依平台宣告略過。
- [ ] 鍵盤的實體媒體鍵沒有驗：Windows 自己決定送給哪個工作階段（可能是別的 App），實機只經工作階段 API 對 FMP 送指令。
- [ ] 音量浮層的媒體卡片沒有截圖看（浮層上可能有擁有者其他 App 的卡片），以工作階段 API 讀的內容為準。
- [ ] SMTC 回報 `IsShuffleEnabled`／`IsRepeatEnabled` 為真（套件替這兩個請求註冊了監聽），App 不處理；Win11 的浮層不顯示這兩顆鈕。
- [ ] 建過 Windows 之後，`dart format … .` 會因 `build/` 底下 cargokit 產生的 `.dart` 回非零（`app/AGENTS.md` 已註明），CI 不受影響。

PR 19 留下的：

- [ ] 記住收起又沒有歌時，沒有地方展開面板（播放列與播放頁都不在），加歌後才有入口。
- [ ] 既有、不是 PR 19 造成：手機橫向（約 411dp 高）打開鍵盤時，`NavigationRail` 與搜尋頁的 `Column` 溢出（實機 8.8／9.9 px，記成 `Uncaught Flutter error`）；面板收起時一樣。
- [ ] `layoutStateProvider` 還沒讀到值時面板當作展開、用預設寬度；Windows 連拍沒看到閃動，慢的裝置可能看得到（外觀主題也是同樣的寫法）。
- [ ] `OrderedTraversalPolicy` 目前與閱讀順序結果相同，沒有測試會因拿掉它而紅（AGENTS.md 已註明，review 時看）。
- [ ] 寫入失敗時寬度改回儲存值的那一支沒有測試。
- [ ] 整個 App 重開仍記得面板狀態只有實機驗，沒有端到端的測試。

（每個 PR 收尾時補；格式照 M1 的「PR n 留下的後續」各節。）

## 里程碑驗收（19 之後）

### 兩平台端到端（ADR 0026 §決定 1；Android 模擬器與 Windows 各一次，dev flavor）

- **模式**：
  - 主流程用 B 站插件（真實連線）：M2 的目標是「以單一音源像舊版一樣日常聽歌」；
  - 只做下列最少的操作，每平台約十首的解析與封面請求；
  - 離線與錯誤的步驟改用測試插件（重播）。
- **步驟**（兩平台相同，平台差異標在括號）：
  1. 清掉 dev 資料目錄，以 `--fmp-dev-plugin` 安裝 B 站插件並啟動。
  2. 搜尋一個關鍵字：點第一首（臨時播放）→ 以選單把另外四首加入佇列、其中一首用「下一首播放」。
  3. 播放列：下一首、上一首（3 秒內與外各一次）、拖進度條、開隨機、開循環「全部」、調音量、靜音再取消。
  4. 開播放頁：
     - 三種寬度（Windows）／直橫向（Android）；
     - 佇列分頁拖曳一首、移除一首；
     - 詳細分頁；
     - 速度 1.5 跨兩首仍是 1.5；
     - Esc／返回鍵關閉。
  5. 右側面板（Windows）：拖寬、收起、展開。
  6. 系統媒體控制：
     - Android 通知與鎖定畫面的上一首、暫停、下一首、拖進度；
     - Windows 鍵盤媒體鍵與媒體卡片。
  7. Android：
     - 「歷史」分頁按返回回到「搜尋」，再按返回 App 退到背景、音樂繼續；
     - 模擬一次音訊焦點中斷（暫停並在結束後續播）。
  8. Windows：切換輸出裝置（有兩個裝置時）。
  9. 單曲循環一首兩圈；歷史頁看到對應筆數並從歷史點一首臨時播放，結束後回到佇列原位置（倒退 10 秒）。
  10. 關掉 App 重開：
      - 佇列、目前這首、位置（倒退「重啟恢復時倒退秒數」）、隨機順序、循環、音量都在；
      - 啟動時沒有解析請求；
      - 封面從快取讀、沒有媒體請求。
  11. 設定：
      - 「播放」組每一列各改一次；
      - 「網路」組看封面用量、清除快取後封面重新下載；
      - 音質切到「低」播一首，`bitrate` 是最低層。
  12. 離線（改用測試插件）：
      - 播放中切斷網路 → 全域離線提示、播放列顯示等待網路、沒有提示洗版；
      - 恢復網路 → 自動續播；
      - 搜尋頁在沒有介面時顯示離線狀態。
  13. 錯誤（測試插件）：`fail` 關鍵字的提示、連續跳過到上限停止並提示一次、試聽關鍵字在兩種設定下的行為。
  14. 隔天（或把 log 檔修改時間改到 8 天前）重開：超過 7 天的 log 被刪。
- **證據**：寫在本任務 `research/m2-acceptance.md`。照 M1 `research/m1-acceptance.md` 的格式，記平台、模式、真實請求清單、截圖（不含個人資訊）。

### ADR 的測試（design §12 第 3 條確認後的範圍）

| ADR | 項目 | 在哪個 PR |
|---|---|---|
| 0016 | 串流網址快取的安全邊界、`expiresAt` 為空、作廢；**預取後播放只解析一次**（下載不走快取在 M6） | 7 |
| 0016 | 快取庫跨類別淘汰、檔案被刪視為未命中、清除後用量 0、移除插件刪項目 | 4、5 |
| 0016 | 網路狀態轉換且沒有計時器輪詢 | 2 |
| 0016 | 各頁離線狀態（M2 存在的畫面） | 2、15、18a |
| 0016 | 插件契約：`expiresAt` 與網址期限一致 | 8 |
| 0016 | lint：快取目錄只經快取模組 | 4 |
| 0017 | 啟動維護清單（排程器的七項在 M3，決定 2） | 6 |
| 0025 | log 保留 7 天與大小同時作用 | 6 |
| 0018 | `QueueModel`：隨機位置語意、拖曳、連續下一首播放、臨時播放快照、上限（Mix 修剪在 M3） | 9 |
| 0018 | `RecoveryPolicy`：每類錯誤、離線暫停計數、歸零、連續跳過停止 | 12 |
| 0018 | 預取後播放只解析一次；單曲循環每圈一筆歷史且不重解析（開直播取消音樂請求在 M3） | 7、10、15 |
| 0018 | 後端契約：同一份規則跑兩個實作與假後端（E19、前瞻失敗、HTTP 狀態碼） | 11、13 |
| 0018 | lint：結束原因型別、窄介面 | 1 |
| 0024 | 播放頁與播放列的 guideline、golden、快捷鍵與焦點 | 17、18a、18b、19 |

- [ ] 上表逐項在 PR 描述或測試檔找到對應。
- [ ] `milestones.md` 的 M2 狀態與兩個驗收勾選（ADR 0026 §如何確認：未打勾不能 archive）。
- [ ] `app/AGENTS.md` 的播放、網路、介面、資料層段落與 M2 的實際一致（逐條有閘門或標明「沒有閘門，review 時看」）。
- [ ] 本任務 `finish`、`archive`。

## 待升級

- `analysis_server_plugin`、`analyzer`、`analyzer_testing` 仍停在 M1 的釘版（`app/AGENTS.md:594-596`）；Flutter 放寬 `test_api` 後一起升。
- `smtc_windows` 最後一版 2025-08-18（digest §3）：M2 期間若 Flutter 或 `flutter_rust_bridge` 不相容，照 ADR 0009 §決定 6 以 git 依賴鎖 commit 並註明上游 issue。

## 風險與回滾點

| 風險 | 處理 |
|---|---|
| `AudioServiceActivity` 的共用引擎讓 `--fmp-dev-plugin`、`integration_test`、`flutter run` 的附加在 Android 失效 | design §8.3 的 `provideFlutterEngine` 覆寫，PR 16a 的實測第一步就驗。不行就先不用 `AudioServiceActivity`，照 `audio_service` 文件手動覆寫 `provideFlutterEngine` 與 `shouldDestroyEngineWithHost`。PR 16a 可單獨 revert |
| `smtc_windows` 要 Rust 從原始碼編譯，本機或 CI 缺工具鏈就建置失敗；套件 13 個月沒有新版 | 舊專案的 `windows-2022` CI 證明 runner 有 Rust；本機要求寫進 `app/AGENTS.md`。壞掉時 16b 單獨 revert，Windows 暫時沒有 SMTC，其餘不受影響 |
| `handleInterruptions: false` 後自寫的中斷處理漏掉情況（例如通話結束不續播），或與 M1 的音訊焦點契約衝突 | 只轉成事件交給控制器，邏輯照舊版 `just_audio_service.dart`；PR 13 實測焦點中斷，並以 `dumpsys audio` 確認換歌仍不放焦點 |
| 佇列一萬筆的差量寫入在 Android 太慢 | PR 14 量整份取代的耗時；超標時改成背景 isolate 的 drift 執行器（`NativeDatabase.createInBackground`），不改資料格式 |
| `flutter_cache_manager` 的 `CacheStore` 有自己的記憶體快取與清理計時器，和統一淘汰器互相干擾 | `getObjectsOverCapacity`、`getOldObjects` 回空；靠它「取檔前檢查存在」的行為（已讀原始碼）；PR 4 測「淘汰器刪檔後同一張圖重新下載」 |
| 拿掉 `deadline` 的遮蔽讓其他 fixture 的「再遮一次不變」紅掉，或被認為放寬遮蔽 | 只改這一個參數名；PR 8 的檢查要試著攻破；fmp-plugins 的 fixture 同一輪重錄。不接受時改回，ADR 0016 的契約檢查標為恆真並寫進 `app/AGENTS.md` 的已知限制 |
| B 站在錄 fixture 或驗收的真實連線時風控 | 最少操作；卡住時改用測試插件完成 UI 與播放驗證，B 站部分具名回報 blocker（M1 同一做法） |
| `tracks` 提前後 M4 的欄位需求和 M2 的形狀衝突 | M2 只放音源給的事實，欄位都可空或必有；M4 只加欄位與新表。擁有者不同意提前時，改成佇列與歷史各存快照，M4 再搬（design §3.1 的另一案） |
| PR 數量多（20 個），依賴鏈長（1 → 9 → 10 → 12 → 14 → 15） | 依「順序與相依」的圖平行開不同目錄的 PR；schema 版本號由後合併的 PR 重排 |
