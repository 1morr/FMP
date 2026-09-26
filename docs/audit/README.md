# FMP 現況審計

> 現況描述，未經確認，不代表目標。

審計日期 2026-09-26～27，分支 `docs/audit`，基準 commit `6d78fe23`。
這是 `fmp-rewrite` 的階段一產出（Trellis task `.trellis/tasks/09-26-audit/`）。

## 怎麼讀

1. 先看下面的「一頁摘要」。
2. 再打開 [`questions.md`](questions.md) 勾選決策；每一項都附了指向細節文件的證據。
3. 需要細節時查對應文件。

| 文件 | 內容 |
|---|---|
| [`features.md`](features.md) | 功能清單（入口、背景行為）、死代碼、「你很可能不知道的功能」 |
| [`architecture.md`](architecture.md) | 分層、目錄地圖、模組依賴圖、Riverpod provider 圖、路由、啟動流程 |
| [`playback.md`](playback.md) | 點歌到出聲的序列圖、播放器狀態機、佇列、串流解析、錯誤恢復、系統媒體控制、Mix、電台 |
| [`sources.md`](sources.md) | 音源能力矩陣、音源抽象、新增音源要改的檔案、音源特定分支位置、匯入與歌詞匹配 |
| [`errors.md`](errors.md) | 例外型別、各音源錯誤流、限流／cookie 失效／風控、使用者看到什麼 |
| [`data.md`](data.md) | Isar schema 與 migration、secure storage、快取、下載檔結構、備份格式、設定總表 |
| [`downloads.md`](downloads.md) | 下載序列圖與狀態機、續傳、路徑設定與失效、已下載檔案、各平台權限 |
| [`accounts-network.md`](accounts-network.md) | 登入、HTTP client、各音源請求策略、敏感資訊外洩面、帳號全貌、請求 × 音源憑證矩陣 |
| [`platforms.md`](platforms.md) | 平台判斷位置、未驗證分支、平台綁定功能、依賴套件平台支援表、原生碼、其他平台的阻礙 |
| [`ui.md`](ui.md) | 頁面地圖、斷點、token、i18n、無障礙與鍵盤、實機截圖與問題 |
| [`perf-baseline.md`](perf-baseline.md) | 啟動時間、記憶體、長列表捲動的實機基準（重寫後的比較對象） |
| [`devtools.md`](devtools.md) | 開發者模式、Toast／log／錯誤呈現 |
| [`engineering.md`](engineering.md) | CI／發版、測試盤點、聯網點、static-rule、依賴健康度、死代碼、AI 指令檔、ADR 與 CONTEXT.md 比對 |
| [`questions.md`](questions.md) | 給你勾選的決策清單 |

## 方法與可信度

- 證據優先序：實際執行 > 程式碼 > 測試 > 文檔。每個結論附 `檔案:行號`、命令輸出或截圖；文檔與程式碼不符標「**不一致**」，未實測的標「**推測**」。
- 每份文件由一個子代理撰寫，再由另一個子代理做對抗式核查（重點核「死代碼／無呼叫端」、安全相關主張、推測）。首輪正確率約 93–98%，約 57 處被更正，文中以「核查更正」標記；沒有任何主要發現被推翻。
- 只跑了離線測試（`--exclude-tags live`）。App 只在 `ui.md`／`perf-baseline.md` 實機執行：Android emulator 用的是空的測試資料；**Windows 的 debug／profile build 會讀寫你真實的 `Documents\FMP`**，審計時誤觸了一次播放（佇列當前曲目開始串流後立即暫停），可能改了播放位置、多了一筆播放紀錄。
- 截圖中的個人資料（歌單、佇列、播放紀錄、當前曲目）已模糊處理。

## 一頁摘要

**規模。** `lib/` 手寫 Dart 343 檔 99,063 行（另有生成碼 46,089 行）、測試 261 檔 63,927 行、1,877 個 commit。離線測試 1,849 個全過，`flutter analyze` 無問題；但 main 的 CI 目前是紅的（一個用固定 200 ms 等待的時序測試，`engineering.md` §12）。

**架構。** 分層大致存在，AGENTS.md 宣稱的邊界逐條 grep 都成立，但實際依賴不是單向：有一個 19 個目錄的大循環（起因是 `main.dart` 的全域可變狀態被反向 import），`services → providers` 反向 11 次，UI 直接 import `services/` 66 次、`data/` 77 次。`AudioController` 單檔 2,953 行、約 125 個方法；播放器狀態至少有 5 份來源。162 個手寫 provider，放置慣例三種以上（`architecture.md`）。

