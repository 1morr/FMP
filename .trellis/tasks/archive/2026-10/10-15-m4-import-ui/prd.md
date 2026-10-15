# M4 PR 8b 匯入對話框、手動刷新、狀態列

> M4 的 PR 8b（`../10-15-m4-library-sync/implement.md` § 8b）。設計在 `../10-15-m4-library-sync/design.md` §5.1、§5.3、§10.3、§10.4、§10.5、§10.8；決定在 ADR 0019 §決定 2、3，ADR 0033 §決定 1、2、8、9，ADR 0013 §決定 5。引擎（`PlaylistImporter`、`PlaylistRefresher`）在 PR 8a 已有。另有 PR 3 留下的兩件（implement.md「留下的後續」）。

## 做什麼

- **音樂庫工具列「匯入」**與對話框：一個文字欄（網址或 `mix:` 簡寫）→「匯入」→ `PlaylistImporter.importUrl`。進度（「已讀 n 首」）；完成後關閉並在音樂庫的巢狀導覽裡開詳情；不認得的網址、第一頁失敗顯示錯誤、不建歌單。`mixSeed` 與僅元資料來源的結果：本 PR 只顯示「尚未支援」之類的錯誤（PR 11、19 接上）。
- **刷新**：歌單卡選單與詳情頁的「刷新」（只有匯入歌單）→ `PlaylistRefresher.refresh(trigger: manual)`；手動刷新失敗照 ADR 0013 的呈現表提示，離線時（失敗且連線狀態不是 online）顯示離線字樣。自動刷新（PR 10）不跳 toast。
- **詳情的狀態列**：design §5.3 表的六種（正常／部分完成／刷新失敗＋重試／來源失效＋重試／需要登入＋登入（開帳號頁該音源那一列）／音源不可用）；匯入歌單的標頭加擁有者與音源標記。
- **「已失效」標記**：項目 `unavailable` 的曲目在列上標「已失效」，點了照常嘗試播放。
- 匯入歌單沒有重排與「從歌單移除」（PR 3 已依 `kind` 隱藏，確認匯入的歌單實際走到）。
- **匯入歌單的編輯**（PR 3 留下，design §10.5）：改名稱、描述、封面時把對應的 `*_overridden` 設為真；「使用遠端的」清回假（下一次刷新寫回遠端值）。自動刷新間隔的欄位在 PR 10。
- **匯入歌單的封面**（PR 3 留下）：封面有多張、在不同網域時，`PlaylistCover` 找插件要用實際選中的那張，或以歌單的插件 id 為準（擇一，回報理由）。
- 字串三語言；guideline；離線照常顯示本機資料。
- 文件：`app/AGENTS.md` § 音樂庫／§ 介面、`.trellis/spec/app/ui/index.md`。

## 驗收

- 測試：對話框（認得、不認得、第一頁失敗、進度）；狀態列六種與「重試」「登入」的動作；手動刷新失敗的提示與離線字樣；已失效標記；匯入歌單的編輯設與清 `*_overridden`；匯入歌單沒有重排與移除；guideline。用 `fmp-test` 的假歌單或測試內的假插件。
- `dart format`、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過。
- 實機（主對話做）：重播（Android）：`fmp-test` 的 `pl-basic`、`pl-grow`（刷新三次看新增、移除、倒序）、`pl-partial`、`pl-gone`（重試）、`pl-auth`、`pl-unavailable`、`pl-parts`。真實（匿名，Android）：匯入一張 YouTube 公開清單並手動刷新一次。
