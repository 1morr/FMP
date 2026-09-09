# FMP 整頓與重構計劃

> 依據 2026-09-09 到 09-10 的五輪審計（A 變更審計、B 基準研究、C 整頓、D 架構評估、E 通用規則）。
> 交接檔在本機 `.scratch/audit/`，不進版控；本文件是它們的可執行摘要，說「做什麼、誰先誰後、怎麼驗收」。
> 證據與量測都在交接檔裡，這裡只留結論與必要數字。
>
> 閱讀方式：§1 前提與現況，§2 里程碑總覽，§3 各里程碑的任務與驗收，§4 待你拍板的決策，§5 明文不做的事，§6 進度。
> 每個里程碑結束時 `main` 可發版、CI 綠燈、使用者可見的改動都在 Android 模擬器上看過。

---

## 0. 工作慣例

- 一個里程碑一個分支、一個 PR；PR 合併前 CI 綠燈，UI 改動附實機截圖或元素描述。
- 每個任務對應一張 GitHub issue（已有的沿用編號，沒有的開工前開）。進度看 issue 狀態與 §6，不另外維護 progress 文件。
- 程式碼與文檔規則以根目錄 `AGENTS.md` 與各子樹 `AGENTS.md` 為準，本文件不重述。
- 唯讀評估與執行分開：先給處置表，批准後再改。純刪除與純測試的任務可以直接做。
- 每個任務結束時記錄「做了什麼、推翻了哪條先前結論」到對應 issue，不寫進本文件。

---

## 1. 前提與現況（2026-09-10）

| 事實 | 值 |
|---|---|
| `main` | `72f3b6e1`，比 `v1.10.0` 多 3 個 commit |
| 整頓分支 `chore/docs-and-repo-hygiene` | 30 個 commit，未 push、未 merge，工作樹乾淨 |
| `main` 保護 | 無 ruleset、無 branch protection |
| open issues | 14 張（#37 #39 #41 #82 #84 #85 #86–#93） |
| `lib/` 手寫行數 | 98,561 |
| `test/` 行數 | 56,030（CI 實跑 52,075），test/lib 比 0.53，五個對照組裡最高 |
| 音訊層 | 401 KB，是對照組最大者 namida 的 2.4 倍；`lib/services/audio/audio_provider.dart` 2,184 程式碼行，已有不再增長的棘輪 |
| 7 份 `AGENTS.md` | 約 1,250 行，`lib/ui` 與 `lib/services/audio` 兩份仍超過 200 行 |
| 舊審查殘留 | `docs/review/execution-log.md` 1,806 行、`docs/review/assets/` 11 MB；「Phase N」字樣在 ADR、skill、docs 與 4 個測試檔仍有 |

**兩個影響日常使用的問題**：Bilibili 匿名請求被風控（與 CI 無關，成因見 M1）；桌面矮視窗下收合導覽軌溢出，設定不可點（#84，P1）。

**架構結論**：不重寫。D 的方案 A 是漸進的 9 步，以刪除為主；重寫的三個觸發條件目前一個都不成立（見 §5）。

---

## 2. 里程碑總覽

| 里程碑 | 目標 | 規模 | 前置 |
|---|---|---|---|
| **M0** 合併整頓分支 | 30 個 commit 進 `main`，`main` 有最小保護 | S | 你看過 commit 表 |
| **M1** 兩個 P1 | Bilibili 風控降載與簽名；#84 導覽軌溢出 | M | M0 |
| **M2** 發版 v1.10.1 | 第一次走自動 release notes 流程；五項只有你能做的實機驗證 | S | M1 |
| **M3** 文檔與測試樹清理 | Phase 殘留、`docs/review` 整目錄、測試樹去掉源碼字串斷言、依賴淘汰警告 | M | M0（可與 M1 並行） |
| **M4** 架構方案 A | 刪死碼、後端契約測試、播放副作用 registry、合併重複路徑 | M–L | M3 |
| **M5** 決策結案與通用規則 | 產品決策寫回 repo；全局 `CLAUDE.md` 與 repo-hygiene skill | S | M4 |

