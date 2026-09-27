# 執行計畫：第 14 項（設計任務，只產出文件）

1. [x] 核准後寫 `docs/adr/0019-library-and-sync.md`（依 `docs/adr/template.md`），內容取自 `design.md` §1–§6；被否決的方案：
   本地與匯入同表只靠網址區分、手動維護反向關係、遠端移除後保留並標示、部分失敗靜默只增不刪、加入遠端也加確認框、
   每張歌單各存「使用登入刷新」、匯入與歌詞兩套評分、手動重搜只看播放量、`fuzzywuzzy`（GPL）。
2. [x] ADR 0014 決定 9：補上評分核心的正規化與套件（見 ADR 0019）。
3. [x] `phase2-plan.md`：§3 第 14 項標 ✅（ADR 0019）；待辦（第 20 項）加入「另存為本地歌單」「曲目收藏」「疑似換版本偵測」；§10 交接段更新，下一項 11 下載與權限。
4. [x] 驗證：`git grep` 確認 ADR 間引用。
5. [x] `task.py finish`、`task.py archive design-library-sync --no-commit --skip-branch-validation`；分開提交 ADR 與歸檔，推上 `docs/audit`。

回退：全部是文件，revert 對應 commit 即可。
