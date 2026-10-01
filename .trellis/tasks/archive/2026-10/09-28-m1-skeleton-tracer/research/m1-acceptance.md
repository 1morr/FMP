# M1 驗收紀錄（2026-10-01）

逐項對照 `phase2-plan.md` §7 與本任務 `prd.md` §驗收。證據類型：**實測**＝實機、執行時或 CI 實跑；
**測試**＝單元／widget 測試。研究檔路徑以 archive 後的位置為準。

## §7 逐項

| 項目 | 證據 | 結果 | 類型、平台 |
|---|---|---|---|
| ADR 0010 isar＋sqlite3 共存、16KB 對齊 | `research/isar-sqlite3-coexistence.md` | 兩庫各自開庫讀寫；16KB 頁模擬器 debug／release 都過；所有 `.so` p_align ≥ 0x4000，`zipalign -c -P 16` 過；零衝突 | 實測（探針，未合併）；Android 模擬器、Windows |
| ADR 0009 CI 含 Linux、macOS、iOS（不簽名） | #192 | 五平台 prod release 建置，macOS／iOS 另建 dev；之後每個 `app` PR 都跑 | 實測（CI） |
| ADR 0008 prod 身分同舊版、dev 不同 | #175、#192、本檔 §dev 與 prod | 身分測試（Android、Windows、iOS、macOS，皆有變異）；工作列 AppID prod `com.personal.fmp` 與使用者釘選的舊版 FMP 合併成同一顆，dev `com.personal.fmp.dev` 另一顆 | 實測＋測試；Windows |
| ADR 0011 log 門面與遮蔽，含遮蔽測試 | #180、#186、#184 | 遮蔽測試（含審查補的 6 類）；兩平台 log 檔寫入；端到端真實連線時 log 無 CDN 網址（#191） | 測試＋實測 |
| ADR 0014 `flutter_js`、宿主 API 最小集 | #183 | 每插件一個背景 isolate；從檔案安裝 `fmp-test`、重開後從資料庫載入 | 實測；Windows、Android 模擬器 |
| ADR 0014 從檔案安裝 B 站插件 | #185、#191 | Windows dev 裝上 `bilibili 0.1.0`；兩平台以它搜尋並連播 | 實測（真實連線） |
| ADR 0014 Promise／記憶體／啟動成本 | `archive/2026-09/09-30-js-runtime/research/notes.md` §4 | 背景 isolate 版：首次建立 Windows 49–82 ms、Android 64–206 ms；search 往返 0.8–0.9／11–20 ms；宿主呼叫 0.16–0.22／6.4–8.8 ms；3 個 runtime RSS +4.6–9.0／+3.1–3.4 MB | 實測；Windows、Android 模擬器，debug 模式（實機 profile 重量列為後續） |
| ADR 0014 YouTube.js 探針 | #188、`archive/2026-09/09-30-youtubejs-probe/` | 四項條件通過（VISIONOS client），M3 的 YouTube 走插件 | 實測（真實連線）；兩平台 |
| ADR 0018 前瞻交接、Android 不放音訊焦點 | #187、#191 | Windows 間隔約 50 ms；Android 30–40 ms；整段一次 `requestAudioFocus`、無 `abandonAudioFocus`；真後端契約 Windows 10/10、Android 連續 5 次 10/10 | 實測；Windows、Android 模擬器（`-no-audio`，以 AudioFlinger 寫入判斷） |
| ADR 0015 `dart analyze` 見插件診斷、哨兵會紅 | #177 | 同一暫放檔 `dart analyze` 報 `fmp_no_empty_catch`、`flutter analyze` 乾淨；哨兵報出 13 條規則 | 實測＋CI |
| ADR 0015 契約執行器與 QuickJS | #183、#184 | 裸 `flutter test` 可載入 QuickJS，不需整合測試退路；CI 的 Linux `flutter test` 也跑 | 實測（Windows）＋CI（Linux） |
| ADR 0015 dev 與 prod 同時開啟各自獨立 | 本檔 §dev 與 prod（另 #175 的視窗與鎖） | AppUserModelID、單一實例鎖、資料目錄三者各自獨立 | 實測；Windows |
| ADR 0015 零聯網兩道防線 | #175 | `live` tag 預設跳過；`--run-skipped --tags live` 時被 `HttpOverrides` 擋下 | 實測＋測試 |
| ADR 0022 release-please 與同一 workflow 的建置、驗證、發布 | #193、`archive/2026-10/10-01-app-release-workflow/research/sandbox-run.md` | sandbox 2.0.0 草稿→修正→2.0.1 正式發布；11 個檔核對；沒有發版時不建置 | 實測（sandbox） |
| ADR 0023 提示在全螢幕頁與對話框之上 | #191、#192 | `toast_layering_test` Windows、Android 模擬器 2/2；CI 的 Linux、Windows 每次跑 | 實測＋CI |
| ADR 0023 Narrator 下不凍結無障礙樹 | #191 | Narrator 開著送提示，MSAA 節點 30→31，消失後移除，換頁照常 | 實測；Windows 11 |
| ADR 0024 輸入框內空白鍵只輸入空格 | #191 | Windows（含中文輸入法選字）、Android 輸入框內不切換播放；框外切換 | 實測＋測試 |
| ADR 0024 F6 焦點切換 | 本檔 §F6、`test/ui/shell/app_shell_test.dart` | 內容→播放列→導覽→內容循環 | 實測＋測試；Windows |
| ADR 0024 Windows 繁中由正黑體顯示 | #190 | 繁中、English 的字型 fallback 為正黑體，简中為雅黑；切換四次 log 都對 | 實測（以 log 的字型清單判斷）；Android 另驗英文介面漢字字形 |

