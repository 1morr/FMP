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

## 待決定（一次問一題）

1. 里程碑的切法與順序，包括舊資料匯入、Debug 頁、插件庫放在哪一步。
2. 里程碑與 PR 的對應：里程碑底下是否再分 PR 級的子任務。
3. 切換放行條件的細節：勾選來源改指 `questions.md`、效能重量方式、擁有者試用多久。

## 驗收條件

- [ ] 待決定項都有擁有者的答覆。
- [ ] 產出 ADR 0026（里程碑結構與切換放行條件）與里程碑清單。
- [ ] 清單中每個里程碑都有：範圍、依賴、驗收，以及併入的 `phase2-plan` §7／§8 項目。
- [ ] ADR 0008 與 parent prd 的「`features.md` 勾保留」改指實際的勾選來源。
- [ ] `phase2-plan.md` §3 第 20 列 ✅；§10 交接改為階段三。
