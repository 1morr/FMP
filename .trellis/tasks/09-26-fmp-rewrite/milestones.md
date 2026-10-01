# 里程碑清單（ADR 0026）

> 每完成一個里程碑或平台任務，就更新它的「狀態」與驗收勾選。
> 範圍若在開工時要大改，先改這份清單並寫明原因。
> 「§7」「§8」指 `phase2-plan.md` 的第 7 節（第一個里程碑的必要驗證）與第 8 節（延後的實測）。

| # | 里程碑 | 依賴 | 狀態 |
|---|---|---|---|
| M1 | 骨架＋曳光彈 | — | 完成（2026-10-01，#173–#194；`archive/2026-10/09-28-m1-skeleton-tracer`） |
| M2 | 完整播放 | M1 | 未開始 |
| M3 | 三音源、帳號與開發工具 | M2 | 未開始 |
| M4 | 音樂庫與同步 | M3 | 未開始 |
| M5 | 舊資料匯入 | M4 | 未開始 |
| M6 | 下載 | M5 | 未開始 |
| M7 | 歌詞 | M5 | 未開始 |
| M8 | 桌面整合 | M2 | 未開始 |
| M9 | 發版、更新與切換 | M1–M8 | 未開始 |
| L | Linux 平台 | M1 | 已開任務，未規劃（`10-01-linux-platform`） |
| Mac | macOS 平台 | Mac 到貨 | 未開始 |
| iOS | iOS 平台 | Mac 到貨 | 未開始 |

- M6、M7 互不依賴，可以對調。
- M8 放在 M7 之後，是因為它不擋試用。

## M1 骨架＋曳光彈

- **做完**：Android、Windows 上能搜尋 B 站並連續播放兩首。
- **範圍**：
  - `app/` 新專案，Flutter 用當時的 stable；`app/AGENTS.md`；flavor dev／prod 與 App 身分；單一實例鎖（ADR 0008、0015）。
  - `fmp_lints` 與接線哨兵；CI 以 `dorny/paths-filter` 切分、五平台編譯、`always()` 彙總（ADR 0015 §9）。
  - 平台層骨架與能力宣告（ADR 0009）。
  - drift 最小 schema 與快照（ADR 0010）。
  - log 門面、遮蔽函式、log 檔（ADR 0011）。
  - 網路層（不含登入，ADR 0012）、錯誤模型（ADR 0013）。
  - JS 執行環境、宿主 API 最小集、以「從檔案安裝」載入 B 站插件（ADR 0014）。
  - 播放核心最小集：兩個後端、兩首的佇列、前瞻交接（ADR 0018）。
  - `ToastHost` 與 `Toaster`（ADR 0023）。
  - token、斷點、字型、slang 三語言骨架、播放快捷鍵（ADR 0024）。
  - `app/` 發版 workflow 以 release-please dry-run 驗證（ADR 0022）。擁有者決定 4 改為在私人 sandbox 完整跑一次（#193）。
- **限時探針**：YouTube.js 可行性。失敗就在 M3 以 Dart 實作 YouTube（ADR 0014）。
- **驗收**（證據：M1 任務 `research/m1-acceptance.md`）：
  - [x] 兩平台端到端操作
  - [x] §7 全部項目
- **之後**：開 Linux 平台任務（已開：`10-01-linux-platform`）。

## M2 完整播放

- **做完**：以單一音源像舊版一樣日常聽歌。
- **範圍**：
  - 完整 `QueueModel` 與 `RecoveryPolicy`（ADR 0018）；
  - 播放頁方案 B、播放列三段、App 內快捷鍵全表、焦點三區（ADR 0024）；
  - 系統媒體控制；速度、音量、輸出裝置（E19）；播放歷史（E15）；
  - 統一快取庫與離線狀態（ADR 0016）；
  - 背景排程器與啟動維護清單（ADR 0017），含 log 保留 7 天（ADR 0025）。
- **驗收**：
  - [ ] 兩平台端到端操作
  - [ ] ADR 0016、0017、0018 的測試

## M3 三音源、帳號與開發工具

- **做完**：三個音源都能搜尋、播放、登入。
- **範圍**：
  - YouTube、網易雲插件；B 站分 P（E2）、Mix（E13）、電台直播（E12）；
  - 帳號與 `CredentialStore`、`AuthRequirement`（ADR 0012，E6）；
  - `1morr/fmp-plugins` repo、CI、`index.json`；插件頁；首次啟動引導（ADR 0014）；
  - Debug 頁與插件開發工具（ADR 0025、0015 §7）；錯誤詳細頁、GitHub 回報、`.github/ISSUE_TEMPLATE/bug_report.yml`（ADR 0023）。
