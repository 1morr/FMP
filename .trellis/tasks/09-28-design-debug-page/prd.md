# Debug 頁與開發者模式的設計

## 目標

階段二第 4 項（parent prd 第 4 項；`docs/audit/questions.md` J1–J4）：把 Debug 頁做成正式工具。
範圍包括：
- 開發者模式怎麼開、怎麼關、要不要記住；
- Debug 頁的區塊與版面；
- log 檔的輪替與保留期限；
- 資料檢查／修復。

產出 ADR 0025。

## 現況（研究已以程式碼核對，細節見 `research/current-state.md`）

- **開發者模式**
  - 開法：「版本」列連點 7 次（`developer_options_provider.dart:49`）。
  - 狀態只放在記憶體，重啟就消失，也沒有關閉入口。
  - 路由無條件註冊（`router.dart:246-263`）。
  - 它只控制兩件事：設定頁是否出現入口、執行期的 log 層級。
- **Debug 頁**：四個區塊，都沒有權限閘門。
  - 記憶體磚：只清 Flutter 記憶體圖片快取。
  - log 層級。
  - 資料庫檢視器：11 個 collection 各做一次 `findAll()`；唯讀，不能搜尋、不分頁。
  - 重設資料：`isar.clear()` 之後跑 migration。
- **Log 檢視頁**
  - 已有：記憶體 500 筆、即時串流、層級與文字篩選、匯出落盤檔（存檔）。
  - 沒有：系統分享、錯誤歷史的概念。
- **Log 檔**：單檔 2MB、保留 3 個，每種 build 都寫。與 ADR 0011 的差異：
  - 記憶體 500 筆，ADR 要 1,000 筆；
  - release 也輸出到 console；
  - stackTrace 沒有遮蔽；
  - 沒有「保留 N 天」的概念。
- **`DataIntegrityRepository.scan/repair`**（`data_integrity_repository.dart:59-162`）
  - 檢查四件事：Track `uniqueKey` 重複、DownloadTask `savePath` 重複、Account `platform` 重複、PlayQueue 超過一筆。
  - `lib/` 裡零呼叫點，只有測試用。
- **沒有的東西**：App 內網路請求紀錄、播放狀態除錯畫面、診斷包、音源健康檢查、插件系統、統一的清除快取入口。
  - 目前 HTTP 流量只能經 VM Service 看（`docs/development.md` §執行期除錯）。

## 研究結論（`research/prior-art.md`、`research/packages-and-platform.md`）

- **入口**：
  - 隱藏手勢：Firefox 連點 logo 5 次；Android 系統本身連點版本號 7 次。
  - 可見設定項：NewPipe（不列入偏好搜尋）、Home Assistant、Signal（說明頁）。
  - LocalSend：關於頁的一顆按鈕，沒有 build 閘門。
- **log 檢視**：Immich、Signal 有層級與搜尋。有 HTTP 請求頁的只有 LocalSend（記憶體 200 筆）。
- **上限**：LocalSend 200 筆、Immich 500 筆、Signal 單檔 20 MiB 且保留 3 天（較長者 21 天）。
- **遮蔽**：只有 Signal（`Scrubber`）與 Namida 有自動遮蔽；Home Assistant 在分享前跳警示。
- **匯出**：Immich、AppFlowy、Namida、Signal 都分享檔案或 zip；Spotube、NewPipe 只給剪貼簿。
- **套件**：
  - talker、alice、requests_inspector 都沒有 release 閘門，閘門要 App 自己加。
  - ADR 0011 已否決用 `TalkerScreen`、`talker_dio_logger`、alice 當 UI。
- **資料庫**：
  - drift 官方 DevTools extension 隨 `drift` 出貨，可以改資料、沒有唯讀模式，release 編譯期整段移除。
  - drift 官方沒有 App 內檢視器；`drift_db_viewer` 2.1.0 唯讀，但已 2.5 年沒發版。
  - drift 沒有唯讀 API（`customSelect` 不擋寫入語句）；要唯讀就自己用 `allTables` 加 `select`。
- **log 輪替**：
  - `logging`、`talker` 都不寫檔。
  - 只有 `logger` 的 `AdvancedFileOutput` 內建依大小輪替，沒有依日期輪替。
  - 社群的 `talker_persistent` 有 `retentionDays`（預設 3）。
- **匯出管道**：
  - `share_plus` 在 Linux 與 Windows RS5 以下分享檔案會 throw；
  - `file_selector.getSaveLocation` 只有桌面能用；
  - Android 分享走 `ACTION_SEND`。
