# M4 執行計畫

「design §n」指本任務的 `design.md`；「決定 n」指 `prd.md` 的擁有者決定；「§17 第 n 條」指 design 的確認清單。

## 通用規則（每個 PR 子任務）

- **開工**：
  - 從最新的 `main` 開分支；
  - 以 `task.py create "<標題>" --slug <slug> --parent .trellis/tasks/10-15-m4-library-sync --package app --no-start` 建子任務；
  - prd 只寫做什麼與驗收（ADR 0026 §決定 1），在已核准的範圍內直接做，遇到未定的事才問。
- **M4a 與 M4b 的順序**：M4b 的 PR 在 M4a 驗收之後才開（決定 1），例外是 PR 16（匹配核心）與 PR 20（排行的契約與工作）：不碰歌單 UI，M4a 期間可以先做，但不早於它們依賴的 PR。
- **合併條件**：
  - `app/` 可編譯、`flutter test` 全綠；
  - CI 彙總 job `CI Result` 通過；
  - PR 描述附 review 指南；動到 `fmp-plugins` 的附該 repo 的 PR 連結。
- **實機驗證**（ADR 0027 與 2026-10-13 的修訂，design §1.3）：
  - 使用者看得到的 PR 照 `verify-on-device` skill 在 Android 模擬器驗；改到平台各自實作的（檔案對話框、重啟）與導覽的寬版再驗 Windows。回報寫明平台與模式。
  - 預設重播（dev flavor＋`fmp-test`、PR 19 起加 `fmp-test-meta`）；`fmp-test` 隨各能力 PR 加假實作（design §4.9），寫進它的 README。
  - 改動本身是插件、網路層、登入，或在錄 fixture 時才用真實連線，只做該節列出的請求，不批次、不迴圈。
- **真實帳號與遠端寫入**（決定 4）：
  - 帳號沿用 M3：YouTube 用擁有者另開的 Google 測試帳號；B 站、網易用擁有者指定的帳號。**登入由擁有者自己掃 QR 或輸入密碼**；代理不輸入、不讀取、不轉述任何密碼、cookie 值或 token。
  - **遠端寫入只對擁有者建的私人「FMP 測試」歌單**（三個平台各一張），加入、移除一首各一次；不對其他歌單寫、**不做真實的「在遠端新增歌單」**（決定 4 只允許加入與移除；建立以 `fmp-test` 重播驗）。
  - 擁有者需要在場的步驟（PR 13、14、15 與 M4a 驗收）開工前先問時間，到了登入或寫入那一步停下等擁有者。
  - log、截圖、PR 描述、research 檔只寫 cookie 名稱與「有／沒有」，不寫值、帳號名稱、頭像、私人歌單的名稱與內容；截圖前確認畫面沒有帳號資訊（帳號列收起，私人歌單的詳情不截）。
  - Spotify、QQ 只用匿名，各匯入一張公開歌單一次。
- **改 schema**：照 `.trellis/spec/app/data/index.md` § 改 schema 做完整流程；版本號以合併順序為準（design §3.2：v15 PR 1 → v16 PR 8a → v17／v18 PR 19、20）。同時開兩個動 schema 的分支時，後合併的重排。
- **動到外殼、提示或新增全螢幕路由**：照 `app/AGENTS.md` § 驗證跑 `toast_layering_test.dart`，把新的路由（巢狀導覽裡的頁、匯入預覽頁）加進它的案例。
- **收尾**：子任務 `finish` 與 `archive --no-commit --skip-branch-validation`；手動 commit；以 merge commit 合併。
- **文件**：
  - 每個 PR 更新 `app/AGENTS.md` 中自己那一層：只寫查不到的契約與有閘門的規則，每條寫出它的閘門；
  - 需要時更新 `.trellis/spec/app/<layer>/`；
  - design §16 標「PR 0」的更正在 PR 0 一次加，其他在對應的 PR 加。
- **套件版本**：以 design §15 為起點，加依賴時到 pub.dev API 核對一次 `latest`，裝當前 stable；與 design 不同時在 PR 描述說明。
- **lint**：新規則與表的改動照 `.trellis/spec/app/lints/index.md` 寫雙向變異案例，並在 `tool/lint_sentinel.dart` 加違規行。
- **子代理模型**（全域規則：預設 sonnet；只有會做「影響後續的決定」的子代理用 opus）：
  - design 已把資料表、契約、演算法、流程寫定，**照計畫寫程式與測試一律 sonnet**；
  - opus 只用在：**要自己定版面與互動的新頁面**（導覽與首頁、歌單詳情、多選、匯入預覽、探索）、**要校準的決定**（PR 16 的權重與門檻）；
  - 交給 sonnet 的實作，prompt 附完整計畫（動哪些檔、介面簽章、驗收條件），並寫明：遇到計畫沒涵蓋的設計決定就停下回報，不自行拍板；由主對話決定，必要時再開 opus；
  - `trellis-check`（審查）一律 opus；研究代理一律 sonnet；
  - 各 PR 的模型寫在該節，理由一句在括號裡。

## 進度與交接（compact 後從這裡接）

