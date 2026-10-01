# M1 骨架＋曳光彈

## 目標

在 `app/` 建出新專案的骨架，接上所有基礎建設。做完時，Android 與 Windows 上能搜尋 B 站並連續播放兩首（ADR 0026）。

## 背景

- 範圍與驗收的來源：
  - `../09-26-fmp-rewrite/milestones.md` § M1；
  - `../09-26-fmp-rewrite/phase2-plan.md` §7（M1 的必要驗證）。
  - 行為以 ADR 0008–0027 為準。
- 研究（已抽查）：
  - `research/m1-scope-digest.md`：各 ADR 的 M1 範圍、相依順序、19 項未定之處；
  - `research/m1-tooling-facts.md`：2026-09-28 的套件版本、Trellis `packages:` 機制。
- 結構（ADR 0026 §決定 1）：
  - 本任務是里程碑任務，擁有者核准一次 prd／design／implement；
  - 每個 PR 是本任務的 child，一個分支、一個 PR，合進 `main`。
- `app/` 還不存在。
- ADR 全在 `docs/audit`（draft PR #173），還沒進 `main`。#173 只改文件與 `.trellis/`，所以 M1 第一步是合併它。
- 舊內容會誤導在 `app/` 工作的 AI：
  - 根目錄 AGENTS.md 全是舊專案規則，每個 session 都會載入。
  - 舊 spec 會被 Trellis 注入。即使宣告了 `packages:`，`session-start.py:680-682` 仍會先把扁平的 `.trellis/spec/<layer>/index.md` 全部加入，之後才做 package 篩選（`:685`）。
  - `trellis-check.md:86` 寫死扁平 spec 路徑與「AGENTS.md § Verification」。
- 與 ADR 或現況不符、M1 要處理的事實：
  - Flutter stable 是 3.47.5；本機與舊專案 CI 是 3.47.1。
  - `window_manager` 0.5.2 於 2026-07 發佈，ADR 0021「0.5.x 已停止維護」有誤。
  - `flutter analyze` 的插件診斷 issue 是 flutter/flutter#187999，ADR 0015 引用的 #193203 已以重複關閉。
  - release-please-action v5 沒有 dry-run。
  - `flutter_js` 在 `flutter test` 內要先建置桌面產物，並把 QuickJS 原生庫放進 `PATH`。
  - `main` 的 ruleset 沒有必要檢查。

## 擁有者的決定

1. **指令檔分家**（2026-09-28）：M1 第 1 個 PR 一次做完，那時 `app/` 還沒有程式碼。
   - 根目錄 `AGENTS.md` 縮成共用部分，並寫明「改舊專案先讀 `lib/AGENTS.md`」。
   - 舊規則原封搬到 `lib/AGENTS.md`；`app/AGENTS.md` 用繁中。
   - 舊 spec 搬到 `.trellis/spec/legacy/`，`app/` 的 spec 在 `.trellis/spec/app/`，並宣告 `packages:`。
   - 舊 skill 改名 `verify-legacy-on-device`；`verify-on-device` 的名字給 `app/` 的新版。
2. **M1 的畫面**（2026-09-28）：照 ADR 0024 蓋真正的外殼，只放能用的東西。
   - 導覽「搜尋」「設定」兩項，照寬度切換樣式。
   - 搜尋頁：點一首就從它開始播，下一首接著播。
   - 設定頁只有外觀組（主題模式、語言）。
   - 播放列：封面、曲名、上傳者、上一首、播放暫停、下一首、進度條。
   - 快捷鍵：空白鍵、Ctrl+←／→、Shift+←／→、Ctrl+F、Ctrl+,、F6。
3. **YouTube.js 探針**（2026-09-29）：
   - 時限約 2–3 個 session，不延長；第 9 個 PR 之後和其他 PR 並行。
   - 過關標準，Android 與 Windows 都要做到：
     - 能載入 YouTube.js；
     - 搜尋有結果；
     - 解出的音訊網址 FMP 播得出聲音；
     - 不需要登入，也不需要另外生成 PO token。
   - 效能數字只記錄。
   - 程式碼不合併；失敗時 M3 以 Dart 實作。
4. **發版 workflow**（2026-09-29）：
   - 在私人的 `1morr/fmp-release-sandbox` 用臨時簽名金鑰完整跑一次，驗完封存。
   - FMP 裡的 workflow 只能手動觸發，M9 才開啟自動觸發，以守住「重寫期間不發版」。
5. **B 站插件**（2026-09-29）：
   - M1 就建公開的 `1morr/fmp-plugins`，只放 README 與 `bilibili/`；
   - CI、`index.json`、插件頁留在 M3。

6. **插件安裝檔格式**（2026-09-30）：單一 `.js` 檔，開頭以 `/* ==FMP Plugin== … ==/FMP Plugin== */` 包一段 JSON manifest，App 不執行腳本就能讀出 manifest 並先檢查網域與能力（沿用使用者腳本 metadata block 的慣例；MusicFree、LX Music 也是一檔一插件）。插件庫可把 manifest 另存、由腳本合併成安裝檔；圖示只能用網址或內嵌 base64。
7. **插件在背景 isolate 執行**（2026-09-30）：`flutter_js` 0.8.7 的 QuickJS 沒有中斷機制，同步無窮迴圈會凍住 UI isolate（PR 9a 實測）。每個插件的 JS 執行環境放在自己的背景 isolate；呼叫逾時先送存活探測：背景 isolate 有回應就只讓這次呼叫以 `NetworkError` 失敗（只是在等網路），沒有回應或 isolate 已結束才把插件標成「沒有回應」並停用到 App 重啟（2026-09-30 擁有者確認）；運算重的腳本（YouTube 解簽名）也不會讓畫面卡頓。不換引擎：可中斷的替代套件（`flutter_qjs_next`、`quickjs_engine`）都是單一作者、低採用的新套件。
8. **M1 的 fixture 錄製**（2026-09-30）：契約執行器加錄製模式，打 `live` tag、手動執行、只給免登入的案例，寫檔前經遮蔽；需要登入的錄製仍在 App 內（M3）。理由：App 內的插件開發工具在 M3，9c 要先錄 B 站 fixture，過時也要能重錄；ADR 0015 §決定 4 的冒煙測試本來就在命令列用真實連線。