- **插件開發**：
  - MusicFree 沒有熱重載。
  - LX Music 切換腳本＝拆掉整個 runtime 重建，除錯靠 DevTools。
  - VS Code 的做法是「Reload Window」。
  - Flutter 熱重載只在 debug build。
  - Android 以 file_picker 選資料夾後讀其中 `.js` 不成立（推測，未實機）；ADR 0015 已限桌面，影響為零。
  - `watcher` 1.2.1 桌面三平台走原生事件。

## 已由前面 ADR 定下的邊界

- **ADR 0011**
  - log 門面與遮蔽函式；
  - 記憶體 1,000 筆、檔案 2MB×3；
  - release 預設 info，開發者模式可調到 debug；
  - 網路紀錄由自己的 dio 攔截器，每請求一筆摘要經門面寫入，不記 body；
  - 錯誤歷史＝Debug 頁的篩選，跨重啟由 log 檔提供；
  - 診斷包欄位參考 NewPipe；
  - 設定裡有「開發者」一組；
  - 「Debug 頁與開發者模式的持久化由 Debug 頁的設計定」。
- **ADR 0013、0023**：開發者模式下每則錯誤提示附「詳細」；Debug 頁的錯誤歷史與提示共用同一個詳細頁。
- **ADR 0015**
  - 音源健康檢查＝檢查案例的真實連線版，在 App 內手動跑。
  - 插件開發工具：開發者模式下、先限桌面、從資料夾載入、重新載入、跑案例看 log、錄 fixture、每插件切換真實／錄製／重播。
  - 「版面由 Debug 頁的設計定」。
  - flavor 分 `dev`／`prod`。
- **ADR 0016**：「清除快取」與各類用量在設定頁。
- **ADR 0010**：drift 以外鍵與唯一鍵保證關係；舊資料匯入先寫暫存庫並驗證。
- **ADR 0018**：播放狀態是 sealed 型別，位置走獨立 stream。
- **ADR 0024**：設計系統；設定頁在 expanded 以上用 list-detail。

## 擁有者的輸入

- J1 勾「保留」（連點 7 次、不持久化、無關閉入口）。
- J2、J3、J4 勾「不確定」。
- 備註：「如果有問題或是有更好的方案的話可以按你推薦的來改」。
- `phase2-plan` §8 的方向：
  - Debug 頁重做成正式工具；
  - log 保留並加輪替與保留期限；
  - 資料檢查／修復收進 Debug 頁。

## 已決定

1. **開發者模式**（2026-09-28，擁有者「按你建議」，取代 J1 的「保留」）：
   - 入口：「設定 → 關於」版本列連點 7 次。
   - 開啟狀態存進設定的「開發者」組，跨重啟保留。
   - Debug 頁最上方放總開關。關掉後：入口消失；錯誤提示不再附「詳細」；log 層級回到 info。
   - dev flavor 預設開啟。
   - 理由：ADR 0023 的「詳細」、ADR 0011 的 debug 層級、ADR 0015 的插件開發工具都依賴它。不記住的話，每次重啟都要再點 7 次、重新載入插件資料夾。
2. **區塊與 release 版**（2026-09-28，擁有者「按你建議」）：
   - 版面：寬畫面左列區塊、右顯示內容；手機進子頁（同設定頁，ADR 0024）。
   - 八個區塊：
     1. 概覽：總開關、log 層級、版本／flavor／平台／資料目錄、診斷包（複製、存檔，手機可分享）。
     2. Log 與錯誤歷史：層級、tag、文字篩選；「只看錯誤」＝錯誤歷史；錯誤開 ADR 0023 詳細頁；匯出 log 檔。
     3. 網路：取自 log 的網路摘要，不另存；可依音源、狀態碼篩選。
     4. 播放狀態：狀態、曲目、串流格式與位元率、後端、輸出裝置、重試、佇列；可複製快照。
     5. 音源健康檢查。
     6. 插件開發：只有桌面。
     7. 資料庫：唯讀瀏覽（筆數、分頁、敏感欄位遮蔽）＋資料檢查。
     8. 重設資料：先自動備份，再二次確認。
   - 拿掉：記憶體磚（改用 DevTools）；快取（在設定頁，ADR 0016；概覽放連結過去）。
   - release 版：開了開發者模式就全部可用。
   - debug build：另可用 drift 官方 DevTools extension。

## 待決定（一次問一題）

3. log 保留期限。
4. 資料檢查／修復在 drift 之下要做什麼。

## 驗收條件

- [ ] 以上待決定項都有擁有者的答覆，寫進 ADR 0025。
- [ ] ADR 0025 含「如何確認」（測試或 lint 與第一個里程碑的實測項目）。
- [ ] ADR 0011、0015 各加一句指向 0025。
- [ ] `phase2-plan.md` 的 §3、§7／§8、§10 已更新。