M1 與 M3 互不依賴，可以在兩個 worktree 並行。M4 等 M3 是因為測試樹清理會改 `AGENTS.md` 的驗證表與幾支靜態規則，方案 A 每一步都靠它們驗收。

---

## 3. 各里程碑

### M0 合併整頓分支並保護 `main`

| # | 任務 | 內容 | 驗收 |
|---|---|---|---|
| 0.1 | 審閱 30 個 commit | 讀 `.scratch/audit/C-cleanup-done.md` §2 的表與 §3 的偏差說明；不同意的 commit 用 `git revert` 單獨撤，不改寫歷史 | 你逐條看過 |
| 0.2 | push 並開 PR | `chore/docs-and-repo-hygiene` → `main`，PR 描述貼 C2 的驗證輸出 | CI 三個 job 綠 |
| 0.3 | `main` 最小 ruleset | 只擋 force-push 與刪除分支，不要求 PR review，不影響平常推送 | `gh api repos/1morr/FMP/rulesets` 長度 1 |
| 0.4 | merge | squash 或 merge commit 皆可，不 rebase | `main` 含 `48631479` 的內容 |

出口：`main` 上 `flutter analyze`、`flutter test --exclude-tags live`、`dart format --set-exit-if-changed lib test` 全綠。

### M1 兩個 P1

**1.A Bilibili 風控**（先開 issue，目前沒有任何 issue 記錄過這件事）

成因（2026-09-10 實測，記錄在 #95）：CI 不打 Bilibili，8 月 25 日以來也沒有 commit 改過請求行為。這台機器上的真正根因是 Clash Verge 的分流：沒有規則把 Bilibili 與 Netease 導向 DIRECT，全部掉到最後的 `Match` 走台灣節點，TLS 握手被切斷；就算通了，台灣出口 IP 的匿名請求也會被 Bilibili 風控。這要在 Clash 的規則裡修，不在 repo 內。App 端保留的是獨立於此的衛生改善：電台輪詢不快取不退避、`rateLimited` 提示不說怎麼解、連網測試沒有東西擋漏標。1.2 與 1.3 延後到 Clash 規則修好、直連下重跑 live 測試之後再決定。

| # | 任務 | 檔案 | 驗收 |
|---|---|---|---|
| 1.1 | 電台輪詢降載 | `lib/services/radio/radio_refresh_service.dart`、`lib/data/sources/bilibili_live_client.dart` | 房號解析結果快取（房號是不變量）；同一輪出現風控碼即指數退避，最長 30 分；App 進背景時停止輪詢。單元測試覆蓋三條，實機開 5 台電台用 VM Service 的 HTTP profiling 數請求量，每台每輪 ≤ 3 |
| 1.2 | 開機領 buvid | `lib/data/sources/bilibili_source.dart` | 啟動時向 `finger/spi` 取 buvid3/buvid4 並持久化，失敗才退回本地產生；不再只在踩到 `-352` 時才換。風控碼判定擴到 `-412`、`-799` |
| 1.3 | WBI 簽名 | `lib/data/sources/bilibili_source.dart`、`lib/data/sources/source_http_policy.dart` | 搜尋與排行榜端點帶 `w_rid`／`wts`；mixin key 每日快取。演算法以 bilibili-API-collect 的 WBI 文件為準，先用 live 測試確認哪些端點目前強制簽名，再決定範圍 |
| 1.4 | 使用者面提示 | `lib/ui/` 錯誤呈現 | `rateLimited` 的 toast 說明「登入 Bilibili 可解」並附設定入口，不只顯示「播放失敗」 |
| 1.5 | 守門 | `test/support/` | 一支靜態規則：新增的連網測試必須標 `live`（#56 修過一次，沒有東西擋回歸） |

即時緩解：在設定裡登入 Bilibili 帳號。這一條寫進 README 的疑難排解，不等程式修好。

**1.B #84 導覽軌溢出**（同區域的 #85 一併處理）

