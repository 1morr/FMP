# FMP 文件地圖

根目錄 [README](../README.md) 是產品入口；AI coding agent 的規則在 [AGENTS.md](../AGENTS.md)，人類貢獻者適用同一套。

| 文件 | 什麼時候讀 | 什麼變了要更新它 |
|------|------------|------------------|
| [README](../README.md) | 想下載或快速了解 FMP | 使用者可見功能、截圖、下載入口、專案定位 |
| [建置指南](building.md) | 在本機編譯 Android / Windows | 本機建置環境、工具鏈、打包前置條件 |
| [開發文件](development.md) | 理解架構與主要模組；用 VM Service 查正在跑的 app | 架構分層、Runtime 調試流程 |
| [建置與發布指南](build-and-release.md) | 發新版本、調整 CI 或 Release 流程 | CI、產物命名、Release workflow、簽名 secrets、應用內更新資產 |
| [疑難排解](troubleshooting.md) | 看到像錯誤的建置或 runtime log，或遇到修不掉只能繞過的行為 | 新查明的噪音或已知行為 |
| [.trellis/spec/](../.trellis/spec/) | 用 Trellis 跑任務，或想知道某一層的程式碼照什麼模式寫（英文，給 agent 讀） | 某層的寫法慣例變了；有閘門的規則改在 `AGENTS.md`，spec 只連過去 |
| [adr/](adr/) | 想知道某個跨模組決定「當初為什麼這樣選」 | 新的跨模組決策（決定、理由、被否決的方案） |
| [verify-on-device skill](../.claude/skills/verify-on-device/SKILL.md) | 改了使用者可見行為，要做強制的實機驗證 | 模擬器啟動方式、驗證流程、裝置端限制 |
| [agents/](agents/) | （給 engineering skills 讀，不是給人讀）| 換 issue 追蹤系統或標籤詞彙 |

## 分工

- 單一段程式碼的理由寫在它旁邊（dartdoc 或守著它的測試）；只有程式碼查不到的跨檔契約與地雷才進 `AGENTS.md`。
- 同一條規則只寫在一個地方，除非另一份文件確實有自己的讀者。
- **語系分工是刻意的**：`AGENTS.md`、`docs/agents/` 與 `.trellis/spec/` 維持英文，與程式碼、commit、識別字一致；`docs/` 其餘文件與根目錄 `README.zh-Hant.md` 以繁體中文撰寫。
- `.claude/skills/` 放可被 Claude Code 直接叫用的專案 skill。`.gitignore` 另外追蹤 Trellis 的接線（`.claude/` 下的 `agents/`、`commands/`、`hooks/`、`settings.json`）；`.claude/` 其餘內容與 `.trellis/workspace/`（session 日誌）是本機狀態。
- `docs/agents/` 的三個檔是 `/setup-matt-pocock-skills` 的產出**再加上 FMP 專屬修改**（repo 釘死成 `1morr/FMP`、繁中語言政策），重跑那個 skill 會用泛用模板覆蓋掉它們。
- 審查記錄不進 `docs/`。一輪審計的結論寫進它所描述的檔案、開成 issue，或留在 git 歷史。
