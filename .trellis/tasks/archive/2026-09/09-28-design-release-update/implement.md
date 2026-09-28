# 執行計畫：第 19 項（設計任務，只產出文件）

1. [x] 核准後寫 `docs/adr/0022-release-and-in-app-update.md`（依 `docs/adr/template.md`），內容取自 `design.md` §1–§3；背景寫明延續舊 ADR 0004（不上架）與 0006（驗過直接發布）、差異為改用 release-please；
   被否決的方案：手動改 pubspec＋打 tag（順序錯就失敗、沒有 CHANGELOG）、Linux 發 Flatpak／deb（App 不能自己換檔）、macOS 付費公證（暫不）、
   Windows 經 SignPath 簽章（每版需手動核准、發行者非 FMP）、`desktop_updater`／`auto_updater`（Linux 不成熟或無 Linux、停滯）、
   免安裝版解到 Temp 後 `robocopy` 覆蓋（部分成功會留下半套檔案）、只在有 checksums 檔時才驗、自動檢查更新。
2. [x] 其他 ADR 各加一句指向 ADR 0022：0009（能力 `appUpdate`）、0017（更新檔清理登記在啟動維護清單）、0020（下載引擎也用於更新檔）。
3. [x] `phase2-plan.md`：§3 第 19 項標 ✅（ADR 0022）；§7 第一個里程碑加入「release-please 發版 PR 與同一 workflow 的建置發布跑通（可用測試 repo 或 dry-run）」；
   §8 延後實測加入：切換 PR 前以舊版 v1.11.0 實際更新到新 App（Android 與 Windows 兩種）；Windows App 自行下載的安裝檔不帶 Mark of the Web；
   macOS App 自行下載的更新不帶 quarantine；Linux AppImage 的改名替換；§10 交接段更新，下一項 3 Toast，下一份 ADR 0023。
4. [x] 驗證：Mermaid 以 mermaid-cli 渲染；`git grep` 確認 ADR 間引用。
5. [x] `task.py finish`、`task.py archive design-release-update --no-commit --skip-branch-validation`；分開提交 ADR 與歸檔，推上 `docs/audit`。

回退：全部是文件，revert 對應 commit 即可。