| # | 任務 | 檔案 | 驗收 |
|---|---|---|---|
| 1.6 | 收合導覽軌在矮視窗可捲動或折疊 | `lib/ui/layouts/responsive_scaffold.dart` | 411dp 高、6 個目的地加選單按鈕，Settings 可點；橫向手機與側欄展開兩種情境實機截圖 |
| 1.7 | #85 排行榜列溢出 | `lib/ui/` 排行榜 tile | 根因在播放數群組不可縮，不是版面層；窄寬度下標題至少顯示 8 個字 |

順帶的小修（同分支，各自一個 commit）：#87 Netease 未登入 `code=404` 誤判成需要 VIP；#89 secure storage 失敗時音訊與歌詞 AI 設定頁永久轉圈。

出口：四張 issue 關閉，Android 模擬器橫向與直向各跑一次，Windows 桌面矮視窗跑一次。

### M2 發版 v1.10.1

| # | 任務 | 驗收 |
|---|---|---|
| 2.1 | pubspec 版本升到 `1.10.1` | `test/workflows/pubspec_version_test.dart` 綠 |
| 2.2 | 走新的 release 流程 | draft release 的 body 由 commit 範圍自動產生；你審過 draft 再 publish。流程以 `docs/build-and-release.md` 為準 |
| 2.3 | 五項只有你能做的實機驗證 | 見下表，結果各記一行到對應 issue |

| 驗證 | 怎麼做 | 對應 |
|---|---|---|
| 登入狀態下的 secure storage 9→10 遷移 | 三個來源都登入的 v1.9.1 或 v1.10.0 覆蓋升級，看 logcat 的 `Migrated N items` | #89 |
| Windows 托盤 | 點托盤圖示、右鍵選單、關閉到托盤 | #90 |
| 高 DPI 封面清晰度 | DPR ≥ 3 的實機看首頁與播放頁封面 | C3 的 P-7c |
| Android gapless | 連播兩首，聽交界 | just_audio 0.10 升級 |
| 音訊裝置失效 | Windows 播放中停用輸出裝置，看錯誤文案 | #41 |

出口：`v1.10.1` 發布，更新對話框在 v1.10.0 上能讀到可讀的 release notes（#82 已修）。

### M3 文檔與測試樹清理

**3.A 文檔尾巴**

| # | 任務 | 內容 |
|---|---|---|
| 3.1 | 刪 `docs/review/` 整目錄 | execution-log 與 28 張截圖都刪；歷史在 git。同 commit 刪根 `AGENTS.md` 那條「不得引用 execution-log」的 Never、`docs/README.md` 的三處引用、以及靜態規則測試裡對應的那一支 test |
| 3.2 | Phase 殘留 | `docs/adr/0001-per-source-settings-and-string-source-ids.md`（4 處）、`docs/adr/0002-repository-boundary.md`（2 處）、`.claude/skills/verify-on-device/SKILL.md`（3 個小節標題）、`docs/debugging-with-vm-service.md:512`、`test/services/audio/audio_provider_size_static_test.dart` dartdoc。一律改成日期或主題，不再指向已刪的路線圖。`lib/services/lyrics/title_parser.dart` 的「Phase 1/2」是演算法步驟，改成「步驟」 |
| 3.3 | 測試檔裡的 review 代號 | 11 個檔的 group 名帶 `C1a`、`B2`、`D4` 之類；3 個檔用 `Phase1` 當測試資料名。全部改成行為描述 |
| 3.4 | README 截圖 | #91：補 Android 截圖，刪兩張零引用的孤兒圖 |
| 3.5 | `AGENTS.md` 超過 200 行的兩份 | `lib/ui`、`lib/services/audio`。只在有明確可刪內容時動；行數本身不是目標，跨檔契約留著 |

**3.B 測試樹**（開 `chore/trim-static-assertions`）

背景：50 個測試檔、8,585 行在讀 `lib/` 原始碼做字串斷言，只有 11 支誠實叫 static_rule。它們多數是把某次重構的完成狀態凍成永久測試，不對應任何使用者可見的失效。音訊層 12,018 行測試對應真實 bug，不動。