## 需求

- **R1**：PR 1 完成指令檔與 spec 分家（決定 1，design §1），同時更正 ADR 0015、0021、0027 的事實。
- **R2**：`app/` 骨架，包含：
  - flavor 與 App 身分；
  - 單一實例鎖；
  - 零聯網兩道防線；
  - `app/AGENTS.md`；
  - CI 分流與彙總 job，並設為必要檢查；
  - `orca.yaml` 的 `app/` setup。
- **R3**：`fmp_lints` 十條核心規則加 `fmp_toast_entry`、`fmp_design_tokens`，每條有雙向變異測試；接線哨兵。
- **R4**：平台層與能力宣告（Android、Windows 實作），以及目錄規則。
- **R5**：drift 最小 schema（`appearance_settings`、`installed_plugins`、`plugin_storage`）、快照、`TrackKey`；另跑 isar／sqlite3 共存探針。
- **R6**：
  - 設定 Notifier；
  - log 門面與遮蔽函式；
  - JSON Lines 的 log 檔（2MB×3）。
- **R7**：`AppError` 與重試策略；Riverpod 自動重試關閉。
- **R8**：網路層（API client、媒體 client、轉址規則、網路紀錄）與 `AuthRequirement` 宣告點；不含登入。
- **R9**：
  - JS 執行環境與宿主 API v1 最小集；
  - 從檔案安裝插件；
  - 契約執行器、fixture、`checks.json`、測試插件；
  - `fmp-plugins` 的 B 站插件（`search`、`resolveStream`）。
- **R10**：播放核心最小集：`PlaybackController`、兩個後端、兩首只在記憶體的佇列、前瞻交接。
- **R11**：`app/` 版 verify-on-device 與 `app/AGENTS.md` 的驗證段（ADR 0027）。
- **R12**：UI（決定 2），包含 token、斷點、字型、slang 三語言、`Toaster`、快捷鍵與 F6。
- **R13**：CI 五平台建置與整合測試；`app-release.yml` 與 sandbox 驗證（決定 4）。
- **R14**：YouTube.js 探針（決定 3）。

技術選擇與 PR 順序見 `design.md`、`implement.md`。

## 驗收

2026-10-01 全部通過，逐項證據與限制見 `research/m1-acceptance.md`。

- [x] Android、Windows 端到端操作：搜尋 B 站，點一首，兩首連續播完。
- [x] phase2-plan §7 每一項都有實測紀錄：
  - [x] ADR 0010：`isar_community`＋`sqlite3` 在 Android、Windows 共存；`sqlite3` 的 Android 16KB page size 對齊。
  - [x] ADR 0009：CI 建置矩陣含 Linux、macOS、iOS（不簽名）。
  - [x] ADR 0008：prod 的 App 身分與舊版一致，dev 不同。
  - [x] ADR 0011：log 門面與遮蔽函式，含遮蔽測試。
  - [x] ADR 0014：
    - `flutter_js` 與宿主 API 最小集；
    - 從檔案安裝 B 站插件；
    - Android、Windows 的 Promise、記憶體、啟動成本實測；
    - YouTube.js 探針有結論。
  - [x] ADR 0018：兩個後端的前瞻交接；Android 換歌時不釋放音訊焦點。
  - [x] ADR 0015：
    - `dart analyze` 看得到插件診斷，哨兵會紅；
    - 契約執行器與 QuickJS 的結論；
    - dev 與 prod 同時開啟時各自獨立；
    - 零聯網兩道防線。
  - [x] ADR 0022：release-please 的發版 PR 與同一 workflow 的建置、驗證、發布在 sandbox 跑通。
  - [x] ADR 0023：提示在全螢幕頁與對話框之上可見；Windows Narrator 下不凍結無障礙樹。
  - [x] ADR 0024：輸入框內空白鍵只輸入空格；F6 焦點切換；Windows 繁中字形由正黑體顯示。
- [x] 新 session 的 SessionStart 只列 `guides` 與 `app` 的 spec 索引（R1）。
- [x] `milestones.md` 的 M1 狀態與勾選已更新，並開好 Linux 平台任務。

## 不在範圍

- 播放頁、音量、隨機、循環、輸出裝置、右側面板、系統媒體控制、串流網址快取、佇列持久化（M2）。
- 登入與 `CredentialStore`、YouTube 與網易雲插件、`fmp-plugins` 的 CI 與 `index.json`、插件頁、Debug 頁（M3）。
- 其他設定組的欄位、音樂庫表（M4 以後）；`PermissionGateway`（M6）。
- Linux、macOS、iOS 的實作檔與實機驗證（各平台任務）。
- 舊專案的程式、`release.yml`、舊 skill 的內容（切換 PR 前只收緊急修正）。