- **狀態**（2026-10-16）：已核准（2026-10-15）。已合併 PR 0–16、20（FMP #272–#289 與 PR 15；fmp-plugins #16–#22）。M4a 剩驗收；M4b 其餘的 PR 等 M4a 驗收（決定 1）。
- **擁有者決定**：決定 1–4 在 `prd.md`；design §17 的 18 條已於 2026-10-15 全部照建議確認；另決定「在遠端新增歌單」不做真實實測，只用測試插件重播驗。
- **待擁有者回覆**：無。
- **下一步**：M4a 驗收（擁有者在場；先問時間）。驗收前先把不需要擁有者的部分做完：ADR 測試對照（`research/m4-adr-tests.md` 的 M4a 段）、`milestones.md`、`app/AGENTS.md` 的 opus 審查。PR 13 起真實實測與錄製都在 Windows：三個平台已登入在 `m4-pr13` worktree 建置產物旁的 `userdata-dev`（憑證在 `%APPDATA%\com.personal\fmp-dev` 的 secure storage，各 dev build 共用），開新 worktree 時把 `userdata-dev` 整個複製過去就不必重新登入；三張「FMP 測試」已匯入、`writable` 都是 1。整合測試會清 dev 資料：Windows 上跑之前先備份 `userdata-dev`。
- **每個 PR 的固定流程**（照 M3 的「每個 PR 的固定流程」，`archive/2026-10/10-08-m3-sources-accounts-devtools/implement.md`）：分支 → `task.py create`（`--parent .trellis/tasks/10-15-m4-library-sync`）→ prd 與 `implement.jsonl`／`check.jsonl`（design 的相關節、ADR 0032–0034、相關的 `.trellis/spec/app/<layer>/index.md`）→ `task.py start` → 派 `trellis-implement`（驗證清單：`dart format --output=none --set-exit-if-changed .`、`build_runner` 後沒有實質變動、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`、動到 lint 時 `dart run tool/lint_sentinel.dart`、需要時建置）→ 實機驗證 → 派 opus `trellis-check`（要它試著攻破：憑證與遮蔽、`mutates` 的略過、刷新的代際、備份檔不含帳號與 cookie、還原的確認框）→ 後續待辦寫進本檔「留下的後續」→ 還原只有換行差異的產生檔（逐檔 `git diff --ignore-all-space --ignore-cr-at-eol` 為空才還原）→ 分開 commit → `finish`、`archive` → push、`gh pr create`（照已核可計畫做的 PR 直接 push，計畫外的先問）→ `gh pr checks --watch` → `gh pr merge --merge`。
- **fmp-plugins 的 PR**：
  - 在同層的 `fmp-plugins/` clone 開分支；
  - 先合併 FMP 的契約 PR，再把 `fmp-plugins` 的 `FMP_REF` 改到那個 commit；
  - 改完以 `FMP_PLUGIN_DIR=<絕對路徑>/<插件> flutter test test/plugins/contract/contract_test.dart` 重播驗證（PowerShell 寫法見 `app/AGENTS.md` § 驗證，跑完刪環境變數）；
  - 不需要登入的案例以命令列 `record_test.dart` 錄；`requiresLogin` 的案例在 PR 12 之後以 App 內工具錄、刪減後提交並標 `meta.edited`（或手寫）；`mutates` 的案例一律手寫；
  - 每次都要 `index.json` 重產、版本號升級（CI 擋）；
  - 在該 repo 開 PR 並合併（擁有者的 repo，照已核可計畫直接做）。
- **地雷**（M1–M3 帶來的，仍適用）：
  - 文件或程式碼引用子任務的研究檔時，一律寫 archive 後的路徑。
  - CI 的 `app` job 工作目錄已經是 `app/`。
  - 桌面裝置一次 `flutter test` 只能跑一個整合測試檔；整合測試會清掉 dev App 的資料，先跑整合測試再裝插件。
  - 真實連線驗播放用「臨時播放」，不要在開了循環的佇列裡混測試曲目（M3 PR 1 的教訓）。
  - 搜尋來源每次啟動回到第一個插件，重播前先點 `FMP Test Plugin` chip。
  - Windows 上 `make-migrations` 遇到 CRLF 快照：先轉 LF（`.trellis/spec/app/data/index.md`）。
- **M4 新的地雷**（預期）：
  - **巢狀 `Navigator`**（PR 2）：快捷鍵、焦點三區、Esc 與系統返回鍵、`toast_layering_test.dart` 都要重新驗。
  - **刷新與排程的互斥**（PR 8a、10）：手動刷新、寫入後刷新、排程同時發生時只能有一張在刷。
  - **大歌單**（PR 8a、19）：一萬首的匯入、刷新與匹配要量時間，寫進 PR 描述。

## 順序與相依

| PR | 依賴 | 半 | ★ | PR | 依賴 | 半 | ★ |
|---|---|---|---|---|---|---|---|
| 0 | 擁有者核准 | — | | 12 | 0 | M4a | |
| 1 | 0 | M4a | | 13 | 8b、12 | M4a | ★ |
| 2 | 1 | M4a | | 14 | 13 | M4a | ★ |
| 3 | 2 | M4a | | 15 | 13 | M4a | ★ |
| 4 | 2 | M4a | | 16 | 0 | M4b | |
| 5 | 3 | M4a | | 17 | 6、M4a 驗收 | M4b | ★ |
| 6 | 0 | M4a | | 18 | 6、M4a 驗收 | M4b | ★ |
| 7 | 6 | M4a | ★ | 19 | 8b、16、17（或 18） | M4b | |
| 8a | 1、6 | M4a | | 20 | 0（契約與工作可在 M4a 期間做，見該節） | M4b | ★ |
| 8b | 3、8a（實機用 7） | M4a | | 21 | 4、5、20、M4a 驗收 | M4b | |
| 9 | 6 | M4a | ★ | 22 | 19、20、21 | M4b | |
| 10 | 8b | M4a | | | | | |
| 11 | 7、8b | M4a | | | | | |

★＝動到 `1morr/fmp-plugins`（共 8 個：7、9、13、14、15、17、18、20）。7、9、17、18 只有 `fmp-plugins` 的 PR（17、18 另在 FMP 加 `officialPluginIds`）；13、14、15、20 先合 FMP 的契約與 UI，再合 `fmp-plugins`。

- **與 decisions §4 草案的差異**：
  - PR 8 拆成 8a（引擎與 `playlist_remote`，沒有 UI）與 8b（匯入對話框、手動刷新、狀態列）：刷新引擎是邏輯最重的一個，先單獨審查（M3 PR 14 拆 14a／14b 的理由）。
  - `playlists` 的 Mix 三欄與 `playlist_entries` 的遠端三欄在 PR 1 一起建（欄位已定案，只做一次 migration；M3 `developer_settings` 的先例）。
  - `chart_settings` 從 PR 21 移到 PR 20：排行工作要讀它決定抓哪些榜單（B12）。
  - PR 2 就放首頁（只有最近播放與首次啟動引導）：導覽的第一項要有頁面，曳光彈每一步都要可運作；PR 4 加其他區塊。
- **曳光彈**：PR 1 → 2 → 3 先讓一張本機歌單端到端可用；接著 6 → 7 → 8a → 8b 讓「貼一個 YouTube 歌單網址 → 匯入 → 刷新」可用。之後每一步都只加能力。
- **可以平行**：0 之後 1、6、12、16 同時開；M4a 期間 16、20 的契約與工作可先做。
- **最長的鏈**：0 → 1 → 2 → 3 → 8b → 13 → 14。
- **高風險先做**：design §4.3、§4.8 的實測放在 PR 7、9、17、18 的開頭；PR 8a 先寫測試再寫實作。

## 0. 規劃檔、ADR 與文件更正

- [x] 本任務的 `prd.md`、`design.md`、`implement.md`、`research/` commit。
- [x] ADR 0032–0034：依確認結果修訂，狀態改「已採納」、日期改核准日。
- [x] design §16 標「PR 0」的更正（§17 已於 2026-10-15 確認，第 16 條通過，ADR 0030 那一行照加）。
- [x] `milestones.md` § M4 拆成 M4a、M4b（範圍、驗收、依賴、頁面對照表）；`09-26-fmp-rewrite/task.json` 的子任務清單加本任務。
- 驗證：`milestones.md` 的 M4a／M4b 範圍與 design §1.1 一致；`git grep` 新 ADR 的引用都對得上檔名；既有 ADR 的每一行更正都在 design §16 列的位置。
- 依賴：擁有者核准。模型：sonnet（文件，照清單）。

## M4a 音樂庫與平台歌單

## 1. 歌單表與孤兒清理（design §3.1、§3.2）

- [x] schema v15：`playlists`（含 Mix 三欄與 CHECK）、`playlist_entries`（含遠端三欄、兩個索引）；`PlaylistKind` 等列舉的寫死字串進 `converters.dart`。
- [x] `PlaylistRepository`：`watchAll`（依 `sort_order`）、`create`、`update`（名稱、描述、封面）、`delete`、`reorder`（整批重寫 `sort_order`）、`entries(playlistId)`（依 `position`, `id`，join `tracks`）、`addTracks`（upsert 曲目、接在尾端）、`removeEntries`、`moveEntries`（整批重寫 `position`）、`changes()`（`tableUpdates`）。只加這些有人呼叫的方法。
- [x] 孤兒查詢加 `playlist_entries`。
- 測試：migration 三種與兩個索引（升級與全新）；CHECK；連帶刪除；`RESTRICT`；`only unreferenced tracks are orphans` 加歌單項目的案例；`stored format`；重寫 `position` 後順序正確；一萬首歌單的 `entries` 與 `moveEntries` 耗時寫進 PR 描述。
- 實測：沒有使用者看得到的改動。不做。
- 依賴：0。模型：sonnet（欄位已定）。

## 2. 導覽重排、首頁（最近播放）、音樂庫、本機歌單（design §10.1–§10.3、§10.5）

- [x] `ShellDestination { home, search, library, radio, settings }`；三種導覽元件；每個目的地一個巢狀 `Navigator`；返回鍵、Esc、再點目前導覽項回根；App 開在首頁。
- [x] 首頁：最近播放區塊（20 筆、查看全部開歷史頁）、首次啟動引導（§17 第 16 條；沒通過就照確認結果改）、全空時的說明。
- [x] 音樂庫：頂端「歷史」、歌單卡清單／格狀、拖曳排序、工具列「新增」；建立與編輯對話框（名稱、描述、封面）；刪除確認；歌單卡選單的全部加入佇列、隨機加入、編輯、刪除。
- [x] `lib/library/playlist_service.dart`（只有本機歌單的部分：建立、編輯、刪除、排序、加入佇列）。
- 測試：五個導覽項 × 三種寬度（取代 ADR 0031 的四項測試）；App 開在首頁；巢狀導覽的返回與 Esc；快捷鍵群組（Ctrl+F 切到搜尋並聚焦、F6 三區）；首頁的引導出現與消失；音樂庫的建立、排序、刪除；10,000 首上限對「全部加入佇列」（`QueueFull`）；guideline；`toast_layering_test.dart` 加巢狀導覽裡的頁。
- 實測（重播）：Android：建兩張歌單、改名、排序、刪一張；從首頁「查看全部」進歷史再返回；清掉 dev 資料後首頁出現引導。Windows：large 寬度的導覽抽屜與巢狀導覽、Esc 返回。
- 依賴：1。模型：opus（導覽與首頁、音樂庫的版面與互動沒有定稿）。

## 3. 歌單詳情與「加入歌單…」（design §10.4、§10.6）

- [x] 詳情頁：標頭、全部、隨機加入、點一首臨時播放、分 P 分組、本機歌單的拖曳重排與「從歌單移除」、`sourceUnavailableProvider` 的標示。
- [x] `TrackRowMenu` 加「加入歌單…」：對話框（勾選多張、新增歌單）；套用在搜尋、歷史、佇列、詳情。
- 測試：詳情的 widget 測試（分組、重排寫入、移除、只有本機歌單有這兩項、10,000 上限）；加入歌單對話框（新增後立即可勾、加入後提示）；guideline。
- 實測（重播）：Android：從搜尋加三首（含一首 `fmp-test` 的分 P）到本機歌單 → 詳情看分組 → 重排 → 移除一首 → 全部加入佇列、隨機加入。
- 依賴：2。模型：opus（詳情頁的版面與分組呈現沒有定稿）。

## 4. 首頁的我的歌單與電台區塊（design §10.2）

- [x] 我的歌單（20 張、查看全部切到音樂庫）、電台（20 個、四種狀態、點一下 `playLive`、查看全部切到電台）。
- 測試：區塊的有無（沒有內容不顯示）、查看全部切到對的目的地、電台狀態標記；guideline。
- 實測（重播）：Android：`fmp-test` 的直播間加兩個電台 → 首頁電台區塊點一個播放 → 查看全部。
- 依賴：2。模型：sonnet（照 PR 2 定下的首頁區塊樣式；要新的版面決定時停下回報）。

## 5. 多選（design §10.7）

- [x] `lib/ui/tracks/track_selection.dart`：進入、選取列、全選、Shift 範圍（桌面）、Esc 離開；動作：加入佇列、加入歌單、從本機歌單移除。
- [x] 用在歌單詳情、搜尋、歷史。
- 測試：三頁進入與離開、動作的結果、快捷鍵（Ctrl+A 只在選取模式內、輸入框裡不作用）、guideline。
- 實測（重播）：Android：搜尋結果多選三首加入歌單；歷史多選加入佇列；詳情多選移除。Windows：Shift 範圍選取、Ctrl+A。
- 依賴：3。模型：opus（多選的互動模式是新的，跨四頁共用）。

## 6. `importPlaylist` 契約與 `fmp-test`（design §4.2、§4.3、§4.9）

- [x] `TrackSummary.partIndex`、`parentTitle`（d.ts、`sourceDtoShapes`、`checks.dart` 的 `trackFields`、寫進 `TrackInfo`）。
- [x] `ImportPlaylistExports`、`SourcePlugin.playlistFromUrl`／`importPlaylist`、DTO 與驗證、`FmpChecks.importPlaylist`（輸入 `{url}`）。
- [x] `fmp-test`：design §4.9 的 `importPlaylist` 歌單與 Mix 網址。
- 測試：`import_playlist_capability_test.dart`（匯出與能力一致、回傳值驗證、`mixSeed` 只給宣告 `mix` 的插件、`cursor` 空字串拒收、分 P 兩欄只給一個拒收）；`type_definitions_test.dart`（含變異）；`checks_test.dart`、`contract_runner_test.dart` 的 `an importPlaylist check…`（含沒宣告能力、期望不符、改無關處不紅）；`health_check_test.dart`、`dev_case_runs_test.dart` 的 `an importPlaylist case`；`test_plugin_bundle_test.dart` 的新歌單。
- 實測：沒有使用者看得到的改動（匯入在 PR 8b）。不做。
- 依賴：0。模型：sonnet（形狀已定）。

## 7. ★ YouTube `importPlaylist`（design §4.3）

- [x] fmp-plugins：`youtube` 的 `playlistFromUrl`（一般清單、`list=RD…`、`mix:<videoId>`）、`importPlaylist`（`browse` 續取、`setVideoId`、`unavailable`、不給 `total`）、私人歌單的 `required` 重送與 Node 測試、`checks.json` 的 `importPlaylist`（公開清單，命令列錄）、manifest 升版、index 重產、`FMP_REF`。
- 實測（真實，匿名，開頭先做）：一張公開清單（超過一頁）的 `playlistFromUrl` 與全部頁各一次，記筆數與「被隱藏的影片」的差；一個 `mix:` 簡寫的 `playlistFromUrl` 一次（不發請求）。量一次插件載入時間（YouTube 插件已約 800 KB），寫進 PR 描述。
- 依賴：6。模型：sonnet（舊 `youtube_source.dart`、`youtube_mix_shorthand.dart` 是規格；回應形狀與舊版不同時停下回報）。

## 8a. 匯入與刷新引擎（design §5.1、§5.2、§3.1）

- [x] schema v16：`playlist_remote`；repository 加刷新用的方法（開始刷新取代際、寫一頁、完整套用、標部分完成、標失敗與狀態）。
- [x] `lib/library/playlist_importer.dart`（依序問、重新匯入＝刷新、第一頁成功才建列）、`playlist_refresher.dart`（FIFO 鎖、比對、代際、過期、取消）。
- [x] `fmp_layer_imports`：`library/` 那半條（design §2.2）。
- 測試（**先寫測試**）：ADR 0019 §如何確認的刷新差異全部（新增、移除、順序、元資料、覆寫旗標、部分失敗不移除、重複影片保留、來源失效停止、重新匯入不覆寫設定）；比對鍵兩種；完整性三條件各缺一個是部分完成；中途被殺（某頁之後丟例外）後再刷一次結果正確；代際過期不寫；`writable` 為 `null` 保留；FIFO 鎖（手動與排程同時只有一張）；第一頁失敗不建列；migration 三種；一萬首歌單的刷新耗時寫進 PR 描述；lint 的雙向變異。
- 實測：沒有使用者看得到的改動。不做。
- 依賴：1、6。模型：sonnet（演算法與案例已在 design 寫定；測試寫不出 design 的行為時停下回報）。

## 8b. 匯入對話框、手動刷新、狀態列（design §5.3、§10.4、§10.8）

- [x] 音樂庫工具列「匯入」與對話框（進度、錯誤）；歌單卡與詳情的「刷新」；詳情的狀態列（design §5.3 的六種）；「已失效」標記；匯入歌單沒有重排與移除。
- 測試：對話框（認得、不認得、第一頁失敗）；狀態列六種；手動刷新失敗的提示與離線字樣；guideline。
- 實測：重播（Android）：`fmp-test` 的 `pl-basic`、`pl-grow`（刷新三次看新增、移除、倒序）、`pl-partial`、`pl-gone`（重試）、`pl-auth`（登入後重試）、`pl-unavailable`、`pl-parts`。真實（匿名，Android）：匯入 PR 7 的那張 YouTube 公開清單、手動刷新一次。
- 依賴：3、8a（真實部分用 7）。模型：sonnet（對話框與狀態列用既有元件；要新的版面決定時停下回報）。

## 9. ★ B 站、網易 `importPlaylist`（design §4.3）

- [x] fmp-plugins：`bilibili`（公開收藏夾、多 P 展開帶 `cid`／`partIndex`／`parentTitle`、展開後不給 `total`、私人收藏夾的重送）、`netease`（歌單詳情、其餘以 id 分批補、`163cn.tv` 短網址、私人歌單的重送）；各自的 Node 測試、`checks.json`、版本、index、`FMP_REF`。
- 實測（真實，匿名，開頭先做）：B 站一個公開收藏夾（含一支多 P 影片）、網易一張公開歌單，各全部頁一次；記 B 站有沒有要 WBI 簽名或觸發風控、網易補齊的批次數。之後在 App 各匯入一次、手動刷新一次（Android）。
- 依賴：6。模型：sonnet（舊 `import_service.dart`、`netease_source.dart` 是規格）。

## 10. `playlist-refresh` 工作與每張歌單的間隔（design §6.1、§10.5）

- [x] `lib/library/playlist_refresh_job.dart`（`FmpApp` 常駐、登記一次、到期選擇、全部失敗才丟錯）；編輯對話框的自動刷新間隔（匯入歌單）；間隔改成不啟用、插件停用或移除時取消進行中的那張。
- [x] `app/AGENTS.md` § 排程器的工作清單加它。
- 測試：排程器的假時鐘模式：到期條件（`active`、間隔不為空、插件在清單上、`last_refreshed_at` 空或已過）、依 `last_refreshed_at` 由舊到新、單張失敗繼續、全部失敗退避、沒有到期算成功、失敗的那張不寫 `last_refreshed_at`、取消；編輯對話框寫入間隔。
- 實測（重播，Android 與 Windows 各一次：生命週期是平台各自的）：匯入 `fmp-test` 的 `pl-grow` → 以 `sqlite3`（Windows）／`adb exec-out run-as … cat` 拉回改寫再推（Android）把 `last_refreshed_at` 改成 25 小時前 → 重啟 → log 有 `Playlist refresh finished`；切到背景（Android）或最小化（Windows）時沒有工作執行。
- 依賴：8b。模型：sonnet（照 `RadioStatusJobs`）。

## 11. Mix 歌單（design §5.4）

- [x] 匯入對話框的 `mixSeed` → `mix({seed})` 一次 → 建 `kind = mix` 的列；歌單卡與詳情的「Mix 播放」（`startMixFrom`）、編輯名稱、刪除；插件不可用時停用。
- 測試：建立（插件沒宣告 `mix` 時不可能拿到 `mixSeed`，PR 6 已守）、Mix 播放取代佇列並進 `mix` 模式、詳情不列曲目、停用的狀態。
- 實測：重播（Android）：`https://fmp.test/mix/<id>` 建一張 → Mix 播放 → 補歌一次。真實（YouTube 匿名，Android）：`mix:<videoId>` 建一張 → Mix 播放一首。
- 依賴：7、8b。模型：sonnet（M3 的 `startMixFrom` 已有）。