| # | 任務 | 內容 | 驗收 |
|---|---|---|---|
| 3.6 | 刪 12 支源碼字串斷言 | 清單在 `.scratch/audit` 的測試評估與本文件附錄 A。同輪改根 `AGENTS.md` 驗證表、`lib/data/AGENTS.md`、`lib/services/audio/AGENTS.md` 的引用 | 減約 916 行；`test/support/agents_docs_static_rule_test.dart` 綠 |
| 3.7 | 合併 5 支為 2 支 | 三份 HTTP policy usage 測試合成一支全樹掃描；credentials 測試併入 `test/data/sources/source_http_policy_test.dart`；list_tile_leading 併入 ui_consistency | 行為斷言零丟失 |
| 3.8 | `test/demo` 搬出 `test/` | 6 檔 2,162 行，零個 `test()`，搬到 `tool/demo/` | `test/` 少 2,162 行 |
| 3.9 | 補自測 | `test/ui/static_rules/ui_consistency_static_rule_test.dart`、`test/ui/static_rules/error_presentation_static_rule_test.dart`、`test/providers/riverpod3_static_rule_test.dart` 各加「合成違規會被抓到」與「註解不算」兩條；ui_consistency 裡 3 條純目錄佈局規則降級成 `lib/ui/AGENTS.md` 的文字約定 | 每支靜態規則都有自測 |
| 3.10 | meta 規則 | 一支測試：讀 `lib/` 原始碼的測試必須位於 `test/support/` 或 `test/*/static_rules/`、檔名以 `_static_rule_test.dart` 結尾、含自測。根 `AGENTS.md` 加一行對應規則 | 偽裝成 widget test 的源碼 grep 從此進不了 CI |

**3.C 依賴**

| # | 任務 | 驗收 |
|---|---|---|
| 3.11 | #86 Gradle / AGP / Kotlin 升級 | 唯一有外部時限的技術債。Android build smoke 綠，實機安裝一次 |

出口：`test/` 約 52,800 行以下，`docs/review/` 不存在，全樹 `rg -i 'phase [0-9]'` 只剩 git 歷史。

### M4 架構方案 A

不收斂雙後端，不重寫。每一步結束時 repo 可運作、可發版，每步一個 PR。

| 步 | 內容 | 刪／加 | 規模 | 驗收 |
|---|---|---|---|---|
| 4.1 | 刪死抽象與死 façade：`AvailabilitySource` 及 3 份實作、`SourceManager` 的 5 個零呼叫 façade、`TrackInfoSource` 的 4 個死方法、media_kit 服務的 mobile 分支與音量控制器。同輪改 `lib/data/sources/AGENTS.md` | 刪 600–800 行 | S | `flutter test test/data/sources test/services/audio` |
| 4.2 | `NeteasePlaylistSource` 死路徑：先實機確認匯入 Netease 歌單走內部流程，再刪 `lib/data/sources/playlist_import/netease_playlist_source.dart` 與重複的 URL 判斷 | 刪 259 行 | S | 匯入 Netease 歌單實機 |
| 4.3 | 後端契約測試：同一份斷言跑在 `JustAudioService`、`MediaKitAudioService`、`FakeAudioService` 上，涵蓋 `seekToLive` 策略、`PlaybackEndReason` 分類邊界、`setNextMedia` 修剪語意。`seekToLive` 目前兩個後端已不等價，先補齊再上契約 | 加約 200 行測試 | M | 新測試綠；Windows 播 Bilibili 直播 |
| 4.4 | 播放副作用 registry：4 方法介面（onTrackStarted、onPlaybackStateChanged、onStopped、dispose）收 `NowPlayingPublisher`、`PlayHistoryRecorder`、`LyricsAutoMatchCoordinator`，每次呼叫包 try-catch，刪第二個扇出站點 | 淨 +50 行 | S–M | 「兩條播放路徑通知同一組消費者」與「teardown 完整」兩條測試 |
| 4.5 | 合併搜尋 fan-out：刪 `SourceManager.searchAll`／`searchFrom`，匯入改走 `SearchService` | 刪 45 行 | S | `flutter test test/services/search test/services/import` |
| 4.6 | 合併排行榜路徑：熱門頁改走 `RankingCacheService` | 刪 60 行 | M | 探索頁實機，三個榜共用快取 |
| 4.7 | 合併畫質選擇到 `audio_stream_quality_fallback.dart` | 刪 12 行 | S | `flutter test test/data/sources` |
| 4.8 | #88 debug 頁：加平台守衛並改走 `AudioController`，或直接刪那 1,297 行。建議刪 | 刪 0 或 1,297 行 | S | Android 實機點進開發者選項 |
| 4.9（可選） | 事件路由改成回傳 `sealed class PlaybackAction`、控制器 switch 套用。這 540 行是 #41 #43 #54 #55 的宿主，風險最高，放最後；做之前先照 `5d7dd2da` 的方法量一次 | 棘輪可能下調 300–400 行 | M–L | `flutter test test/services/audio` 全綠，兩平台實機 |