- **驗收**：
  - [ ] 兩平台端到端操作
  - [ ] §8：YouTube App 內網頁登入（ADR 0012）
  - [ ] §8：加入 Debug 頁的里程碑實測（ADR 0025）

## M4 音樂庫與同步

- **做完**：建歌單、匯入並刷新平台歌單、匯入 Spotify／QQ 歌單。
- **範圍**：
  - 關聯表與孤兒清理（ADR 0019）；本機歌單（E3）；
  - 匯入與刷新（E4）；僅元資料來源的匹配（E5）；遠端歌單編輯（E7）；
  - 首頁排行（E14）；新格式的備份與還原（E16）。
- **驗收**：
  - [ ] 兩平台端到端操作
  - [ ] `opencc` native assets 在各平台建置（ADR 0019）

## M5 舊資料匯入

- **做完**：首次啟動自動匯入舊版的歌單、曲目、歷史、設定、帳號；也能匯入舊備份檔。
- **範圍**：`legacy_import`（ADR 0010）：先寫暫存庫、驗證後才換上；錯誤頁；「刪除舊版資料」。
- **驗收**：
  - [ ] 以擁有者的真實資料副本完整匯入，比對筆數
  - [ ] 擁有者開始以 dev flavor＋真實資料副本日常試用

## M6 下載

- **範圍**：ADR 0020 全部（E8）；匯入舊下載紀錄。
- **驗收**：
  - [ ] 兩平台端到端操作
  - [ ] §8：加入下載的里程碑實測（ADR 0020）

## M7 歌詞

- **範圍**：
  - ADR 0021 全部（E9–E11）；
  - 官方 AI 插件 `openai-compatible`、`system-one`；
  - 舊歌詞配對以 `manual` 匯入。
- **驗收**：
  - [ ] 兩平台端到端操作
  - [ ] §8：桌面歌詞、Android 懸浮歌詞、逐字的里程碑實測（ADR 0021）

## M8 桌面整合

- **範圍**：托盤、全域快捷鍵、開機自啟、關閉縮到托盤（E18）；設定頁「鍵盤快捷鍵」列出兩組（ADR 0024）。
- **驗收**：
  - [ ] Windows 端到端操作
  - [ ] 錄製全域快捷鍵時，與 App 內快捷鍵衝突會提示

## M9 發版、更新與切換

- **範圍**：
  - 應用內更新（ADR 0022，E17）；
  - `docs/user-guide.md` 與關於頁（ADR 0024）；
  - 切換 PR（ADR 0008 §決定 5）：刪除根目錄舊專案、`docs/audit/`、ADR 0001–0007；`release.yml`、`ci.yml`、`orca.yaml`、`tool/release/` 改指向 `app/`。
- **驗收**（ADR 0026 §決定 5）：
  - [ ] 功能清單 E1–E17 與各 ADR 行為逐項通過
  - [ ] 舊版與新版同機各量 5 次，新版每項不差超過 5%
  - [ ] 真實資料副本完整匯入，並比對筆數
  - [ ] 從 v1.11.0 實際升級：Android、Windows 安裝版、Windows 免安裝版（§8，ADR 0022）
  - [ ] Windows 自行下載的安裝檔不帶 Mark of the Web
  - [ ] App 身分比對（ADR 0008）
  - [ ] 試用 2 週，沒有未解決的阻擋性 bug

## 平台任務

- **Linux**（M1 之後）：
  - 驗收在 VMware Workstation Pro 的 Ubuntu LTS 桌面虛擬機，X11 與 Wayland 各一次；日常開發用 WSL2。
  - 之後每個里程碑在虛擬機跑一次冒煙測試。
  - [ ] §8：沒有 keyring 時的 secure storage（ADR 0012）
  - [ ] §8：X11／Wayland 桌面歌詞（ADR 0021）
  - [ ] §8：AppImage 改名替換（ADR 0022）
- **macOS**（Mac 到貨後）：
  - [ ] §8：AVPlayer 對 B 站 DASH 與直播 HLS（ADR 0018）
  - [ ] §8：桌面歌詞（ADR 0021）
  - [ ] §8：更新不帶 quarantine（ADR 0022）
- **iOS**（Mac 到貨後，實機與付費帳號在該任務決定）：
  - [ ] §8：AVPlayer 對 B 站 DASH 與直播 HLS（ADR 0018）
  - [ ] §8：Live Activity 本機逐行更新（ADR 0021）
- 各平台實機驗證完才發佈（ADR 0009）。
