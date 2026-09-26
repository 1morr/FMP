# 設計：文檔結構與 ADR 機制

## 1. 目標文檔地圖

判準：一種資訊只有一個家；放哪裡由「誰讀、什麼時候讀」決定。

| 位置 | 讀者 | 放什麼 | 不放什麼 | 採用的慣例 |
|---|---|---|---|---|
| `README.md`（英）＋`README.zh-Hant.md` | 使用者 | 產品介紹、截圖、下載、平台支援 | 開發細節 | 維持現況雙語（App 本身支援英文） |
| `docs/*.md` | 人類開發者 | 操作指南（建置、發版、除錯）、參考（設定、產物命名）、說明（架構為什麼這樣分） | 單一段程式碼的理由（寫在 dartdoc）、agent 規則 | Diátaxis；不預建四個空資料夾，`docs/README.md` 的地圖表加一欄標每份文件的類型 |
| `docs/adr/NNNN-*.md` | 人類與 agent | 跨模組決定、理由、被否決的方案、怎麼確認有被遵守 | 實作步驟、任務進度 | MADR（見 §3） |
| `AGENTS.md` | AI agent | 頂層目錄地圖（≤10 列）、驗證指令表、邊界規則（每條附閘門）、程式碼查不到的地雷 | 能從程式碼幾秒查到的東西、某一層的寫法細節 | agents.md；使用者全域規則 |
| `.trellis/spec/<layer>/` | AI agent（實作該層時） | 這一層的程式碼怎麼寫、範例與反例 | 歷史、決策理由（連到 ADR）、有閘門的規則本文（連到 AGENTS.md） | 使用者在 prd 定的分工 |
| `.trellis/tasks/*/design.md` | 執行該任務的人與 agent | 這次任務怎麼做 | 長期規則 | 隨任務歸檔 |
| `.claude/skills/<name>/` | AI agent | 可被叫用的專案操作流程（例如 verify-on-device） | 規則 | Claude Code skill |
| `docs/audit/` | 使用者 | 重寫前的現況快照與驗收基準 | 新內容 | 凍結；最後一個里程碑刪除（§5） |

語言：以上全部繁中；程式碼識別字、指令、檔名、log 字串、commit message 保留原文。README 例外，維持英／繁雙語。

## 2. 規則放哪裡

| 資訊 | 唯一位置 | 其他地方怎麼提 |
|---|---|---|
| 有閘門的邊界規則 | `AGENTS.md` | spec 只放連結 |
| 規則為什麼存在 | 對應的 ADR | AGENTS.md 一句話＋ADR 編號 |
| 某層寫法慣例 | `.trellis/spec/<layer>/` | — |
| 驗證要跑什麼 | `AGENTS.md` 驗證表 | Trellis 子代理定義回指 AGENTS.md，不複寫 |
| 建置／發版步驟 | `docs/` | AGENTS.md 只放指令 |
| 單一段程式碼的理由 | 旁邊的 dartdoc 或守它的測試 | — |

AGENTS.md 裡每一條規則都要能回答「哪個 test 或 lint 守著它」；答不出來的，要嘛補閘門，要嘛刪掉（使用者全域規則）。

## 3. ADR 機制

- 位置維持 `docs/adr/`（MADR 預設是 `docs/decisions/`，但既有引用都指向 `adr/`，改名沒有好處）。
- 檔名 `NNNN-用英文小寫連字號的標題.md`，從 **0008** 接續，編號不重用。
- 範本 `docs/adr/template.md`，章節（依 MADR 精簡）：
  - 標題（問題＋選擇）
  - 狀態、日期
  - 背景與問題
  - 考慮過的選項（每個一段：做法、優點、缺點）
  - 決定與理由（寫明採用了誰的慣例）
  - 後果（好的、壞的、之後要注意的）
  - 如何確認：守著這個決定的 test／lint／review 點（對應 MADR 的 Confirmation）
