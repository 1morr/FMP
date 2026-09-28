# prior-art — 大型重寫怎麼切成里程碑、怎麼把使用者切過去

- 任務：`09-28-design-milestones`。本檔只收事實與來源，**不決定**里程碑方案。
- 來源規則：repo 內程式碼／文件用 GitHub permalink（**固定 40 字元 SHA**）；部落格、官方公告用原文連結。所有推論標 **推測**。
- 已核對：本檔引用的每個 permalink，其 SHA 與路徑都以 `gh api repos/<owner>/<repo>/commits/<sha>` 與 `contents?ref=<sha>` 驗證存在（2026-09-28）。

---

## 1. 概念：排序策略的詞彙

| 概念 | 一句話 | 來源 |
|---|---|---|
| **Walking skeleton**（走動的骨架） | 先做一個「端到端可跑、但功能極薄」的骨架，把所有層與佈署管線接起來；之後每次都在**已能運作**的系統上加肉。定義出自 Alistair Cockburn《Writing Effective Use Cases》(Addison-Wesley, 2000) 的 "walking skeleton" 用法 | Cockburn, *Writing Effective Use Cases*, 2000（書，無線上 permalink） |
| **Tracer bullets**（曳光彈） | 用一小發「打得到目標」的實作把需求到佈署的整條路徑先打通，再逐發修正準度；與 walking skeleton 常被並用，差別在曳光彈強調**先取得回饋再校準** | Hunt & Thomas, *The Pragmatic Programmer*, 2nd ed. (2019), Topic 12 "Tracer Bullets" |
| **Strangler Fig**（絞殺榕） | 在舊系統旁長出新實作，逐塊把請求導過去，直到舊系統可移除；不需一次替換整個系統 | <https://martinfowler.com/bliki/StranglerFigApplication.html>（2004 初版，2019-04-29 改名為 Strangler Fig） |
| **Branch by Abstraction** | 在程式內建立一層抽象，讓新舊實作可並存切換，避免長期 feature branch；適合「替換內部元件」而非「替換整個 app」 | <https://martinfowler.com/bliki/BranchByAbstraction.html>（2014-01-07） |
| **Feature Toggles** | 用開關控制新舊路徑；Fowler/Hodgson 把它分成 release / experiment / ops / permission 四類，並強調**每種開關有對應的移除時機**（release toggle 上線後應刪） | Pete Hodgson, <https://martinfowler.com/articles/feature-toggles.html>（2017-10-09） |
| **Vertical slice vs layer-by-layer** | 垂直切片＝一次做完某功能的 UI→邏輯→資料；分層＝一層一層做完（先全資料層，再全 UI）。業界實務文獻普遍主張重寫前期用垂直切片（與 walking skeleton／tracer bullet 同源），分層適合**替代方案已存在、只是換實作**的場景 | 無單一權威出處；**推測**（見 §4） |
| **Parity checklist / cut-over gate** | 「切換前必須逐項確認舊功能都對得上」的清單，與「切換當下的放行條件」 | 業界口語，**推測**（見 §4） |

**推測**：Strangler Fig 與 Branch by Abstraction 都預設「同一個 codebase 內新舊並存、可切換」；FMP 的做法（`app/` 與舊專案同 repo 並存、各自獨立建置）更像**同一 repo 內兩個 app 的平行存在**，不是單一服務的絞殺。兩者能借的是「舊系統在切換完成前持續可修」與「切換是一次明確的放行事件」，不是「同進程切流量」。

---

## 2. 案例：成熟專案怎麼做

### 2.1 Immich — 新版時間軸放開關，使用者自行切換

- 事實：Immich 沒有重寫整個 app，而是替換 **timeline + sync + upload** 這條主幹。v1.136.0 的 release discussion 標題為 **"v1.136.0 - 69420 stars release"**，內容含 **"Beta timeline, sync, and upload mechanism"** 與 **"Beta timeline button"**，並在 logo 旁標 beta 符號讓使用者知道自己在用測試版時間軸。
- 來源：<https://github.com/immich-app/immich/discussions/20133>（release v1.136.0 亦存在於該 repo 的 release 清單）。
- 切法：**同一版 App 內並存新舊時間軸**，用一個按鈕切到 beta；行動端使用者不會被強制切換。
- 對 FMP 的相關性（**推測**）：這是「功能級 feature toggle + 使用者自行 opt-in」的樣本；適合**替換單一模組**，不適合「整個 app 重建」。

