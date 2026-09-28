# 重寫里程碑定稿

## 目標

階段二第 7 項的定稿部分（parent prd 第 7 項、`phase2-plan.md` §3 第 20 列）。
把 ADR 0008–0025 拆成可以各自驗證的里程碑，並滿足兩個條件：
- 每個里程碑結束時，`app/` 都能正常運作；
- 每個 PR 大小都在擁有者能 review 的範圍內。

同時定下三件事：
- 切換到新 App 的放行條件；
- 擁有者何時開始用新 App 試用；
- 追蹤方式。

高層策略已由 ADR 0008 決定：同 repo 的 `app/`、搬運葉節點、主幹開發、舊版可緊急修正，第一個里程碑是 tracer bullet。

## 現況（`research/current-state.md`、`research/repo-mechanics.md`，已抽查）

- **里程碑沒有編號**：全 repo 沒有里程碑清單，只有描述性的指稱：
  - 「第一個里程碑」出現在 8 份 ADR；
  - 另有「加入下載的里程碑」「加入 Debug 頁的里程碑」「切換前」這類說法。
- **第一個里程碑已累積 10 份 ADR 的必要驗證**（`phase2-plan.md` §7）。ADR 0014 自承「第一個里程碑變重」。
- **延後的實測**（`phase2-plan.md` §8）：各自掛在「加入 X 的里程碑」或平台任務。
- **功能凍結的例外**（`phase2-plan.md` §9）：
  - 腳本插件、歌詞三項；
  - `1morr/fmp-plugins` repo、插件頁、首次啟動引導「排入里程碑規劃，第一個里程碑不需要」。
- **切換條件的出處不一致**：
  - ADR 0008 §決定 5（`:53`）與 parent prd 完成定義（`:203`）都寫「`features.md` 中勾『保留』的功能」；
  - 但 `features.md` 沒有勾選欄，實際勾選在 `questions.md`。E1–E17 保留（`:237-258`），E18–E20 在後續 ADR 已處理（0024 刪除 E20）。
- **其他仍未落點的事**：
  - ADR 0011：「各組設定的欄位清單在里程碑中依 `docs/audit/data.md` §7 定案」；
  - ADR 0017 的啟動維護清單要在哪個里程碑實作。
- **平台順序**（ADR 0009 §決定 9、`questions.md` A1）：
  - Android、Windows 從第一個里程碑起全面驗證；
  - Linux、macOS、iOS 從第一個里程碑起在 CI 編譯；
  - Linux 在第一個里程碑後開平台任務（虛擬機）；macOS、iOS 有設備後開；
  - 實機驗證完才發佈。
- **CI**：
  - `ci.yml` 只有舊專案的 3 個 job，約 17–23 分鐘，刻意不加 path filter；
  - ADR 0015 §9 的 `dorny/paths-filter` 切分與 5 平台矩陣都還沒實作。
- **追蹤**：
  - Trellis 的 parent／child 不是依賴系統，先後順序要寫在 child 的 prd／implement（`workflow.md:173`）；
  - repo 沒有 GitHub Milestones（`[]`）、沒有 issue 範本。
- **工具鏈**：舊專案與效能基準都是 Flutter 3.47.1／Dart 3.13.1；目前 stable 是 3.47.5／Dart 3.13.4。
- **效能基準**（`perf-baseline.md`）：
  - 冷啟動首幀：Android 1239ms、Windows 1731ms；
  - 記憶體：Android PSS 約 179MB、Windows Working Set 約 300MB；
  - 另有長列表捲動的幀時間。

## 研究結論（`research/prior-art.md`）

- **概念**：
  - walking skeleton（Cockburn）與 tracer bullet（Pragmatic Programmer）都主張：先打通端到端最薄的一條，再在能運作的系統上逐層加能力。
  - Strangler Fig 與 Branch by Abstraction 適用於同一個 codebase 內換元件，不直接適用於 FMP 這種同 repo 兩個 App 的情形。
- **案例**：
  - NewPipe：`refactor` 分支、nightly 通道，舊版只收修正。結構最接近 FMP。
  - Finamp：重寫分支成為預設分支，走 beta 通道，並明說下載資料遷移可能不一致。
  - Firefox Fenix：新 App 上架，事先明文警告資料遺失，用 project board 追蹤缺口。
  - Spotube v5：以一次 major 版本當切換點。
  - Immich：同一 App 內用開關選擇 beta 時間軸。
- **共同點**：公開可見的都是切換機制與風險聲明，查不到任何一個專案的完整里程碑清單。

## 已決定