## 12. 帶憑證錄製與 `mutates`（design §4.7、§12）

- [x] `PluginCheck.mutates`；健康檢查、`record_test.dart`、`DevCaseRuns` 的真實與錄製模式略過並顯示「略過：會改動遠端」，重播照跑。
- [x] `runIsolatedCase` 在真實與錄製模式、`requiresLogin` 的案例帶該插件的已存憑證；`recordCase` 對所有 `requiresLogin` 案例以 `accounts` 列換值。
- [x] `app/AGENTS.md` § 插件「已知限制」的那一句改寫；`.trellis/spec/app/plugins/index.md` 的錄製段。
- 測試（測試檔內雙向變異）：design §12 的閘門；`mutates` 在四個地方不呼叫插件（以會記錄呼叫次數的假插件）、在重播照跑；隔離環境在重播模式不帶憑證。
- 實測：沒有使用者看得到的改動；Debug 頁健康檢查的「略過」字樣在 PR 14 有 `mutates` 案例時一起看。
- 依賴：0。模型：sonnet（規則已定；安全面由 opus 審查攻）。

## 13. ★ `libraryRead` 與帳號頁「歌單」（design §4.4、§7.3）

- [x] FMP：`LibraryReadExports`（`libraryPlaylists`，`libraryLiveRooms` 的匯出檢查先加、呼叫在 PR 15）、DTO、`FmpChecks.libraryRead`（`requiresLogin`）；帳號頁的「歌單」按鈕與頁（已匯入標示、匯入所選、進度、部分失敗）；`fmp-test` 的 `libraryPlaylists`。
- [x] fmp-plugins：三個插件的 `libraryPlaylists`（B 站收藏夾清單、YouTube 帳號清單、網易使用者歌單；`writable`）、Node 測試、`checks.json`（App 內錄製後刪減並標 `meta.edited`，或手寫）、版本、index、`FMP_REF`。
- 測試：`library_read_capability_test.dart`（匯出、`requiresLogin` 的案例形狀、回傳值驗證、`libraryLiveRooms` 沒宣告 `live` 拒載）；帳號頁的 widget 測試（只在已登入且宣告時出現、已匯入停用勾選、部分失敗列出）；契約與健康檢查的 `a libraryRead case`。
- 實測：
  - 重播（Android）：`fmp-test` 登入 → 歌單 → 匯入 `pl-auth`。
  - 真實（擁有者登入、擁有者在場，Android）：三個平台各：帳號頁「歌單」列出一次 → 匯入私人的「FMP 測試」一次 → 關掉「以登入身分瀏覽與播放」→ 手動刷新那張一次（網路紀錄看到第一次 `credentials: false`、重送 `true`，design §4.3）→ 開關恢復。截圖不含帳號資訊與私人歌單內容。
  - 錄製（Windows，擁有者登入）：三個插件的 `libraryRead` 案例以 App 內工具錄一次，刪減到只剩插件讀的欄位，`meta.edited` 寫明；人工逐檔看過沒有帳號名稱、email、手機號。