### 2.2 NewPipe — 在 side branch 重寫，舊版凍結成維護模式，另發 nightly

- 事實：`TeamNewPipe/NewPipe` 有一個 **`refactor` branch**。該分支的 `README.md` 寫明 "We are rewriting large chunks of the codebase"，且說明現行 `master` 的程式庫**進入維護模式、只收 bugfix**。重寫版以 **nightly** 形式發布於 `TeamNewPipe/NewPipe-refactor-nightly`。
- permalink（README）：<https://github.com/TeamNewPipe/NewPipe/blob/52886c235a210fa74806786697bac69f14ec7497/README.md>
- 官方公告：<https://newpipe.net/blog/pinned/announcement/newpipe-0.27.6-rewrite-team-states>
- 切法：**新的獨立分支／獨立 app 身分**，舊版停止功能開發但仍出修正；使用者要拿新版得走 nightly 通道。
- 對 FMP 的相關性（**推測**）：與 ADR 0008「同 repo 新 app」結構最接近；但 NewPipe 的舊版是**凍結**，FMP 的舊版要**繼續修**（`docs/adr/0008-rewrite-as-new-app-in-same-repo.md:52`），這點不同。

### 2.3 Spotube v5 — 一次改掉外掛模型，重寫 plugin 介面

- 事實：Spotube 5.0.0 的 release note 明列這版是 **plugin 化重寫**（把來源抽成外掛）。plugin 介面的程式碼在 `lib/models/metadata/plugin.dart`。
- permalink（plugin.dart）：<https://github.com/KRTirtho/spotube/blob/a8f70f201e23edb8f3d27a60722e4af43b0842fc/lib/models/metadata/plugin.dart>
- 官方 release note：<https://spotube.cc/blog/release-note-v5.0.0>
- 切法：**以一次 versioned release 為切換點**，沒有長期並存的 toggle（release note 是 migrate-notice 風格）。
- 對 FMP 的相關性（**推測**）：FMP 的來源外掛與 Spotube 的 plugin 模型同型（runtime 腳本／介面契約）；可借的是「外掛契約要先凍結、再上線」與「用一次 major release 當切換事件」。

### 2.4 Finamp — 重寫版直接開在預設分支 `redesign`，公開 beta，明確警告下載資料可能不一致

- 事實：`finamp-app/finamp` 的**預設分支是 `redesign`**（不是 `main`）。repo 內有 `beta-release.md`，內容提到設定可能變動，並寫明 "Downloads should be migrated, but since the new download system is completely different, there might be inconsistencies"。
- permalink（beta-release.md）：<https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/beta-release.md>
- 切法：**重寫分支成為預設分支**，用 beta 通道放行；資料遷移（下載）明說可能不一致，不保證無損。
- 對 FMP 的相關性（**推測**）：FMP 的 `legacy_import` 是一次性資料匯入（見 ADR 0008–0012 群），Finamp 的樣本說明**「資料能搬但可能不一致」要事前明講**，而不是承諾無損。

### 2.5 Firefox for Android — Fenix 取代 Fennec，資料遺失明講＋遷移 project board

- 事實：Mozilla 的行動端遷移文件 `Fennec-Migration.md` 直接寫：

  > "Replacing a Fennec (Firefox for Android) installation with Fenix (Firefox Preview) can (and at the time of writing this definitely will) result in DATA LOSS"

  文件同時連到一個**遷移追蹤 project board**（`mozilla-mobile/projects/40`）與一份**有日期的 changelog**。
