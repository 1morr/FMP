# JS 執行環境與插件載入（M1 PR 9a）

父任務：`../09-28-m1-skeleton-tracer`（implement「9.」的 9a；prd 擁有者決定 6）。

依據：
- ADR 0014 §決定 1–5 與 2026-09-30 的補充：安裝檔格式；
- ADR 0015 §決定 6：測試插件；
- ADR 0012、0013：宿主 HTTP 經網路層、結構化錯誤轉成 `AppError`；
- ADR 0011：`log` 經門面。

## 做什麼

1. **引擎**：`flutter_js`（pub.dev 最新 stable），Android 與 Windows 用 QuickJS。
   - 先查官方文件、README 與原始碼：
     - 怎麼執行腳本、怎麼跑 Promise／microtask；
     - 怎麼從 JS 呼叫 Dart 的非同步函式；
     - 每個插件一個獨立 runtime；
     - 能不能執行 ES module 語法。
   - 若不支援 `export`，腳本改用約定的全域寫法，例如 `globalThis.fmpPlugin = { search, resolveStream }`，並更新 ADR 0014 補充句裡的範例說法。
   - 查證來源記在 `research/notes.md`。
2. **安裝檔與 manifest**：`lib/plugins/manifest/`。
   - 從單一 `.js` 檔開頭的 `/* ==FMP Plugin== … ==/FMP Plugin== */` 取出 JSON，不執行腳本。
   - 欄位（ADR 0014 §決定 3）：
     - `id`、`name`、`version`、`author`、`apiVersion`；
     - `capabilities`：本 PR 認得 ADR 的 12 個名稱，未知名稱就拒絕；
     - `allowedHosts`；
     - `login`：M1 只接受空值或省略；
     - `retry`、`rateLimit`：對應 PR 7 的策略型別，可省略；
     - `redaction`：追加的遮蔽名單；
     - `defaults`、`icon`：網址或 `data:` base64。
   - 驗證：
     - 必填欄位、型別；
     - `apiVersion` 必須等於宿主支援的版本（v1），不相容就拒絕；
     - `id` 格式：小寫英數與 `-`，長度上限；
     - `allowedHosts` 只能是 host，不含 scheme 或路徑。
   - 錯誤以 `AppError`（`Unsupported` 或 `ParseError`）表達，附給使用者看的 key。
3. **執行環境與宿主 API v1**：`lib/plugins/runtime/`。`flutter_js` 只准在這裡 import，`fmp_layer_imports` 已守。
   - 每插件一個 runtime，彼此看不到對方。
   - `http.request`：經 PR 8 的 `SourceHttpClient`，網域清單取自 manifest。JS 端拿到狀態碼、header、body 字串。每個請求的 `AuthRequirement` 由腳本宣告，預設 `never`。
   - `crypto`：M1 只提供 B 站需要的 `md5` 與 `sha256`（字串進、hex 出）。B 站 WBI 簽名要 md5，參考舊專案 `lib/data/sources/bilibili_source.dart`。
   - `storage`：該插件在 `plugin_storage` 的 get、set、delete（PR 5 的 repository），key 與 value 都是字串。
   - `credentials`：M1 一律回「沒有憑證」（`CredentialStore` 在 M3）。
   - `log`：經門面，tag 是插件 id，層級照門面。
   - **結構化錯誤**：腳本以約定的形狀 throw，例如 `{ fmpError: 'RateLimited', retryAfterSeconds, reason }`，宿主轉成對應的 `AppError`。其他例外在插件邊界包成 `UnexpectedError`（`AppError.wrap`，ADR 0013 §決定 2）。
   - 逾時：每次呼叫插件函式都有上限，例如 30 秒，超過就回 `NetworkError`，或另定的錯誤。
   - 啟動時把 manifest 的遮蔽名單交給遮蔽函式（PR 6 的追加 API）。