4.1、4.2、4.5、4.7 是純刪除，可以直接做。4.3、4.4 加機制，先給設計再做。4.6 動首頁，要實機。

出口：音訊層與音源層合計減 1,000 行以上，後端等價由測試而非口頭保證。

### M5 決策結案與通用規則

| # | 任務 | 內容 |
|---|---|---|
| 5.1 | 產品決策寫回 repo | §4 的 P-1 到 P-3 拍板後各一段寫進對應 `AGENTS.md` 或 ADR，附觸發重新評估的條件 |
| 5.2 | #92 #93 憑證失效統一呈現 | 產品面的功能，等 M4 之後做；先把 `expiredPlatforms` 這個零讀取的欄位處理掉 |
| 5.3 | 全局 `CLAUDE.md` 增補 | E 的 29 行草稿裡先進「Agent 指令檔」與「規則要有閘門」兩節共約 22 行；「數字要可追溯」只有一個實例，等第二個 |
| 5.4 | repo-hygiene skill | 以 E 的草稿為底，套到你其他 4 個 public repo 時逐條驗證 |
| 5.5 | 其他 repo 的最小動作 | 四個 repo 各加 `.gitattributes`；`biliStreamMonitor` 補隱私聲明（它要 cookies 權限讀 B 站登入態） |

---

## 4. 決策

2026-09-10 全部依建議值拍板。P-1 定為預設 10,000 筆、設定可調、刪最舊的。
表格保留建議與它原本阻塞的步驟，方便日後回看當初為什麼這樣選。

| # | 議題 | 建議 | 阻塞哪一步 |
|---|---|---|---|
| D-b | 30 個 commit 是否 merge | 看過 C2 的表後 merge | **阻塞 M0** |
| D-a | `main` 最小 ruleset | 建，只擋 force-push 與刪分支 | M0 |
| D-1 | 雙後端是否收斂成 media_kit | 不收斂，改用契約測試把等價機制化 | M4 前提 |
| D-2 | 方案 A 步驟 1–2 刪死碼 | 做 | M4 |
| D-3 | 播放副作用 registry | 做，範圍 3 個消費者 | M4 |
| D-4 | `audio_provider.dart` 再往下拆 | 暫不做，列為 4.9 可選 | M4 |
| D-5 | 位元組快取 | 結案為不做，理由寫進 `lib/services/audio/AGENTS.md` | M5 |
| D-6 | crossfade | 明文放棄，一段話寫進 `lib/services/audio/AGENTS.md` | M5 |
| D-7 | 音源插件化（原 Phase 9）與「出廠空殼」 | 兩題一起放棄；capability 介面現在有 3 個死的 5 個薄的，不是凍結成公開 API 的時機 | M5 |
| P-1 | 播放歷史要不要保留上限 | 需要你決定，會主動刪使用者資料。建議上限 10,000 筆並在設定裡可調 | **阻塞 M5 的 5.1** |
| P-2 | App 內更新要不要自動檢查 | 產品決策。建議啟動後背景檢查一次，每日最多一次，可關 | 5.1 |
| P-3 | `docs/review/` 整目錄刪除 | 刪，含 execution-log 與截圖 | M3 的 3.1 |
| P-4 | 測試樹刪 12 支 | 刪，清單見附錄 A | M3 的 3.6 |
| E-1 | 全局 `CLAUDE.md` 增補 | 先進 22 行 | M5 |