端到端（#191，模式：真實）：Windows 搜「piano」、拖到接近結尾由前瞻接上第二首，7 個 API GET；Android 模擬器第一首
自然播完後交接，約 40 ms，8 個 API GET。兩平台 log 都沒有 CDN 網址。

R1：本 session 開頭的 SessionStart 只列 `guides` 與 `app/*` 的 spec 索引。

## 本次補做的實測（Windows 11，dev 用測試插件，模式：重播；prod 無插件、無網路操作）

### F6

用 MSAA 的 `STATE_SYSTEM_FOCUSED` 讀焦點（`verify-on-device` 的 `msaa_tree.ps1` 加上狀態欄位的暫時版本）。
測試插件搜尋並播放一首，讓播放列出現；焦點在搜尋框時連按四次 F6：

| 次數 | 焦點 |
|---|---|
| 1 | 播放列「上一首」 |
| 2 | 導覽「搜尋」分頁 |
| 3 | 內容區的搜尋框 |
| 4 | 播放列「上一首」 |

### dev 與 prod 同時開啟

prod 是以目前 `main` 建的 `--flavor prod --release`（免安裝），與 dev debug 同時執行：

- **視窗**：`FMP` 與 `FMP Dev` 兩個行程同時存在。
- **單一實例鎖**：兩個 flavor 各再啟動一次，第二個實例都在數秒內以 0 結束，原本兩個都還在。
- **資料目錄**：prod 寫在執行檔旁的 `userdata\`，dev 在 `userdata-dev\`；兩邊 log 的 `App started` 分別是
  `flavor: prod`、`flavor: dev` 與各自的目錄。
- **AppUserModelID**：工作列按鈕的 UI Automation AutomationId 分別是 `Appid: com.personal.fmp` 與
  `Appid: com.personal.fmp.dev`。prod 那顆與使用者原本釘選的舊版 FMP 是同一顆（身分與舊版相同）。
- **舊版資料未被碰到**：執行前後 `Documents\FMP` 與 `%APPDATA%\com.personal\fmp` 的檔案數與最新修改時間相同。
  兩個 App 以 `WM_CLOSE` 正常關閉。

更正：#192 與 13a 的 prd 寫「Windows prod 的資料目錄是使用者真實的 `Documents\FMP`」不對。新 App 的免安裝 prod 用
執行檔旁的 `userdata\`，安裝版用 `%APPDATA%\com.personal\fmp`（`app/lib/platform/app_data_directory/app_data_directory_windows.dart`）；
本機的 prod 建置是免安裝版，執行它不碰 `Documents\FMP`。M5 的舊資料匯入會讀 `Documents\FMP`，那時在本機執行 prod 要另外小心。

## 留下的限制

- Android 的 dev 與 prod 並存沒有實測：模擬器上的 `com.personal.fmp` 是舊版測試資料，不裝 prod（已列在 9a 的後續）。
- `flutter_js` 成本只有 debug 模式與模擬器的數字；實機 profile 重量列在 9a 的後續。
- Android 播放只以 AudioFlinger 寫入、音訊焦點與位置前進判斷，模擬器沒有出聲。
- 發版產物只在 sandbox 驗過，沒有安裝；正式金鑰與 v1.11.0 升級的實測在 M9 前（13b 的後續）。