4. **`SourcePlugin` 介面**：`lib/plugins/source_plugin.dart`，App 其他部分只認這個。
   - M1 的方法只有 `search` 與 `resolveStream`。其他能力的方法在引入它們的里程碑加，不寫空殼。
   - DTO，版本化，v1：
     - `SearchQuery`：關鍵字、頁碼；
     - `SearchPage`：項目、有沒有下一頁；
     - `TrackSummary`：`TrackKey` 的三段、標題、上傳者、時長毫秒、`artwork`（`[{url, width?}]`）；
     - `StreamRequest`：`TrackKey`、平台可播格式、用途 `playback`；
     - `StreamCandidate`：網址、headers、容器、編碼、位元率、`expiresAt`。
   - 輸入與輸出都驗證；插件回傳的形狀不對時回 `ParseError`。
   - 匯出一致性：manifest 宣告的能力，腳本必須都有匯出對應函式，否則拒絕載入（ADR 0014 §如何確認）。
5. **從檔案安裝**：`lib/plugins/install/`，一個 service 接收檔案內容（bytes 或字串），依序：
   1. 解析 manifest；
   2. 在 runtime 試載入並檢查匯出一致；
   3. 寫進 `installed_plugins`（PR 5）；
   4. 註冊到插件清單的 provider。
   
   已安裝同 id 時視為更新，storage 保留。選檔 UI 在 PR 12。本 PR 只提供 service，以及 dev 啟動時從命令列參數或環境變數讀路徑安裝的開發入口。只在 dev flavor 生效，寫明理由。
6. **測試插件**：`app/test/fixtures/plugins/test_plugin/test_plugin.js`（ADR 0015 §決定 6）。
   - 用安裝檔格式，id 例如 `fmp-test`；
   - 能力：`search`、`resolveStream`；
   - 回傳合成資料，不發任何網路請求；串流指向 `app/` 內附的一個很短的本機音檔。音檔用 CC0，或自己用 `ffmpeg` 產生的靜音或正弦波，授權寫在旁邊。
   - 用來測執行環境、宿主 API、轉換；PR 10、12 的實機驗證也用它。
7. **QuickJS 能否在 `flutter test` 內載入**（§7 的實測）：
   - 先試裸 `flutter test`；
   - 不行就依研究的做法（先建置桌面產物，把原生庫放進 `PATH` 或設 `LIBQUICKJSC_TEST_PATH`）；
   - 再不行就改用 `integration_test`（ADR 0015 的退路）。
   - 把結論和實際可用的指令寫進 `app/AGENTS.md` 的驗證段；CI 的 `app` job 照這個結論跑執行環境的測試（Linux runner）。
8. **`flutter_js` 實測**（§7），寫進 `research/notes.md`，並把數字交主對話轉給擁有者：
   - Android 模擬器與 Windows 各量三件事：建立 runtime 的時間、載入測試插件的時間、一次 `search` 的往返時間（含 Promise）；
   - 建立 1 個與 3 個 runtime 後增加的記憶體（RSS）；
   - 量測用的程式碼放在 `integration_test/`，或一個只在 dev 的量測入口，不進正式路徑。
9. **文件**：
   - `app/AGENTS.md` 插件段：安裝檔格式、宿主 API 清單、結構化錯誤的形狀、`flutter_js` 只在 runtime 目錄；
   - `.trellis/spec/app/plugins/index.md`（繁中）：怎麼寫一個插件、怎麼加宿主 API（要改 `apiVersion` 嗎）；
   - TypeScript 型別定義 `app/lib/plugins/types/fmp-plugin.d.ts`，給插件作者用，內容與 DTO 一致。要有測試或腳本確認兩邊欄位一致；做不到就在 AGENTS.md 寫明靠 review。

## 驗收

- [ ] `app/`：
  - format 通過；
  - codegen 沒有變動；
  - `dart analyze --fatal-infos`、`flutter analyze` 零問題；
  - `flutter test` 全綠，執行環境的測試有真的跑 QuickJS，或寫明改走哪條路；
  - 哨兵通過。
- [ ] 測試：
  - manifest 解析與拒絕的各種情況；
  - 能力與匯出不一致時拒絕；
  - `apiVersion` 不相容時拒絕；
  - 網域外的請求被拒；
  - 插件讀不到其他插件的 storage；
  - 結構化錯誤轉成對應的 `AppError`；
  - 逾時；
  - 用測試插件做搜尋與解串流。
- [ ] CI 的 `app` job 綠，而且跑到 QuickJS 的測試。
- [ ] `flutter_js` 在 Android 與 Windows 的實測數字（主對話在實機上跑量測入口）。
