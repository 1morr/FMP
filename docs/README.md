# FMP 文件地圖

根目錄 [README](../README.md) 是產品入口；AI coding agent 的規則在 [AGENTS.md](../AGENTS.md)，人類貢獻者適用同一套。新版從零重做，下表前五列與 ADR 0001–0007 描述根目錄的舊版。

類型依 [Diátaxis](https://diataxis.fr/)：操作指南（照步驟做一件事）、參考（查事實）、說明（理解為什麼）。

| 文件 | 類型 | 什麼時候讀 | 什麼變了要更新它 |
|------|------|------------|------------------|
| [README](../README.md) | 說明 | 想下載或快速了解 FMP | 使用者可見功能、截圖、下載入口、專案定位 |
| [建置指南](building.md) | 操作指南 | 在本機編譯 Android / Windows | 本機建置環境、工具鏈、打包前置條件 |
| [開發文件](development.md) | 說明 | 理解架構與主要模組；用 VM Service 查正在跑的 app | 架構分層、Runtime 調試流程 |
| [建置與發布指南](build-and-release.md) | 操作指南、參考 | 發新版本、調整 CI 或 Release 流程 | CI、產物命名、Release workflow、簽名 secrets、應用內更新資產 |
| [疑難排解](troubleshooting.md) | 參考 | 看到像錯誤的建置或 runtime log，或遇到修不掉只能繞過的行為 | 新查明的噪音或已知行為 |
| [設計綱要](design-brief.md) | 說明 | 想知道新版要做什麼、為什麼這樣決定 | 訪談拍板的需求、決定與查證過的事實 |
| [新版架構](../ARCHITECTURE.md)、[路線圖](roadmap.md)、[新版開發](app-development.md) | 說明、參考 | 想知道新版的架構、里程碑與怎麼建置驗證 | 架構、里程碑或閘門改動 |
| [進度](progress.md) | 參考 | 想知道新版做到哪、下一步是什麼 | 每個 session 結尾 |
| [adr/](adr/) | 說明 | 想知道某個跨模組決定「當初為什麼這樣選」 | 新的跨模組決策（決定、理由、被否決的方案） |
| [名詞表](../GLOSSARY.md) | 參考 | 命名程式碼、票或文件裡的領域概念 | 新增或改寫領域名詞（先經擁有者確認） |
| [research/](research/) | 參考 | 想看 brief〈查證過的事實〉某條的原始研究與來源 | 新的對外查證 |
| [verify-legacy-on-device skill](../.claude/skills/verify-legacy-on-device/SKILL.md) | 操作指南 | 舊專案緊急修正改了使用者可見行為，要做強制的實機驗證 | 模擬器啟動方式、驗證流程、裝置端限制 |
| [audit/](audit/) | 快照（凍結） | 對照重寫前的現況、功能勾選與效能基準 | 只允許核查更正；新版取代舊版時刪除 |

## 分工

- 單一段程式碼的理由寫在它旁邊（dartdoc 或守著它的測試）；只有程式碼查不到的跨檔契約與地雷才進 `AGENTS.md`。
- 同一條規則只寫在一個地方，除非另一份文件確實有自己的讀者。
- **語言**：新文件一律繁體中文，根目錄 `AGENTS.md` 也是；`lib/AGENTS.md` 描述舊版，維持英文；README 維持英／繁雙語。程式碼識別字、指令、檔名、log 字串、commit message 保留原文。
- `.claude/skills/` 放可被 Claude Code 直接叫用的專案 skill，`.claude/settings.json` 也進版控；`.claude/` 其餘內容、`.agents/` 與 `.codex/` 是本機狀態。
- 審查記錄不進 `docs/`。一輪審計的結論寫進它所描述的檔案、開成 issue，或留在 git 歷史。例外：`docs/audit/` 凍結保留，新版取代舊版時刪除。