1. **里程碑的切法與順序**（2026-09-28，擁有者「按你建議」）：以縱向切片排序；每個新增資料表的里程碑，同時補上那張表的舊資料匯入。

   | # | 里程碑 | 範圍 |
   |---|---|---|
   | M1 | 骨架＋曳光彈 | Android、Windows 能搜 B 站並播放；接上 CI 切分、lint、log 與遮蔽、drift、網路層、錯誤模型、Toast、token、JS 執行環境＋B 站插件；限時的 YouTube.js 可行性驗證 |
   | M2 | 完整播放 | 佇列、播放頁 B、播放列、App 內快捷鍵、系統媒體控制、速度／音量／輸出裝置、播放歷史、快取、背景排程器 |
   | M3 | 三音源、帳號與開發工具 | YouTube、網易雲插件；登入；B 站分 P、Mix、電台直播；`1morr/fmp-plugins`、插件頁、首次啟動引導；Debug 頁與插件開發工具 |
   | M4 | 音樂庫與同步 | 本機歌單、匯入平台歌單並刷新、Spotify／QQ 匹配、遠端歌單編輯、首頁排行、新格式的備份與還原 |
   | M5 | 舊資料匯入 | 匯入歌單、曲目、歷史、設定、帳號、舊備份檔；之後擁有者以 dev flavor＋真實資料副本日常試用 |
   | M6 | 下載 | 下載與權限，並匯入舊下載紀錄 |
   | M7 | 歌詞 | 多源與 AI 插件、逐字、桌面歌詞、Android 懸浮，並匯入舊歌詞配對 |
   | M8 | 桌面整合 | 托盤、全域快捷鍵、開機自啟、單一實例 |
   | M9 | 發版、更新與切換 | 應用內更新、release-please、舊更新器相容、效能重量、真實資料副本完整匯入、身分比對，最後切換 PR |

   - **Debug 頁放 M3**：寫 YouTube、網易雲插件時要用插件開發工具與網路紀錄。
   - **舊資料匯入放 M5**：音樂庫的資料表到 M4 才齊，之後擁有者可以用真實資料試用。
   - **插件庫放 M3**：有三個官方插件後才需要插件目錄。
   - **平台任務**：
     - **Linux**：M1 之後開。驗收在 VMware Workstation Pro 的 Ubuntu 桌面虛擬機，X11、Wayland 各測一次；日常開發用 WSL2。之後每個里程碑在虛擬機跑一次冒煙測試。
       - 不用 WSLg 驗收的原因：它是 Weston 加 RDP，沒有托盤（wslg #532）、鑰匙圈預設沒在跑，桌面歌詞的置頂與穿透也測不準。
     - **macOS、iOS**：Mac 預計下個月到貨。到貨前只靠 GitHub macOS runner 編譯與 iOS 模擬器測試（ADR 0009）。到貨後開平台任務；iOS 要不要實機、要不要付費帳號，屆時再問。

2. **里程碑與 PR 的對應**（2026-09-28，擁有者「按你建議」）：
   - **里程碑任務**：fmp-rewrite 的 child，例 `m1-tracer-bullet`。
     - 開工時走 brainstorm，prd／design／implement 核准一次；
     - implement 列出 PR 子任務與先後順序；
     - 驗收＝端到端實際操作，加上併入的 `phase2-plan` §7／§8 實測。
   - **PR 子任務**：里程碑任務的 child，例 `m1-log-facade`。
     - 一個分支、一個 PR；
     - 只寫簡短的 prd（做什麼、驗收）；
     - PR 描述附 review 指南（改了什麼、為什麼、看哪幾個檔、怎麼實際驗證）；
     - 合進 `main` 後 `app/` 可編譯、測試全綠。
   - PR 子任務在里程碑已核准的範圍內直接做，遇到未定的事才問。
   - 追蹤只用 Trellis 任務樹，不開 GitHub Milestones／Projects。
   - 此決定調和 parent prd「每個里程碑是 child task」與「每個 child task 一個 PR」兩條規則。

## 待決定（一次問一題）

3. 切換放行條件的細節：勾選來源改指 `questions.md`、效能重量方式、擁有者試用多久。

## 驗收條件

- [ ] 待決定項都有擁有者的答覆。
- [ ] 產出 ADR 0026（里程碑結構與切換放行條件）與里程碑清單。
- [ ] 清單中每個里程碑都有：範圍、依賴、驗收，以及併入的 `phase2-plan` §7／§8 項目。
- [ ] ADR 0008 與 parent prd 的「`features.md` 勾保留」改指實際的勾選來源。
- [ ] `phase2-plan.md` §3 第 20 列 ✅；§10 交接改為階段三。