- 依賴：8b、12。模型：sonnet（頁面是勾選清單，照插件頁的列樣式；要新的版面決定時停下回報）。

## 14. ★ `libraryWrite` 與遠端操作（design §4.5、§7.1、§7.2）

- [x] FMP：`LibraryWriteExports`、manifest 檢查（沒宣告 `libraryRead` 拒收）、`results` 驗證、`FmpChecks.libraryWrite`（`requiresLogin`＋`mutates`）；曲目選單與多選的「加入遠端歌單…」（對話框、在遠端新增、逐項結果）、詳情的「從遠端歌單移除」（確認框）、寫後刷新；`fmp-test` 的 `libraryWrite`。
- [x] fmp-plugins：三個插件的 `createPlaylist`、`addToPlaylist`、`removeFromPlaylist`（去重、B 站 bvid→aid、YouTube `setVideoId`）、Node 測試、`checks.json` 的 `libraryWrite`（`mutates`，fixture 手寫）、網易 `X-Real-IP` 的處理寫進 README、版本、index、`FMP_REF`。
- 測試：`library_write_capability_test.dart`；入口條件（插件、登入、多選時同一插件、`writable`）；結果提示三種；移除確認框、`removed`／`notPresent` 刪本地、`failed` 列出；寫後刷新排進同一個鎖；`mutates` 的案例在健康檢查顯示略過。
- 實測：
  - 重播（Android）：`fmp-test` 登入 → 加入 `pl-auth`（`added`）→ 再加一次（`alreadyPresent`）→ 加 `fail`（`failed`）→ 在遠端新增歌單 → 匯入的 `pl-auth` 詳情「從遠端歌單移除」。
  - 真實（擁有者登入、擁有者在場，Android，決定 4）：三個平台各：在「FMP 測試」加入一首、移除同一首各一次；網易先以「不帶 `X-Real-IP`」做（design §4.5），不行才帶。**不做真實的「在遠端新增歌單」**。
  - Debug 頁健康檢查：三個插件的 `libraryWrite` 顯示「略過：會改動遠端」。
