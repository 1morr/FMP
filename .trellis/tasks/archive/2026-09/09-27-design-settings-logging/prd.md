# 設計第 18 項：設定與日誌基礎設施

## 目標

定下新 App 的設定怎麼分組、怎麼存；log 的層級、輸出、輪替與保留；以及所有會展示或匯出內容的出口
（log 檔、Debug 頁、錯誤 Toast 的詳細、診斷包、網路紀錄）共用的**同一個遮蔽函式**。

需求來源：parent `prd.md` 階段二第 3、4、18 項；`questions.md` C2（重寫時修正）、J3（按推薦）、M3／M4；ADR 0009（目錄）、ADR 0010（設定存資料庫、migration 不改使用者值）。

## 現況（證據）

- 自製 `AppLogger`：500 筆記憶體緩衝、落盤 `Documents/FMP/logs/fmp.log` 2MB×3 輪替、`redactSensitive` 只遮 header 與 key 名；release 版仍 `debugPrint` 到 logcat（`docs/audit/devtools.md` §3）。
- 外洩面：stackTrace 不遮、CDN 簽名 URL 不遮、AI 請求 payload 在 debug 級別整份寫入（`docs/audit/accounts-network.md` §4、`devtools.md` §3.3）。
- 設定約 45 項，約 19 個 Notifier 各自讀寫同一列 `Settings`（`docs/audit/data.md` §7、`architecture.md` §4）。

## 研究結論（`research/logging-and-redaction.md`、`research/diagnostics-and-settings.md`）

- 日誌：`talker` 5.1.20（2026-07，五平台，160/160）是唯一同時有記憶體歷史、檢視 UI、dio 轉接的候選；`logger` 2.8.0 有輪替但沒有 UI 與 dio 整合。talker 的紀錄物件欄位不可變，**遮蔽必須在呼叫 log API 之前**做（在觀察者裡做不到）。
- 遮蔽：三種策略互補——key／header 名單、CDN URL 形狀截斷、**已知值替換**（Finamp：把目前登入帳號的實際 token 值在訊息與 stackTrace 中逐字替換）；stackTrace 也要遮。網易的簽名在 POST body 不在 URL。
- 診斷包：NewPipe 的錯誤報告結構最適合參考（同一組欄位產生文字／JSON，刻意不含硬體識別資訊）；Finamp 的教訓：在產生內容時遮一次，匯出只用已遮的結果。
- 網路紀錄：`talker_dio_logger` 會繞過我們的遮蔽層；`alice` 是另一套平行 UI；`pretty_dio_logger` 不留歷史。
- 設定建模：Spotube 用 drift 單列多欄（每個設定一個有型別的欄位），Riverpod 以 `watchSingle()` 串流接上；沒找到 key-value 表的先例。

## 需求

- R1 單一 log 入口（薄門面）；門面先遮蔽再交給 `talker`；門面之外禁止 `print`、`debugPrint`、`developer.log` 與直接呼叫 talker（lint，第 8 項）。
- R2 單一遮蔽函式，四種策略：header 名單、key 名單（query 與 body）、CDN URL 簽名參數、已知憑證值替換；套用在訊息、error 字串與 stackTrace。Toast 詳細、Debug 頁、診斷包、網路紀錄、log 檔都只用遮過的內容。
- R3 網路紀錄用自己的 dio 攔截器，只記摘要（方法、主機、路徑、遮過的 query、狀態、耗時、大小、音源、錯誤類型），不記 body。
- R4 錯誤歷史：統一錯誤模型（第 2 項）的每個錯誤都以結構化欄位寫入 log，Debug 頁可依類型、音源、時間篩選。
- R5 設定依功能分組，每組一張單列表、每個設定一個有型別的欄位；欄位可為空＝「使用者沒設定過，用程式預設」，讓預設值可以改而不動使用者值；每個音源的設定另一張表以音源 id 為鍵。
- R6 release 版不輸出到 logcat／stdout。

## 已決定

- D1（使用者 2026-09-27）：release 版寫 log 檔，層級 `info` 以上，單檔 2MB、保留 3 個，只存本機、經遮蔽、不上傳。
- 其餘依研究與使用者要求（Debug 頁用 App 設計系統）寫入 design.md：不用 `TalkerScreen`、不用 `talker_dio_logger`、不記 body、設定分組單列表。

## 驗收標準

- [x] design.md 涵蓋日誌門面與輸出、遮蔽函式、網路紀錄、錯誤歷史、診斷包、設定建模。
- [x] `docs/adr/0011-*.md` 依範本寫成。
- [x] `phase2-plan.md` 標記第 18 項完成。
