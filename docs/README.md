# FMP 文件地圖

此目錄保存面向使用者、貢獻者與維護者的專案文件。根目錄 [README](../README.md) 是產品入口；AI coding agent 的強約束規則在 [AGENTS.md](../AGENTS.md)。

## 先讀哪份文件

| 情境 | 建議文件 |
|------|----------|
| 想下載或快速了解 FMP | [專案 README](../README.md) |
| 想在本機編譯 Android / Windows | [建置指南](build-guide.md) |
| 想理解專案架構與主要模組 | [開發文件](development.md) |
| 要發布新版本或調整 Release 流程 | [建置與發布指南](build-and-release.md) |
| 要用 VM Service / Marionette 做 Runtime 調試 | [VM Service 調試指南](debugging-with-vm-service.md) |
| 要查歷史重構背景 | [歷史重構流水](history/refactoring-log.md) |
| 要修改程式碼並遵守 agent 規則 | [AGENTS.md](../AGENTS.md) |

## 目前文件

| 文件 | 讀者 | 用途 |
|------|------|------|
| [開發文件](development.md) | 貢獻者 | 專案概覽、技術棧、架構地圖、目前開發規則摘要 |
| [建置指南](build-guide.md) | 本機建置者 | Android APK、Windows 免安裝版與安裝包的本機建置說明 |
| [建置與發布指南](build-and-release.md) | 維護者 | CI、簽名、GitHub Releases、更新資產與發版流程 |
| [VM Service 調試指南](debugging-with-vm-service.md) | 調試者 / agent | 透過 Dart VM Service、Marionette 與 Isar Inspector 做運行期檢查 |
| [歷史重構流水](history/refactoring-log.md) | 維護者 | 已歸檔的歷史記錄，只作背景參考，不作為目前實作規範 |

## 權威來源

- [AGENTS.md](../AGENTS.md) 是 AI coding agent 的權威規則，包含架構邊界、遷移規則、UI 編碼約束，以及會影響程式修改的專案注意事項。
- [開發文件](development.md) 是人類貢獻者的 onboarding 文件，只摘要目前架構並連回 `AGENTS.md`，不要在兩邊重複維護每條 agent 規則。
- [建置與發布指南](build-and-release.md) 是 Release 行為的權威文件；下載連結、產物命名與應用內更新規則變更時優先更新它。
- `.serena/memories/` 應保持狹窄且補充性質。如果某個 memory 變成目前核心規則，應合併到 `AGENTS.md` 或獨立文件，並刪除重複 memory。
- `docs/history/` 只放歷史脈絡。除非內容已反映在 `AGENTS.md` 或目前文件中，否則不要把歷史記錄當成現行規範。

## 維護規則

- 架構、資料模型、遷移、UI 或音源行為變更：優先更新 `AGENTS.md`，必要時同步更新 [開發文件](development.md)。
- 本機建置環境、工具鏈或打包前置條件變更：更新 [建置指南](build-guide.md)。
- CI 產物命名、Release workflow、簽名 secrets、應用內更新資產識別變更：更新 [建置與發布指南](build-and-release.md)。
- Runtime 調試流程、VM Service 腳本或 Marionette 用法變更：更新 [VM Service 調試指南](debugging-with-vm-service.md)。
- 使用者可見功能、截圖、下載入口或專案定位變更：更新根目錄 [README](../README.md)。
- 不要把同一條規則複製到多個文件，除非目標文件確實擁有對應讀者和維護責任。