---

## 5. 明文不做的事

| 不做 | 理由 |
|---|---|
| 核心重寫 | 15 條架構問題沒有一條需要重寫；重寫要同時放棄 12,018 行測試與 1,426 行踩坑註解。重新評估的條件：just_audio 確定停更且 media_kit 的 Android 背景切歌問題有確定修法；或決定支援 Linux／macOS；或音訊層成為 issue 的主要來源 |
| 收斂成 media_kit 單後端 | 只縮 6.3%，卻要承擔四筆跨 OEM 開啟中的背景切歌失效回報 |
| 目錄大搬移（原 Phase 6） | 分層邊界已由靜態測試守住，搬 135 個檔案不會讓耦合更誠實 |
| 音源插件化（原 Phase 9.2–9.4） | `flutter_js` 上游停滯；capability 介面尚未收斂 |
| pre-commit 框架 | Dart 生態沒有成熟等價物，localsend 與 spotube 都只靠 CI；CI 已有 format／analyze／test 三道 |
| issue templates、PR template、CODE_OF_CONDUCT | open PR 為零，沒有外部貢獻者流量；理由已寫在 `48631479` |
| 一次性全樹簡繁轉換 | diff 會淹沒所有真實改動；改到哪轉到哪 |
| 文檔連結有效性檢查 | 五個成熟對照組 0/5 做，不是基準 |

---

## 6. 進度

| 里程碑 | 狀態 | 分支 / PR | 備註 |
|---|---|---|---|
| M0 | 完成 2026-09-10 | #94 | `main` 有 `protect-main` ruleset |
| M1 | 進行中 | #96 已合併；1.B 在 `fix/rail-overflow-and-p1s` | 1.A 做完；1.2 與 1.3 延後（#95 記錄了 Clash 根因） |
| M2 | 未開始 | | 等 1.B |
| M3 | 進行中 | #97 已合併；3.1 在 `chore/drop-review-history`；3.B 在 `chore/trim-static-assertions` | 3.4、3.5、3.11 未開始 |
| M4 | 未開始 | | |
| M5 | 未開始 | | |

---

## 附錄 A：M3 要刪的 12 支測試

| 檔案 | 行 | 為什麼 |
|---|---:|---|
| `test/ui/widgets/mini_player_test.dart` | 71 | 不 render，斷言 private method 不存在 |
| `test/ui/pages/radio/radio_reload_relocation_test.dart` | 33 | 檔名是事件，斷言某個 builder 缺席 |
| `test/ui/playlist_cover_grid_structure_test.dart` | 49 | 手寫大括號配對切 private class body |
| `test/ui/pages/settings/account_management_page_test.dart` | 28 | 正則寫死 10 空格縮排 |
| `test/services/audio/audio_backend_static_test.dart` | 125 | 斷言編譯器已保證的方法簽名；`lib/services/audio/AGENTS.md` 有引用，同輪改 |
| `test/ui/pages/settings/database_viewer_page_coverage_test.dart` | 169 | 斷言 import 字面量；根 `AGENTS.md` 驗證表與 `lib/data/AGENTS.md` 有引用，同輪改 |
| `test/ui/pages/library/playlist_detail_remote_remove_structure_test.dart` | 96 | structure 家族 |
| `test/data/repositories/download_repository_bulk_structure_test.dart` | 59 | structure 家族 |
| `test/services/download/download_path_sync_service_batch_test.dart` | 37 | structure 家族 |
| `test/data/repositories/playlist_mutation_batch_structure_test.dart` | 39 | 真行為已在 `test/data/repositories/playlist_mutation_repository_test.dart` 測過 |
| `test/core/services/network_image_cache_service_structure_test.dart` | 38 | structure 家族 |
| `test/providers/lyrics_auto_match_service_provider_test.dart` | 172 | 8 個 fake 換 1 條接線斷言，與 `test/services/lyrics/lyrics_auto_match_service_test.dart` 同行為 |

保留但搬家：`test/services/audio/audio_provider_size_static_test.dart` 搬到 `test/support/`，dartdoc 去掉 Phase 字樣。