- 依賴：13。模型：sonnet（流程已定；寫入失敗的形狀與舊版不同時停下回報）。

## 15. ★ `libraryLiveRooms` 與從帳號匯入電台（design §4.4、§7.4）

- [x] FMP：`libraryLiveRooms` 的呼叫、帳號頁「⋯」的「從帳號匯入電台」、摘要提示；`fmp-test` 的 `libraryLiveRooms`。
- [x] fmp-plugins：`bilibili` 的 `libraryLiveRooms`（粉絲勳章牆，舊 `fetchMedalWall`）、Node 測試、版本、index、`FMP_REF`（`checks.json` 不加：每能力一條，`libraryRead` 的那條已是 `libraryPlaylists`）。
- 測試：只在匯出且宣告 `live`、已登入時出現；重複的計數；寫入 `radio_stations`。
- 實測：重播（Android）：`fmp-test` 匯入五個直播間（再匯入一次全部「已在清單」）。真實（擁有者登入，Android）：B 站匯入一次。
- 依賴：13。模型：sonnet。

## M4a 驗收（15 之後）

### 兩平台端到端（Android 模擬器與 Windows 各一次，dev flavor）

- **模式**：真實（三個官方插件、擁有者的帳號，決定 4）只做下列步驟；錯誤、部分完成、排程用 `fmp-test`（重播）。擁有者在場：第 5–7 步。
- **步驟**：
  1. 清掉 dev 資料目錄（Android 解除安裝 dev 重裝；Windows 刪 dev 的 application support 與 WebView 資料）→ 啟動 → **首頁**出現首次啟動引導 → 裝三個官方插件；以 `--fmp-dev-plugin` 裝 `fmp-test`。
  2. 導覽五項各點一次；音樂庫建一張本機歌單 → 搜尋頁多選三首加入 → 詳情重排、移除一首 → 全部加入佇列、隨機加入 → 首頁「我的歌單」看得到；音樂庫頂端「歷史」可開。
  3. 匯入：YouTube 公開清單、B 站公開收藏夾（含多 P）、網易公開歌單各一張 → 詳情分 P 分組 → 各手動刷新一次。
  4. Mix：`mix:<videoId>` 建一張 → Mix 播放。
  5. 帳號頁登入三個平台 → 「歌單」匯入私人的「FMP 測試」→ 關掉開關後刷新仍成功（重送）。
  6. 對「FMP 測試」加入一首、移除同一首（三平台各一次）→ 本地副本跟著更新。
  7. B 站「從帳號匯入電台」→ 首頁電台區塊看到。
  8. 重播：`fmp-test` 的 `pl-partial`、`pl-gone`、`pl-auth`（登出後）、`pl-unavailable` 的狀態列；排程（PR 10 的到期做法）。
  9. 離線：音樂庫、詳情、首頁照常；手動刷新顯示離線字樣。
- **證據**：`research/m4a-acceptance.md`（平台、模式、真實請求清單；截圖不含帳號資訊與私人歌單內容）。

### ADR 的測試

| ADR | 項目 | 在哪個 PR |
|---|---|---|
| 0019 §如何確認 | 刷新差異九項（新增、移除、順序、元資料、覆寫旗標、部分失敗不移除、重複影片保留、來源失效停止、重新匯入不覆寫） | 8a |
| 0019 §如何確認 | 外鍵連帶刪除、孤兒清理只刪無人參照的、刷新中途失敗後的一致性 | 1、8a |
| 0019 §如何確認 | `importPlaylist` 分頁與完整性回報、`libraryWrite` 的錯誤對應（契約） | 6、7、9、14 |
| 0017 | `playlist-refresh` 在假時鐘下：看不見與離線不跑、到期才跑、一次一張、全部失敗退避、取消 | 10 |
| 0028／0032 | 四個能力中 `importPlaylist`、`libraryRead`、`libraryWrite` 的型別一致、匯出與能力、回傳值驗證、`checks.json` 格式；`mutates` 只重播；`requiresLogin` 案例的帶憑證與換值（雙向變異） | 6、12、13、14、15 |
| 0033 | 五個導覽項 × 三種寬度、App 開在首頁、首頁的引導、詳情的狀態列、多選、曲目選單的兩個新項目只在條件成立時出現 | 2、3、5、8b、14 |
| 0031（M4 接手的） | 首頁電台區塊、Mix 歌單的 Mix 播放、從帳號匯入電台 | 4、11、15 |
| 0012 | 私人歌單重送 `required`（各插件 Node 測試）；`libraryRead`／`libraryWrite` 未登入不出現入口 | 7、9、13、14 |
| 0018 | 歌單「全部」與「隨機加入」的 10,000 首上限整批拒絕 | 2、3 |

- [x] 上表逐項在 PR 描述或測試檔找到對應，寫進 `research/m4-adr-tests.md` 的 M4a 段（48 項：47 有、1 部分；缺口在該檔末段）。
- [ ] `milestones.md` 的 M4a 狀態與勾選。
- [x] `app/AGENTS.md` 的資料層、插件、排程器、介面、音樂庫段落與實際一致（逐條有閘門或標明「沒有閘門，review 時看」），opus 審查一次。

## M4b 外部匯入、排行與備份

## 16. 匹配核心與繁簡字表（design §8.1、§8.2）

