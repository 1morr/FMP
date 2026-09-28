# 執行計畫：第 3 項（設計任務，只產出文件）

1. [x] 核准後寫 `docs/adr/0023-unified-toast.md`（依 `docs/adr/template.md`），內容取自 `design.md` §1–§6；被否決的方案：
   三條入口並存（舊版）、桌面右下角疊卡、依序排隊、`fluttertoast`（沒有 Windows）、`toastification`（沒有動作與 live region）、
   把報告內容放進 GitHub 網址、一般使用者完全看不到回報、子視窗各自顯示提示。
2. [x] 其他 ADR 各加一句指向 ADR 0023：0013（提示外觀、去重時間、詳細）、0015（`fmp_toast_entry`）、0021（子視窗提示轉主視窗）。
3. [x] `phase2-plan.md`：§3 第 3 項標 ✅（ADR 0023）；§7 第一個里程碑加入「提示在全螢幕頁與對話框之上可見；Windows Narrator 下提示不凍結無障礙樹」；
   §10 交接段更新，下一項 5 UI/UX，下一份 ADR 0024。
4. [x] 驗證：Mermaid 以 mermaid-cli 渲染；`git grep` 確認 ADR 間引用。
5. [x] `task.py finish`、`task.py archive design-toast --no-commit --skip-branch-validation`；分開提交 ADR 與歸檔，推上 `docs/audit`。

回退：全部是文件，revert 對應 commit 即可。
