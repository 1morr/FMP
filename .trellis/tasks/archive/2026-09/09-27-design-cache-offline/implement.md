# 執行計畫：第 17 項（設計任務，只產出文件）

1. [x] 核准後寫 `docs/adr/0016-cache-and-offline.md`（依 `docs/adr/template.md`），內容取自 `design.md` §1–§7；被否決的方案：
   分類上限、串流網址持久化（B6）、宿主解析各平台期限參數、通用 HTTP 回應快取、DNS 輪詢（B10）、手動離線模式與邊聽邊存（功能凍結，列待辦）。
2. [x] ADR 0014 補一句：`resolveStream` DTO 帶 `expiresAt`、封面為多尺寸 `artwork` 清單（見 ADR 0016）。
3. [x] `phase2-plan.md`：§3 第 17 項標 ✅（ADR 0016）；待辦（第 20 項）加入邊聽邊存、手動離線模式、已下載內容容量管理；§10 交接段更新，下一項 16 背景任務。
4. [x] 驗證：Mermaid 以 mermaid-cli 渲染（設計圖已驗）；`git grep` 確認 ADR 間引用正確。
5. [x] `task.py finish`、`task.py archive design-cache-offline --no-commit --skip-branch-validation`；分開提交 ADR 與歸檔，推上 `docs/audit`。

回退：全部是文件，revert 對應 commit 即可。