- 什麼時候寫：階段二每個設計項目定案時，重大決定各一份（預期至少：重寫策略、平台層、資料層與相容、網路與帳號、錯誤模型、音源插件、測試策略、播放核心、下載與權限、發版與更新）。一個項目可以有多份，也可以沒有（例如 Toast 可能只進 spec）。
- 取代舊 ADR：新 ADR 推翻或讓舊 ADR 不再適用時，**同一個 commit**：刪除舊檔、改掉所有引用、`git grep` 確認沒有殘留（`.trellis/tasks/archive/` 是歷史，不改）。新 ADR 在「背景」裡寫明它取代了哪一份、原本決定了什麼。

> 與 MADR 的差異：MADR 以狀態「superseded by」保留舊紀錄；這裡依使用者要求直接刪除，歷史靠 git。

## 4. 舊 ADR 與 CONTEXT.md 的去留

| 舊 ADR | 處理 | 在哪一項定案 |
|---|---|---|
| 0001 字串音源 id ＋ 每源設定清單 | 字串 id 的部分確認沿用；每源設定清單由第 6／18 項的新設計取代。第 1 項寫音源插件 ADR 時把字串 id 併進去，0001 同時刪除 | 1、6、18 |
| 0002 Isar 只在 repository 層 | 第 6 項決定資料層後：換庫則刪除；原則（資料庫只在資料層）寫進新的資料層 ADR | 6 |
| 0003 兩個音訊後端 | 第 13 項重新決定，新 ADR 取代 | 13 |
| 0004 Android 所有檔案存取權 | 第 11 項重新決定，新 ADR 取代 | 11 |
| 0005 曲目識別鍵包含 cid | 確認沿用（也是舊資料遷移要用的格式）；第 6 項視需要改寫 | 6 |
| 0006 Release 自動發布 | 確認沿用；第 19 項補上「發佈說明由 CHANGELOG 產生」後改寫 | 19 |
| 0007 Isar 停在 v3 | 隨 0002 一起處理 | 6 |

`CONTEXT.md`：5 個術語描述的原則（憑證只用在解析串流、媒體位元組請求不帶憑證、「用登入狀態」開關的範圍）併進第 12 項的 ADR 與 spec，術語依新設計命名；階段三刪除 `CONTEXT.md` 並改掉 `.trellis/spec/` 裡 7 處引用。

## 5. `docs/audit/` 的生命週期

重寫期間凍結（只允許核查更正），是完成定義的基準（`features.md` 勾「保留」的功能、`perf-baseline.md` 的效能）。最後一個里程碑的 PR 刪除整個目錄，並把 `docs/README.md`「審查記錄不進 `docs/`」恢復成沒有例外。

## 6. 階段三要處理的現況衝突

來自 `docs/audit/engineering.md` §8.2、§9：

- mattpocock 殘留：`docs/agents/` 三檔、AGENTS.md「Agent skills」段、`docs/README.md:21,23`；「issue 用繁中撰寫」搬一句進 AGENTS.md。
- AGENTS.md 的 Trellis 自動區塊提到不存在的 `.codex/`、被 gitignore 的 `.agents/`；本機 `.agents/skills/verify-on-device/` 是過期副本。
- check 子代理有三份定義（`.claude/agents/trellis-check.md`、`.trellis/agents/check.md`、`.claude/skills/trellis-check/`）。
- Trellis 文件描述 journal commit，但設定已關閉。
- AGENTS.md 對「等待慣例」的閘門範圍說得比實際寬。
- `.trellis/workflow.md` 3.4「不 push」與使用者全域「自己的 repo 直接 push」的層級差異：repo 內不衝突，保留 Trellis 原文，不在 repo 內處理。

`.trellis/`、`.claude/` 裡由 Trellis 產生的檔案，改動前先確認 `trellis update` 會不會覆蓋（AGENTS.md「Trellis」段已記錄要保留的客製）。