- [x] `unorm_dart`、`string_similarity`（版本核對）；`externalPackageOwners`。
- [x] `lib/core/matching/`：正規化、評分、`rank`；`app/tool/opencc/`（釘 commit 的 `TSCharacters.txt`、`LICENSE`、產生器）、`ts_characters.g.dart`；`lib/app/licenses.dart` 登記授權。
- [x] 測試語料（約 50 對，手寫，不連網）與校準後寫死的權重、門檻。
- 測試：ADR 0019 §如何確認的評分案例（全半形、繁簡、括號、時長門檻、多歌手；自動與手動重搜同分）；語料全綠；重新產生的字表等於已提交的；已知字對；授權登記；lint 雙向變異。
- 實測：沒有使用者看得到的改動。不做。
- 依賴：0（可與 M4a 平行）。模型：opus（權重與門檻要以語料校準，結果影響之後每一次匹配與 M7 的歌詞）。

## 17. ★ Spotify 插件（design §4.8）

- [ ] fmp-plugins：`spotify/`（manifest 1.0.0、`importPlaylist`、`never`、`checks.json`、命令列錄的 fixture、README）、index。
- [ ] FMP：`officialPluginIds` 加 `spotify`。
- 實測（真實，匿名，開頭先做）：一張公開歌單（超過 100 首）的 embed 頁一次，記 `__NEXT_DATA__` 是否還在、是否完整。抓不到就停下回報（可能牽動決定 1 的範圍）。之後在 App 匯入一次（PR 19 合併後的驗收再做完整流程）。
- 依賴：6、M4a 驗收。模型：sonnet（舊 `spotify_playlist_source.dart` 是規格）。

## 18. ★ QQ 插件（design §4.8）

- [ ] fmp-plugins：`qqmusic/`（`musics.fcg`＋自簽 `sign`，`pageSize = 1000`）；FMP：`officialPluginIds` 加 `qqmusic`。
- 實測（真實，匿名，開頭先做）：一張公開歌單一次，記 `sign` 是否仍被接受。
- 依賴：6、M4a 驗收。模型：sonnet（舊 `qq_music_playlist_source.dart`、`qq_music_sign.dart` 是規格）。

## 19. 匯入預覽、匹配結果、匹配目標設定（design §3.1、§8.3、§8.4、§10.9、§10.10）

- [ ] schema v17（或 v18）：`match_results`、`track_origins`、`source_settings` 兩欄；孤兒查詢加 `match_results`。
- [ ] `lib/library/external_import.dart`；匯入對話框接到預覽頁；預覽頁（進度、取消、改選、重搜、排除、建立歌單）。
- [ ] 設定頁「音樂庫」區（這一區第一次出現）：匹配目標音源的拖曳與勾選。
- [ ] `fmp-test-meta`（dev asset）。
- 測試：`ExternalImport`（沿用 `match_results` 不搜尋、合併前 5、門檻、搜尋失敗不中斷、取消後不寫、確認的 transaction 寫入三張表、未匹配不進歌單）；migration 三種；孤兒；設定的拖曳寫 `match_rank`、取消勾選寫 `match_target`；預覽頁的 widget 測試；guideline；一千首歌單的匹配以假插件量一次（寫進 PR 描述）。
- 實測：重播（Android）：`fmp-test-meta` 的 `meta-basic` → 預覽 → 改選一首、重搜一首、排除一首 → 建立 → 再匯入一次（全部沿用、沒有搜尋）。真實（匿名，Android）：Spotify 與 QQ 各一張公開歌單（PR 17、18 的那張）走完一次，記首數、匹配成功數、耗時。
- 依賴：8b、16、17（或 18）。模型：opus（預覽頁的版面與互動沒有定稿）。

## 20. ★ `charts` 契約、排行快取與工作（design §4.6、§6.2、§9.1、§3.3）

- [ ] schema v18（或 v17）：`network_settings.chart_refresh_interval_minutes`、`chart_settings`；Notifier 與設定頁「網路」區的排行間隔。
- [x] FMP：`ChartsExports`、DTO、`FmpChecks.charts`；`CacheCategory.chart`；`lib/charts/`（快取、`charts:<pluginId>` 工作、記憶體的單榜單失敗標記、`runNow`）；`fmp_layer_imports` 的 `charts/` 那半條；移除插件刪 `chart_settings` 列；`fmp-test` 的 `charts`。
- [x] fmp-plugins：三個插件的 `chartList`、`chart`（舊版的來源與排序）、`checks.json`（命令列錄）、版本、index、`FMP_REF`。
- 測試：`charts_capability_test.dart`；排程（全停用不登記、單榜單失敗不退避、全部失敗退避、間隔改變重新登記）；快取（先顯示快取與「更新於」、停用刪快取、移除插件刪）；migration 三種；設定的「網路」區；契約與健康檢查的 `a charts case`；lint 雙向變異。
- 實測：重播（Android）：沒有 UI 的部分以 Debug 頁的 log 看工作執行；真實（匿名）：三個插件各 `chart` 一次（命令列錄製即是）。首頁的呈現在 PR 21 驗。
- 依賴：0；契約與工作可在 M4a 期間先做（只有設定頁「網路」區多一列，沒有其他 UI），合併不擋 M4a 驗收。模型：sonnet（照電台工作）。

## 21. 首頁排行、探索頁、首頁排行設定（design §9.2、§9.3、§10.10）

- [ ] 首頁排行區塊（每個啟用榜單前 5、查看全部、刷新）；探索頁（分頁、完整清單、多選）；設定頁「音樂庫」區的「首頁排行」（拖曳、勾選，停用即刪快取並重新登記工作）。
- 測試：全停用沒有區塊；順序照設定；探索的分頁與多選；停用後快取被刪、工作被移除；離線時顯示快取或離線空狀態；guideline。
- 實測：重播（Android）：`fmp-test` 的 `hot`、`new`、`broken` → 首頁、探索、多選加入歌單 → 停用 `new`。真實（匿名，Android）：首頁看到三個插件的榜單一次。
- 依賴：4、5、20、M4a 驗收。模型：opus（首頁排行區塊與探索頁的版面沒有定稿）。

## 22. 備份與還原（design §11，ADR 0034）

- [ ] `DatabaseBackups` 的 `export`、`stage`、`carryOver`、`restoreStaged` 與表的歸類清單；`lib/app/backup.dart`；設定頁「備份與還原」區；Debug 頁的還原改走同一條（§17 第 15 條）、`DataReset.restoreAndRestart` 不再清憑證。
- 測試：ADR 0034 §如何確認的全部（以真的檔案資料庫）；`data_reset_test.dart` 跟著改（還原保留憑證）；確認框的 widget 測試；表的歸類閘門的雙向變異。
- 實測（Android 與 Windows：檔案對話框與重啟是平台各自的）：兩平台各：登入 `fmp-test`、建歌單 → 匯出 → 另一平台還原（`adb push` 或共用資料夾）→ 確認框列出插件與網域 → 重啟後歌單在、`fmp-test` 仍登入、輸出裝置是這台的、`backups/` 有還原前的自動備份。另各試一份較新版的檔（把 `user_version` 改大）被拒、資料不變。Android 的 `.db` 篩選（design §11）。
- 依賴：19、20、21（所有加表的 PR）。模型：sonnet（流程已定；安全面由 opus 審查攻）。

