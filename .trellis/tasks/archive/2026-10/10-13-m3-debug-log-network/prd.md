# M3b PR 12：Debug 頁的 Log 與錯誤歷史、網路區塊

> 父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（`implement.md` §12，design §12.3）。ADR 0025 §決定 2–4、ADR 0011（log 門面、遮蔽、網路摘要、錯誤歷史）。PR 11（#237）已建好 Debug 頁的 list-detail 骨架與「概覽」；這個 PR 加兩個區塊。計畫已核准，在範圍內直接做；遇到計畫沒寫的決定才問。

## 做什麼

1. **Log 區塊**（`DebugSection` 加一個值）：
   - 預設看這次執行的記憶體歷史（log 門面的 talker 歷史）。
   - 「含之前的紀錄」：在 isolate 以 M1 的 `parseLogLines` 讀回 log 檔（最多 6 MB，從最新的往回讀；壞行略過），與記憶體歷史合併、依時間排序、不重複。
   - 篩選：層級、tag、文字；「只看錯誤」＝錯誤歷史（點一筆的詳細頁在 PR 13，這個 PR 先不接）。
   - 動作：「複製已篩選」（純文字，經遮蔽後的內容本來就已遮蔽）；「清除 log」同時清記憶體歷史與 log 檔，排進 `LogFile` 的寫入佇列（同 M2 PR 6 的做法），確認對話框。匯出 log 檔在 PR 15。
2. **網路區塊**（`DebugSection` 再加一個值）：
   - 資料來源：tag `network` 的記錄（M1、M2 已寫，含 `client`、`networkRecordId`），不另存。
   - 清單欄位：時間、方法、主機、路徑、狀態、耗時、大小、音源。
   - 篩選：音源、狀態碼類別（2xx／3xx／4xx／5xx／失敗）、文字。
   - 單筆詳細：遮過的 query、錯誤類型、以 `networkRecordId` 對應的錯誤紀錄。
3. **字串與樣式**：slang 三語（en、zh-TW、zh-CN），token；寬窄版面照 PR 11 的 Debug 頁。
4. **文件**：`app/AGENTS.md` 的 Debug 頁與 log 段落；需要時 `.trellis/spec/app/ui/`、`logging/`。

## 不做

- 錯誤詳細頁與 GitHub 回報（PR 13）、匯出與診斷包（PR 15）、播放狀態與資料庫區塊（PR 14）、健康檢查與插件開發（PR 16）。

## 驗收

- [ ] 網路篩選依音源與狀態碼類別（ADR 0025 §如何確認），單元或 widget 測試。
- [ ] 清除 log 後記憶體歷史與 log 檔都空（測試）；清除和正在進行的寫入不互相打架（排進寫入佇列）。
- [ ] 「含之前的紀錄」：讀回檔案、6 MB 上限、壞行略過、與記憶體合併不重複（測試）。
- [ ] Log 篩選（層級、tag、文字、只看錯誤）、複製已篩選、網路單筆詳細與對應錯誤紀錄（widget 測試）；guideline 測試（寬窄）。
- [ ] `flutter analyze`、`dart analyze --fatal-infos`、`dart format`、`flutter test` 全綠。
- [ ] **實機**（Android 模擬器，dev debug；照 ADR 0027 §決定 3 的修訂，本 PR 只動共用 UI，不驗 Windows）：重播（`fmp-test`）搜尋後 Debug 頁網路區塊看到該筆、篩選可用；一次真實 B 站匿名搜尋看到網路摘要；Log 區塊的篩選與清除。