- permalink（Fennec-Migration.md）：<https://github.com/mozilla-mobile/firefox-android/blob/fe8a71cd70ad5674abe1824fe11dc78372b736c2/fenix/docs/Fennec-Migration.md>
- 切法：**新 app 以新身分上架**，舊 app 使用者不會自動被搬；資料遺失**明文警告**、用 project board 逐項追蹤缺口、changelog 記錄每個時間點。
- 對 FMP 的相關性（**推測**）：這是「換 app 身分、舊使用者手動遷移、事前明講資料風險」的最完整樣本。FMP 的切換條件（`docs/adr/0008-rewrite-as-new-app-in-same-repo.md:53-57`）與此高度可比。

### 2.6 Tusky / Mastodon 客戶端 — 漸進採用，沒有 big-bang 重寫

- 事實：查到的 Tusky（Mastodon Android 客戶端）變更史是**漸進式採用**（逐步導入 Compose、逐步替換畫面），沒有找到「另開分支重寫整個 app 並切換」的公開紀錄。
- 對 FMP 的相關性：作為**反例**——不是每個成功專案都用 big-bang 重寫；漸進替換在某些情境更省風險。

### 2.7 AppFlowy — 查不到「整 app 重寫」的公開里程碑紀錄

- 查到的 AppFlowy 資料是功能迭代與版本發布，**沒有**找到「重寫整個 app 並切換使用者」的公開文件。列為查不到。

---

## 3. 橫向對照（決定排序策略時要看的維度）

| 維度 | Immich | NewPipe | Spotube v5 | Finamp | Firefox Fenix |
|---|---|---|---|---|---|
| 重寫範圍 | 單一模組（timeline+sync+upload） | 整個 app（large chunks） | 外掛模型 | 整個 app（redesign） | 整個 app |
| 排序策略 | 模組級垂直切片 | 另起 app（vertical） | 一次 release | 另起分支（預設分支） | 另起 app／新身分 |
| 使用者切換方式 | App 內按鈕 opt-in beta | nightly 通道 | major release | beta 通道 | 新 app 上架，手動遷移 |
| 新舊並存 | 是（同一 App 內） | 是（兩份 app／兩條通道） | 否 | 是（兩條通道） | 否（舊 Fennec 不更新） |
| 資料 migration | 不涉及（後端同一份） | 不涉及 | 不涉及 | **明說可能不一致** | **明說會資料遺失** |
| 舊系統切換後狀態 | 舊路徑移除 | 舊版維護模式、只收 bugfix | — | 舊版被 redesign 取代 | Fennec 停止 |
| 明確 cut-over 事件 | 無（長期 toggle） | 無（長期並行） | 有（5.0.0） | 有（beta→stable） | 有（Fenix 上架） |

**推測**：上表沒有「重寫者一開始就把里程碑編號寫成公開清單」的樣本；公開可見的都是**切換機制**（toggle／通道／新身分）與**風險聲明**，不是里程碑目錄。里程碑清單在這些專案裡多為內部規劃（issue／project board），不保證對外可見。

---

## 4. 查不到／推測

- **查不到**：Immich、NewPipe、Spotube、Finamp 任一專案的**完整里程碑清單**（含編號與每階段驗收條件）的公開文件。查到的是切換機制與 release note。
- **查不到**：AppFlowy 的整 app 重寫里程碑紀錄。
- **查不到**：Tusky 有 big-bang 重寫；查到的是漸進採用 Compose。
- **查不到**：`vertical slice vs layer-by-layer` 與 `parity checklist / cut-over gate` 的**權威原始出處**。前者是實務共識用語、後兩者是業界口語；本檔標為推測。
- **推測**：Strangler Fig／Branch by Abstraction 不直接適用於「同 repo 兩個獨立 app 並存」的 FMP 情境；能借的是「舊系統切換前持續可修」與「切換是一次明確放行」兩個性質。
- **推測**：NewPipe 是最接近 FMP 結構的樣本（同 repo、新 app 身分、舊版維護模式），但 NewPipe 舊版停止功能開發、FMP 舊版要繼續修（ADR 0008 :52），兩者對「資源怎麼分」的答案不同。
