# 0011 — 單一日誌門面與單一遮蔽函式；設定依功能分組、空值代表未設定

- 狀態：已採納
- 日期：2026-09-27
- 影響範圍：`app/lib/core/logging/`、`app/lib/core/redaction/`、dio 攔截器、Debug 頁、診斷包、設定的資料表與 Riverpod 狀態

## 背景

舊專案的自製 `AppLogger` 只遮 header 與 key 名：stackTrace 不遮、CDN 簽名 URL 不遮、release 版仍輸出到 logcat，
AI 請求在 debug 級別整份寫進 log（`docs/audit/devtools.md` §3、`docs/audit/accounts-network.md` §4）。
設定約 45 項，約 19 個 Notifier 各自讀寫同一列 `Settings`，migration 還改寫過使用者設定（`docs/audit/data.md` §2、§7）。

擁有者要求：所有會展示或匯出請求內容的地方（Toast 詳細、Debug 頁、診斷包、log）經過同一個遮蔽函式，
cookie、token、簽名 URL、API key 一律遮蔽；錯誤進入可檢索的歷史；Debug 頁用 App 的設計系統。
設定存在資料庫、migration 不得改使用者設定過的值（ADR 0010）。

## 考慮過的選項

- **日誌套件**：`logger`（有輪替與記憶體輸出，但沒有檢視 UI 與 dio 整合）、`logging`（官方但極簡）、`loggy`（四年未更新）、
  自寫全套、`talker`（採用：記憶體歷史、分派、五平台、持續維護）。
- **檢視 UI**：`TalkerScreen`（否決：不是 App 的設計系統）vs 自製（採用）。
- **網路紀錄**：`talker_dio_logger`（否決：直接寫入 talker，繞過遮蔽層）、`alice`（否決：另一套平行 UI 與遮蔽面）、
  `pretty_dio_logger`（否決：不留歷史）、自己的攔截器經門面寫入（採用）。記錄 request／response body（否決：遮蔽代價高、易漏）。
- **遮蔽時機**：在 talker 觀察者裡遮（否決：talker 的紀錄欄位不可變，做不到）、在門面寫入前遮（採用）。
- **設定建模**：單一大表（Spotube；否決：舊版多 Notifier 共寫一列的問題會延續）、key-value 表（否決：失去型別、無先例）、
  `shared_preferences`（否決：位置無法跟 Portable 版走，ADR 0010）、每組一張單列表（採用）。
- **release 版 log 檔**：不寫（否決：重開後錯誤歷史消失）、只寫 warning 以上（否決：缺前因後果）、寫 info 以上（擁有者 2026-09-27 選定）。

## 決定

1. **日誌門面**：全 App 只有一個 log 入口，參數含訊息、tag（模組或音源 id）、error、stackTrace、結構化欄位；
   門面先遮蔽，再交給 `talker`（只用它的歷史與分派）。門面以外禁止 `print`、`debugPrint`、`developer.log` 與直接使用 talker。
2. **輸出**：記憶體歷史最近 1,000 筆；檔案在 ADR 0009 資料目錄的 `logs/`，單檔 2MB、保留 3 個，寫入失敗不影響 App；
   console 只在 debug build，release 不輸出到 logcat／stdout。release 預設層級 `info`，開發者模式可調到 `debug`。
3. **遮蔽函式**（唯一一個）依序套用：header 名單、key 名單（query 與 body）、已知媒體 CDN 的簽名參數去除、
   已知憑證值逐字替換（帳號層登記目前各音源的實際憑證值，Finamp 的做法）。套用在訊息、error 字串、stackTrace、結構化欄位。
   名單集中一處，音源插件可追加自己的名單。
4. **網路紀錄**：自己的 dio 攔截器，每個請求一筆摘要（方法、主機、路徑、遮過的 query、狀態、耗時、大小、音源、錯誤類型），
   經門面寫入；不記 body。
5. **錯誤歷史**：統一錯誤型別被處理時一律經門面以 `warning`／`error` 寫入，帶錯誤類型、音源、對應網路紀錄等欄位；
   Debug 頁篩選即為錯誤歷史，跨重啟由 log 檔提供。
6. **診斷包**：參考 NewPipe，一組欄位產生純文字與 JSON；內容為版本、平台、語系、各音源啟用與登入狀態（是／否）、
   非敏感設定摘要、已遮蔽的 log 與錯誤歷史；不含硬體識別資訊、帳號名稱、歌單內容。產生時組裝一次，匯出只用這份結果。
7. **設定**：依功能分組（播放、外觀、音樂庫與同步、下載、歌詞、網路、桌面、開發者），每組一張單列表、每個設定一個有型別的欄位，
   每組一個 Riverpod Notifier 監看自己那一列、只寫改動的欄位。**欄位為空＝使用者沒設定過**，讀取時套用程式預設；
   改預設值不需 migration，也不會動到使用者設定過的值。每個音源的設定另一張表，以音源 id 為主鍵。設定包含在備份中。設定頁版面、「鍵盤快捷鍵」與「關於」頁見 ADR 0024。

採用的慣例：talker 作資料核心；Finamp `censored_log.dart` 的已知值替換；NewPipe 錯誤報告的欄位結構；
Spotube 以 drift 存設定並以 `watchSingle()` 接 Riverpod。

## 後果

- 好的：任何出口都不會漏出未遮蔽的內容；錯誤可依類型與音源追查；設定的預設值可以安全調整；新增音源不必改設定 schema。
- 壞的：Debug 頁的 log 檢視要自己做；遮蔽名單要隨音源維護；release 版在本機留有 info 級別的使用紀錄（已遮蔽、不上傳）。
- 之後要注意：統一錯誤型別的欄位由錯誤模型的 ADR 定；開發者模式的持久化、log 保留 7 天與 JSON Lines 格式、Debug 頁見 ADR 0025；各組設定的欄位清單在里程碑中依 `docs/audit/data.md` §7 定案。

## 如何確認

- lint：門面以外禁止 `print`、`debugPrint`、`developer.log`、import talker：lint `fmp_log_facade`（ADR 0015）。
- 遮蔽測試：每個音源一組假憑證與假簽名 URL，斷言經 log 檔、記憶體歷史、診斷包、網路紀錄後都不再出現原值，包括出現在 stackTrace 的情況。
- 設定測試：寫入使用者值後改變程式預設，斷言讀到的仍是使用者值；未設定的欄位讀到新預設。
