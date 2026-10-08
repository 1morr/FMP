# 里程碑清單（ADR 0026）

> 每完成一個里程碑或平台任務，就更新它的「狀態」與驗收勾選。
> 範圍若在開工時要大改，先改這份清單並寫明原因。
> 「§7」「§8」指 `phase2-plan.md` 的第 7 節（第一個里程碑的必要驗證）與第 8 節（延後的實測）。

| # | 里程碑 | 依賴 | 狀態 |
|---|---|---|---|
| M1 | 骨架＋曳光彈 | — | 完成（2026-10-01，#173–#194；`archive/2026-10/09-28-m1-skeleton-tracer`） |
| M2 | 完整播放 | M1 | 完成（2026-10-08，#196–#219；`archive/2026-10/10-01-m2-full-playback`） |
| M3a | 三音源與帳號 | M2 | 未開始（任務 `10-08-m3-sources-accounts-devtools`，PR 1–10） |
| M3b | 開發工具、排程器、電台、Mix、分 P | M3a | 未開始（同上，PR 11–21） |
| M4 | 音樂庫與同步 | M3b | 未開始 |
| M5 | 舊資料匯入 | M4 | 未開始 |
| M6 | 下載 | M5 | 未開始 |
| M7 | 歌詞 | M5 | 未開始 |
| M8 | 桌面整合 | M2 | 未開始 |
| M9 | 發版、更新與切換 | M1–M8 | 未開始 |
| L | Linux 平台 | M1、Mac 到貨 | 已開任務，延後到 Mac 上與 macOS、iOS 一起做（`10-01-linux-platform`） |
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
- **之後**：開 Linux 平台任務（已開：`10-01-linux-platform`；2026-10-01 改為延後到 Mac 上做，先做 M2）。

## M2 完整播放

- **做完**：以單一音源像舊版一樣日常聽歌。
- **範圍**：
  - 完整 `QueueModel` 與 `RecoveryPolicy`（ADR 0018）；
  - 播放頁方案 B、播放列三段、App 內快捷鍵全表、焦點三區（ADR 0024）；
  - 系統媒體控制；速度、音量、輸出裝置（E19）；播放歷史（E15）；
  - 統一快取庫與離線狀態（ADR 0016）；
  - 啟動維護清單（ADR 0017），含 log 保留 7 天（ADR 0025）；
  - 2026-10-01 規劃時擁有者決定加入：媒體 client 與封面磁碟快取（原屬 M6）、「歷史」導覽項、右側「正在播放」面板、Android 返回鍵；`tracks` 表提前（原屬 M4）。
  - 移出：背景排程器到 M3；`mix`、`live` 模式到 M3；已下載曲目的離線行為到 M6。明細見 `10-01-m2-full-playback/design.md` §1。
- **驗收**（證據：M2 任務 `research/m2-acceptance.md`、`research/m2-adr-tests.md`）：
  - [x] 兩平台端到端操作（驗收時抓到並修好三個 bug，見證據檔「發現與修正」）
  - [x] ADR 0016、0018 的測試，與啟動維護清單、log 保留 7 天的測試（範圍見 M2 `design.md` §12 第 3 條）

## M3a 三音源與帳號

- **做完**：三個音源都能搜尋、播放、登入。
- **任務**：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（PR 1–10；規劃時擁有者決定把 M3 拆成 M3a、M3b，2026-10-08）。
- **範圍**：
  - YouTube、網易雲插件；宿主 API 的 `idempotent`、`authHeaders`、`login`（ADR 0028、0029）；
  - 帳號與 `CredentialStore`、`AuthRequirement`、三種登入方式（QR、App 內網頁登入、貼上 cookie）、失效與刷新（ADR 0012、0029，E6）；
  - `1morr/fmp-plugins` repo、CI、`index.json`；插件生命週期與插件頁；首次啟動引導（ADR 0014、0030）；
  - 設定頁的「帳號」「插件」區塊。
- **驗收**：
  - [ ] 兩平台端到端操作
  - [ ] ADR 0012、0013、0014、0015 §決定 6、0016、0028、0029、0030 的測試（逐項對到任務的 `research/m3-adr-tests.md`）
  - [ ] §8：YouTube App 內網頁登入（ADR 0012）

## M3b 開發工具、排程器、電台、Mix、分 P

- **做完**：Debug 頁與插件開發工具可用；電台、Mix、B 站分 P 都能用。
- **任務**：同 M3a（PR 11–21）。
- **範圍**：
  - Debug 頁與開發者模式、診斷包、插件開發工具與健康檢查（ADR 0025、0015 §7）；設定「關於」區塊的版本列（開發者模式入口；其餘內容 M9）；
  - 錯誤詳細頁、GitHub 回報、`.github/ISSUE_TEMPLATE/bug_report.yml`（ADR 0023）；
  - 背景排程器（ADR 0017）與 lint `fmp_periodic_timer_owner`，第一個工作是電台狀態（2026-10-01 從 M2 移來）；
  - 電台直播（E12）、Mix（E13）、`QueueModel` 的 `mix`、`live` 模式（ADR 0018、0031）；
  - B 站分 P（E2）、曲目詳細 `trackDetail`（ADR 0028）。
- **驗收**：
  - [ ] 兩平台端到端操作
  - [ ] ADR 0017 排程器的測試與 lint `fmp_periodic_timer_owner` 的雙向變異測試
  - [ ] ADR 0015 §決定 7、0016、0018、0023 §決定 4、0025、0028、0031 的測試（逐項對到任務的 `research/m3-adr-tests.md`）
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

- **範圍**：ADR 0020 全部（E8）；匯入舊下載紀錄；ADR 0016 §決定 7 的已下載曲目離線行為。媒體 client 已在 M2 建好（2026-10-01）。
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

- **Linux**（2026-10-01 擁有者決定：Mac 到貨後與 macOS、iOS 一起在 Mac 上做，M2 先行；ADR 0026 §決定 4 的修訂）：
  - 驗收的虛擬機與 X11／Wayland 的做法在該任務決定（原定 Windows 上的 VMware Workstation Pro）。
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