## M4b 驗收（22 之後）

### 兩平台端到端（Android 模擬器與 Windows 各一次，dev flavor）

- **模式**：真實（Spotify、QQ 匿名；三個官方插件的排行匿名）只做下列步驟；其餘重播。
- **步驟**：
  1. Spotify、QQ 各匯入一張公開歌單 → 預覽頁改選一首、重搜一首、排除一首 → 建立 → 播一首。
  2. 同一張再匯入一次：沿用先前的匹配（沒有搜尋請求）。
  3. 設定「音樂庫」：匹配目標拿掉網易、調順序 → 重搜一首看到變化。
  4. 首頁排行三個插件 → 查看全部進探索 → 多選加入歌單 → 停用一個榜單（首頁不見、快取刪掉）→ 排行間隔改成關閉再改回。
  5. 備份：匯出 → 在另一平台還原 → 登入保留、插件確認框、自動備份在。
  6. 離線：首頁排行顯示快取與「更新於」；探索沒有快取的分頁顯示離線空狀態。
- **證據**：`research/m4b-acceptance.md`。

### ADR 的測試

| ADR | 項目 | 在哪個 PR |
|---|---|---|
| 0019 §如何確認 | 評分核心：全半形、繁簡、括號、時長門檻、多歌手；自動與手動重搜同分 | 16、19 |
| 0019 §決定 5 | 匯入預覽：前 5 名、第一名自動選、改選、重搜、排除；寫 `match_results`、`track_origins`；沿用不重算 | 19 |
| 0016 §決定 4 | 排行快取先顯示並標「更新於」、只抓啟用的、停用刪快取 | 20、21 |
| 0017 | `charts:<pluginId>`：全停用不登記、單榜單失敗不退避、間隔關閉只手動 | 20 |
| 0028／0032 | `charts` 的型別、匯出、回傳值、`checks.json`；Spotify、QQ 的契約；lint `fmp_source_id_literal` 加兩個 id | 17、18、20 |
| 0033 | 首頁排行區塊、探索頁、設定頁「音樂庫」區；`match_results` 算孤兒參照者 | 19、21 |
| 0034 | 匯出不含排除的表與裝置值、不含假 cookie 的位元組；還原的拒絕三種、保留登入、自動備份、確認框；表的歸類閘門 | 22 |

- [ ] 上表逐項寫進 `research/m4-adr-tests.md` 的 M4b 段。
- [ ] `milestones.md` 的 M4b 狀態與勾選；本任務 `finish`、`archive`。

## 留下的後續

（各 PR 合併時寫在這裡，最新的在上面。）

- **PR 15 → 之後**：
  - B 站勳章牆改用批次端點 `get_status_info_by_uids`（舊版每個主播各問一次 `getRoomInfoOld`）：宿主匯入後不再呼叫 `liveStatus`，房間的顯示資料要一次拿齊。實測（Windows，擁有者帳號）一次匯入 90 個：勳章牆 1 次、批次 2 次。
  - 匯入寫到一半失敗時只提示「無法匯入電台：原因」，沒說已加了幾個（已寫入的留著，再匯入一次會算成「已在清單」）；要不要改看實際使用。
  - 第一個「選填匯出」：manifest 只說「可以匯出」，`SourcePlugin.exportsLibraryLiveRooms` 讀執行期的匯出表；之後再有選填匯出照這個做。

- **PR 14 → 之後**：
  - **寫後刷新延後 60 秒**（design §7.1、§7.2 原寫立刻刷新）：YouTube 寫後讀有延遲，實測約 40 秒；立刻刷新時，加入的看不到、移除的會被舊清單加回來。本地刪除仍立即做。B 站、網易立刻讀就一致。
  - 新建遠端歌單一律預設私人（契約沒有隱私欄位；舊版 YouTube 是 unlisted、B 站與網易對話框預設公開）。擁有者之後要改再說。
  - 網易寫入不帶 `X-Real-IP`、不設 `os=linux` 可以（實測）。
  - 沒實測到的：B 站重複加入的 11201（`alreadyPresent`）、網易重複加入的碼、YouTube 空清單或剛建清單的 `VL<id>` 形狀（插件現在回 `NotFound`）、對別人的歌單寫入被拒時的碼。
  - 健康檢查「略過：會改動遠端」沒在實機看到：開發入口裝的插件沒有 `checks.json`；Windows 對真實插件跑健康檢查會發一整輪真實請求。由 `health_check_test.dart` 守。
  - 開發資料夾載入的插件在啟動時取代已安裝的版本，啟動刷新跑到一半被 dispose（log：`Failed to refresh the credentials`、`The plugin runtime was disposed during loginRefresh`）。只在開發資料夾生效時發生，之後的請求正常。
  - B 站分 P 曲目的「從遠端歌單移除」會移掉整支影片（收藏夾以影片為單位），插件 README 已寫。

- **PR 13 → PR 14、之後**：
  - YouTube、網易的 `importPlaylist` 不給 `writable`（null＝這次不知道）：從帳號頁匯入的以 `libraryPlaylists` 的值帶進來（`importPlaylistId(writable:)`），**以網址匯入的自己的歌單 `writable` 一直是 0**，「從遠端歌單移除」不會出現。YouTube 帶憑證的 `browse VL<id>` 回應有沒有可用的旗標沒有實測；網易可以在帶憑證時比對 `creator.userId` 與 `account/get`（多一個請求）。PR 14 碰到時決定。
  - FMP 的遮蔽認不出 YouTube 回應 `serviceTrackingParams` 裡 `{"key":"visitor_data","value":…}` 這種形狀（國家碼）：fmp-plugins 這次手動換成 `***`，之後重錄還要手動，或在 FMP 的 redactor 加規則。
  - 遮蔽器對很深的 JSON 值一律換成 `<nested too deep>`：YouTube 自己的清單的 `deletePlaylistEndpoint` 在約 20 層，fixture 裡留空物件（插件只看鍵）。
  - YouTube `libraryPlaylists` 的續取（超過一頁）沒有實測（測試帳號只有三張）。
  - Windows 的 `toast_layering_test.dart` 本機沒跑（會清掉擁有者的登入），交給 CI；Android 跑過。

- **PR 20（fmp-plugins）→ PR 21、M4a 驗收**：
  - B 站 `ranking/v2` 要 WBI 簽名加 `web_location=333.934`：不簽的匿名請求連三次 -352，簽了第一次就成功（fmp-plugins #19）。舊版 `getRankingVideos` 不簽，曾經可用。
  - YouTube 的觀看數在 WEB context 寫成 `235K`、`14M`（不帶 views），解析兩種都認；`hl` 是 `en`，在地化格式變了會退回清單原順序。
  - 錄下的 YouTube fixture 的 `visitorData`／`x-goog-visitor-id` 解碼後帶錄製地的國家碼（既有 fixture 也一樣，遮蔽閘門不管）；要不要遮由擁有者決定。

- **PR 20（FMP 端）→ PR 21**：
  - 設定頁「網路」區的快取用量只列封面；`watchUsage` 已有 `chart` 鍵，PR 21 讓排行上畫面時加一列（ADR 0016 §決定 3）。
  - 「清除快取」不會更新 `chartCacheRevisionProvider`，讀 `chartContentProvider` 的畫面會顯示清掉前的內容到下次工作寫入；PR 21 接上 UI 時處理。
  - `CacheStore.get` 不更新最後存取時間，排行實際上依寫入時間淘汰；每小時重寫，影響小。
  - `chartList` 失敗時照樣登記、交給排程器退避（審查改的；登記當下不知道啟用集合時不刪快取）。

