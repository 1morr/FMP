# FMP 文件地圖

此目錄保存面向使用者、貢獻者與維護者的專案文件。根目錄 [README](../README.md) 是產品入口；AI coding agent 的強約束規則在 [AGENTS.md](../AGENTS.md)。

## 先讀哪份文件

| 情境 | 建議文件 |
|------|----------|
| 想下載或快速了解 FMP | [專案 README](../README.md) |
| 想在本機編譯 Android / Windows | [建置指南](building.md) |
| 想理解專案架構與主要模組 | [開發文件](development.md) |
| 要發布新版本或調整 Release 流程 | [建置與發布指南](build-and-release.md) |
| 要用 VM Service 做 Runtime 調試 | [VM Service 調試指南](debugging-with-vm-service.md) |
| 改了 UI／使用者可見行為，要做強制的 Android 模擬器實機驗證 | [verify-on-device skill](../.claude/skills/verify-on-device/SKILL.md) |
| 遇到看起來像錯誤的建置或 runtime log 噪音 | [疑難排解](troubleshooting.md) |
| 想知道接下來要做什麼、順序與驗收 | [整頓與重構計劃](plan.md) |
| 想知道某個架構決定「當初為什麼這樣選」 | [adr/](adr/) |
| 想知道某一輪執行時推翻了哪條先前結論 | [review/execution-log.md](review/execution-log.md) |
| 要修改程式碼並遵守 agent 規則 | [AGENTS.md](../AGENTS.md) |

## 目前文件

| 文件 | 讀者 | 用途 |
|------|------|------|
| [整頓與重構計劃](plan.md) | 維護者 / agent | 2026-09 審計後的里程碑、任務、驗收與待拍板決策；完成一個里程碑就更新它的進度表 |
| [開發文件](development.md) | 貢獻者 | 專案概覽、技術棧、架構地圖、目前開發規則摘要 |
| [建置指南](building.md) | 本機建置者 | Android APK、Windows 免安裝版與安裝包的本機建置說明 |
| [建置與發布指南](build-and-release.md) | 維護者 | CI、簽名、GitHub Releases、更新資產與發版流程 |
| [VM Service 調試指南](debugging-with-vm-service.md) | 調試者 / agent | 透過 Dart VM Service 與 Isar Inspector 做運行期檢查 |
| [疑難排解](troubleshooting.md) | 開發者 / agent | 已查證的良性建置與 runtime 噪音（如 Windows `Failed to update ui::AXTree`、`resolve_symlinks.ps1` 的 `Get-Item` 警告）與其成因 |
| [adr/](adr/) | 貢獻者 / agent | 架構決策記錄：決定了什麼、為什麼，以及被否決的替代方案與否決的證據 |
| [agents/](agents/) | agent 工具鏈 | engineering skills 讀取的專案設定：issue 追蹤、triage 標籤、domain 文檔規則 |
| [review/execution-log.md](review/execution-log.md) | 維護者 | Phase 0–7 執行期每一輪開工前推翻了哪些先前結論、收工時實機看到什麼 |

## 權威來源

- [AGENTS.md](../AGENTS.md) 是 AI coding agent 的權威規則，包含架構邊界、遷移規則、UI 編碼約束，以及會影響程式修改的專案注意事項。
- [開發文件](development.md) 是人類貢獻者的 onboarding 文件，只摘要目前架構並連回 `AGENTS.md`，不要在兩邊重複維護每條 agent 規則。
- [建置與發布指南](build-and-release.md) 是 Release 行為的權威文件；下載連結、產物命名與應用內更新規則變更時優先更新它。
- **語系分工是刻意的**：`AGENTS.md`（根目錄與各子樹）與 `docs/agents/` 維持英文，與程式碼、commit、識別字一致，方便 agent 與跨語言貢獻者比對；`docs/` 其餘文件與根目錄 `README` 以中文撰寫，面向人類使用者與貢獻者。不強制統一語系。
- `.claude/skills/` 放可被 Claude Code 直接叫用的專案 skill（目前只有 `verify-on-device`：模擬器與桌面版的實機驗證迴圈）。`.gitignore` 只追蹤這個子目錄，`.claude/` 其餘內容是本機狀態，不進版控。
- `docs/agents/` 是 engineering skills（`/triage`、`/to-tickets`、`/to-spec`、`/wayfinder`、`/domain-modeling` 等）讀取的專案設定，不是給人讀的說明文件；要換 issue 追蹤系統或標籤詞彙時直接改這裡的檔案即可。這三個檔是 `/setup-matt-pocock-skills` 的產出**再加上 FMP 專屬修改**（repo 釘死成 `1morr/FMP`、繁中語言政策、與 `AGENTS.md` 的分工），重跑那個 skill 會用泛用模板覆蓋掉它們。

## 維護規則

- 架構、資料模型、遷移、UI 或音源行為變更：優先更新 `AGENTS.md`，必要時同步更新 [開發文件](development.md)。
- 本機建置環境、工具鏈或打包前置條件變更：更新 [建置指南](building.md)。
- CI 產物命名、Release workflow、簽名 secrets、應用內更新資產識別變更：更新 [建置與發布指南](build-and-release.md)。
- Runtime 調試流程或 VM Service 腳本變更：更新 [VM Service 調試指南](debugging-with-vm-service.md)。
- 模擬器啟動方式、實機驗證流程或裝置端限制變更：更新 [verify-on-device skill](../.claude/skills/verify-on-device/SKILL.md)，並讓 `AGENTS.md` 的 Agent Skills 只保留一行指引。
- 使用者可見功能、截圖、下載入口或專案定位變更：更新根目錄 [README](../README.md)。
- `review/execution-log.md` 是**歷史**，不是規則。**程式碼、測試與 `AGENTS.md` 不得
  引用它** —— 一份被引用的歷史快照不是歷史快照，是沒人維護的活文檔。要留下的事實
  請寫進它所描述的那個檔案裡。`test/support/agents_docs_static_rule_test.dart` 守著
  這條規則。截圖留在 `review/assets/04-ui-ux/`，它是 UI 回歸唯一的歷史視覺基準。
- 不要把同一條規則複製到多個文件，除非目標文件確實擁有對應讀者和維護責任。
