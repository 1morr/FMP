# 執行計畫：第 5 項（設計任務，只產出文件）

1. [x] 核准後寫 `docs/adr/0024-ui-ux-design-system.md`（依 `docs/adr/template.md`），內容取自 `design.md` §1–§9，附示意頁連結（私人，擁有者可見）；被否決的方案：
   播放頁 A 左右分割、C 沉浸式歌詞；只留繁中與英文、簡中自動轉換；App 內只做畫面操作、App 內快捷鍵可自訂；中寬度保留五個播放控制；
   保留 App 內使用者指南；`flutter_adaptive_scaffold`（已停止維護）；dynamic color（新功能）；
   全 App 毛玻璃、整套液態玻璃、各平台原生風格。
2. [x] 其他 ADR 各加一句指向 ADR 0024：0011（設定頁版面、快捷鍵與關於頁）、0015（`fmp_design_tokens`）、0021（播放頁歌詞位置）。
3. [x] `phase2-plan.md`：§3 第 5 項標 ✅（ADR 0024）；§7 第一個里程碑加入「空白鍵在輸入框內只輸入空格、F6 焦點切換、Windows 繁中字形由正黑體顯示」；
   §10 交接段更新，下一項 4 Debug 頁，下一份 ADR 0025。
4. [x] 驗證：`git grep` 確認 ADR 間引用。
5. [x] `task.py finish`、`task.py archive design-ui-ux --no-commit --skip-branch-validation`；分開提交 ADR 與歸檔，推上 `docs/audit`。

回退：全部是文件，revert 對應 commit 即可。