- **PR 5 → 之後**：
  - 歷史頁的單獨分 P 仍是一行，會截掉「· P2」（詳情頁已改兩行；佇列列高固定不改）。要不要跟進，看實際使用。
  - 搜尋頁選取中按 Ctrl+F 或再點「搜尋」導覽項不會離開選取：外殼的 `popUntil(isFirst)` 碰不到根頁上的 `LocalHistoryEntry`。要統一得改外殼。
  - 歷史頁全選後有新紀錄進來，重讀「已載入的筆數」會讓最舊的已選項目掉出範圍（選取數少 1）。屬於分頁規則，沒改。
  - 多選「加入佇列」在取分 P 途中按取消，取回後仍會加入佇列。輕微，沒改。
  - PR 3 的「單獨分 P 兩行」（詳情頁）與 PR 2 的「格狀拖曳替代操作」（螢幕閱讀器的移動動作；鍵盤排序不做，清單版也沒有）已在 PR 5 處理。

- **PR 3 → PR 8b、fmp-plugins**：
  - 音樂庫卡片的「編輯」對匯入歌單也開放，但還不會設 `*_overridden`；PR 8b 有匯入入口時一起做（design §10.5），並處理匯入歌單封面有多張、在不同網域時 `PlaylistCover` 只拿第一張找插件的問題。
  - 歌單詳情裡單獨的分 P 列只顯示一行，「影片 · P2 標題」在手機寬度會截掉「· P2…」（Android 實機）；PR 5 碰到詳情列時順便決定要不要兩行。
  - YouTube 插件的 `description` 沒寫「匯入播放清單」（B 站、網易已更新）；下一個 YouTube 插件 PR（13）順便改。

- **PR 2 → PR 3、5**：
  - 自訂封面（圖片網址）PR 2 沒做：網址的網域屬於某個已安裝插件的允許網域才收（經那個插件的媒體 client 讀），否則提示；PR 3 實作。
  - 首頁「最近播放」的卡片沒有選單；PR 3 加 `TrackRowMenu`（「加入歌單…」）時一併套用。
  - expanded 以上的格狀拖曳沒有螢幕閱讀器／鍵盤的替代操作（清單版有 `ReorderableListView` 的上移／下移）；PR 5 或之後決定要不要加自訂 semantics actions。
- **PR 7、9 → M4a 驗收、PR 13、14**：
  - B 站多 P 展開沒有真實驗證（實測的官方收藏夾全是單 P）；M4a 驗收在 App 匯入一個含多 P 影片的公開收藏夾。
  - B 站 `ftype=collect&ctype=21`（訂閱的合集）的網址可能被當成收藏夾 `fid`，沒有實測；遇到再處理。
  - YouTube、B 站、網易的私人歌單與不存在歌單的真實回應沒有實測；PR 13 擁有者登入時順便驗。
  - B 站收藏夾增刪（`fav/resource/deal`、`batch-del` 的 `<aid>:2`）出自舊版程式碼，沒有實測；PR 14 驗。

- **PR 8a → PR 7、10**：
  - 比對鍵分兩池：有 `remote_item_id` 的既有項目只會被同一個 id 比到。PR 7 實測：YouTube 匿名回應沒有 `setVideoId`，三個官方插件都不給 `remoteItemId`，所以不會在兩池之間跳；PR 14 的移除改用影片／歌曲 id。
  - PR 10：排程工作傳 `RefreshTrigger(isCurrent: () => context.isCurrent)`；到期選擇不挑 `sourceGone`／`authRequired`；間隔改成不啟用時的取消。

- **PR 12 → PR 13**：
  - 健康檢查「非 `login` 的 `requiresLogin` 案例在已登入時帶憑證跑」還沒有測試（PR 12 時 `checks.json` 寫不出這種案例）；PR 13 加 `libraryRead` 案例時補。
  - 隔離環境的重播不帶憑證：`libraryPlaylists` 的請求是 `required`，重播時會先得到 `AuthRequired`、到不了 fixture。PR 13 的契約重播要以 fixture 內的憑證狀態或 runner 的假憑證處理，先確認 `contract_test.dart` 怎麼跑 `requiresLogin` 案例。
  - 隔離環境讀空的設定表：「以登入身分瀏覽與播放」開關在開發工具裡不生效（`app/AGENTS.md` 已知限制）。
- **PR 6 → PR 8a**：`app/AGENTS.md` § 插件的 `importPlaylist` 條寫著「`PlaylistImporter` 與刷新器還沒有」，PR 8a 落地時改掉。

## 風險與回滾點

| 風險 | 處理 |
|---|---|
| Spotify embed 頁或 QQ `sign` 已不能匿名用 | PR 17、18 開頭先實測；不行就停下回報，由擁有者決定 M4b 的範圍（決定 1）；插件可以單獨不做，匹配與預覽頁照樣以 `fmp-test-meta` 驗 |
| B 站收藏夾匿名讀取觸發風控或要簽名 | PR 9 開頭實測；以最少的請求確認，失敗時 B 站的公開收藏夾在驗收裡標「只驗到登入後」並請擁有者決定（M1 遇到風控的做法） |
| 刷新引擎在重複影片、代際、中途被殺交錯時出錯 | PR 8a 先寫測試、單獨審查（opus 試著攻破）；刷新不碰匯入歌單以外的資料，最壞是那張歌單內容錯，重新刷新可修 |
| 巢狀 `Navigator` 弄壞快捷鍵、焦點或提示的層級 | PR 2 的 widget 測試與 `toast_layering_test.dart`；Windows 實機看 Esc、F6、Ctrl+F |
| 大歌單的匹配很久（1000 首 × 3 個目標＝3000 次搜尋，以 B 站限流估計十幾分鐘，未量測） | 預覽頁顯示首數、進度與取消（design §8.4）；PR 19 以假插件量一次、真實記一次 |
| 遠端寫入改到擁有者真正的歌單 | 決定 4：只寫「FMP 測試」；`mutates` 讓健康檢查、冒煙、錄製不跑寫入；PR 12 在 PR 14 之前 |
| 錄到的 `libraryRead` fixture 帶帳號資訊進公開的插件庫 | PR 12 的換值閘門＋人工刪減＋`meta.edited`（插件庫 `login_fixtures_test.dart` 擋沒標的） |
| 備份帶著插件腳本，還原不經安裝確認 | 確認框列出插件與網域（ADR 0034 §決定 4）；opus 審查攻這一步 |
| 匯出的備份殘留 cookie（刪除的列留在空閒頁） | 清除後 `VACUUM`；測試在位元組裡找假 cookie |
| Android SAF 篩不到 `.db` | PR 22 實測；改成不篩選、以內容判斷 |
| schema 版本衝突（v15–v18 四個 PR） | 依「順序與相依」排隊合併；後合併的重排版本號與快照 |
| 8 個 PR 動到 `fmp-plugins`，兩個 repo 交錯 | FMP 先合契約；`FMP_REF` 跟著更新；插件 revert 規則見 design §18 |
| M4a 與 M4b 的界線 | M4a 驗收後才開 M4b 的 UI PR；M4b 整個不做時 M4a 仍可交付（design §18） |