**播放。** UI 上「點一首歌」幾乎全走「臨時播放」（播完回原佇列）；歌單頁「全部」按鈕其實只加入佇列。網路錯誤的重試訊號只有一個沒人用的入口接得住，臨時播放、Mix、上下首因此會出現錯誤路徑。預取在重啟後形同失效；隨機模式下拖曳與「下一首播放」的語意不對（`playback.md`）。

**音源。** 有能力介面（`SourceCapability`），但新增一個能搜能播的音源最少要改 15 個檔，做到網易雲同等約 54 個；音源特定分支 50 處散在 28 個檔，守它的 static-rule 預算只有 9 處。Spotify／QQ 只能匯入，匹配到可播放音源（`sources.md`）。

**錯誤。** 自訂例外到畫面一律變成「發生錯誤」（`userMessageFor` 不認得它們），同時 adapter 又會把 `e.toString()` 原文丟上畫面；多源搜尋只要一源成功就隱藏其他失敗；網易雲任何非 200 碼（含限流）都會清憑證；播放用的連線偵測不到登入失效（`errors.md`）。

**資料與下載。** Isar 走社群 fork `isar_community` 3.3.2，11 個 collection 之間沒有任何 link，關係靠手動維護的 id。含簽名的串流 URL 明文存進資料庫；Windows 上資料庫與 log 在「文件」資料夾。**已由程式碼確認的資料遺失路徑**：每次啟動的下載同步用「清理過特殊字元的資料夾名」比對歌單原名，對不上就丟關聯；約 10 秒後的孤兒清理只看這份關聯、不看歌單本身的曲目清單，於是曲目被刪、從歌單消失（未實機重現，`downloads.md` §4.4）。Android 下載路徑選一次就改不了；續傳不驗證檔案一致性（`data.md`、`downloads.md`）。

**帳號與隱私。** UI 的登入狀態讀 Isar，實際送請求只看 secure storage；「重設所有資料」不清憑證，重設後 UI 顯示未登入但請求仍帶舊 cookie（已由程式碼確認）。log 遮蔽不涵蓋 CDN 簽名參數與 stackTrace。v3→v4 migration 把使用者自己關掉的 B 站「用登入狀態播放」強制打開。YouTube／網易的首頁排行永遠不帶登入（`accounts-network.md`）。

**你很可能不知道的。** 在本機刪「匯入的平台歌單」裡的曲目，會同步在 B 站／YouTube／網易雲上刪；每次啟動可能自動換 B 站 cookie；網易雲寫入請求帶偽造的 `X-Real-IP`；AI 歌詞匹配（預設關）會把影片描述與歌詞預覽連同 API key 送到自訂端點、不強制 https；Windows 更新會靜默執行下載的安裝程式或用隱藏的 bat 覆蓋程式目錄，SHA-256 只在 release 附了 checksum 檔時才驗；每 15 秒解析三個公共 DNS 名稱（`features.md` §15）。

**平台。** 88 處平台判斷、三種寫法並存。macOS／Linux 會出現半套桌面 UI、沒有標題列、推測無法播放；iOS 程式碼最接近能跑但缺背景播放與 ATS 設定。Linux 缺 just_audio／audio_service／flutter_inappwebview 實作；`media_kit_libs_windows_audio` 在 pub.dev 已 unlisted（`platforms.md`）。

**UI。** i18n 三語言完全對齊（各 1,176 key），但間距與字級沒有 token、App 內沒有任何鍵盤快捷鍵、播放頁大播放鍵沒有無障礙名稱（`ui.md`）。

**效能基準（profile，3 次中位數）。** 冷啟動到首幀 Android 1,239 ms／Windows 1,731 ms；首頁記憶體 Android PSS ≈179 MB／Windows Working Set ≈300 MB；長列表 UI thread 每幀中位數 1.00 ms／0.45 ms（`perf-baseline.md`）。

**工程與文檔。** 不加參數的 `flutter test` 會打三個音源的正式 API（`dart_test.yaml` 沒有預設 skip）。7 份 ADR 中 5 份與程式碼一致，0001、0007 部分不一致；CONTEXT.md 5 個術語都對得到程式碼，Media Handoff 的 redirect 檢查只在下載路徑。AI 指令檔分散在 AGENTS.md、`.trellis/`、`.claude/`、`docs/agents/`、`CONTEXT.md`、`orca.yaml`，有數處互相矛盾；`docs/agents/` 仍是 mattpocock 模板內容（`engineering.md` §8–§11）。
