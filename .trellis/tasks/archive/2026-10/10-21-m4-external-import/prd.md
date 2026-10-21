# 匯入預覽、匹配結果、匹配目標設定

## 目標

M4 PR 19（上層 `implement.md` § 19、design §3.1、§5.1、§8.3、§8.4、§10.8、§10.9、§10.10、§17 第 7、8、12、18、19 條，ADR 0014 §決定 9、ADR 0019 §決定 5、6、ADR 0033）：

- 只有 `importPlaylist`、沒有 `resolveStream` 的插件（Spotify、QQ）的歌單，經匯入預覽頁匹配到可播的音源，建成本機歌單。
- 能播的插件的歌單也可以選「配對到其他音源」走同一條路（§17 第 19 條）。
- 設定頁「音樂庫」區加「匹配目標音源」。

上層計畫與 §17 第 19 條都已由擁有者核准（2026-10-15、2026-10-21），本 PR 不需要新的擁有者決定。

## 現況

- 匹配核心（PR 16）在 `lib/core/matching/`：`score`、`rank`，門檻 0.6。
- 從網址匯入在 `lib/library/playlist_importer.dart`：`PlaylistImporter`，§5.1。目前僅元資料來源走到第 3 步時的行為以程式碼為準。
- 匯入對話框在 `lib/ui/library/import_dialog.dart`。
- `PlaylistPage.truncated`（#299）：只能出現在最後一頁，表示來源只提供了部分曲目。
- Spotify、QQ 插件已在 fmp-plugins 合併（#23、#24），id 是 `spotify`、`qqmusic`，在 `officialPluginIds` 裡。
- 設定頁「音樂庫」區（PR 21）：
  - `lib/ui/settings/library_controls.dart` 的「首頁排行」是可勾選、可拖曳的清單，`shrinkWrap`、不自己捲動，留給本 PR 接在下面；
  - 拖曳先照新順序畫，寫入失敗就退回並提示。
- schema 目前是 v17。`source_settings` 只有 `browse_as_logged_in`。

## 需求

### 0. 先補文件（獨立的 docs commit，放在程式碼之前）

照 design §17 第 19 條，補 ADR 0019 §決定 5、ADR 0033 §決定 12，以及 design §5.1 第 3 步、§8.3、§8.4、§10.9：

- 能播的插件也能「配對到其他音源」；
- 預設仍是「匯入為平台歌單」；
- 這次匯入的目標音源預設不勾來源插件；
- 插件端沿用 `importPlaylist`；
- `truncated` 照常匹配並提示。

ADR 用「補充（2026-10-21，M4 PR 19）」的寫法，照既有 ADR 的補充格式。也把上層 `implement.md` § 21 的勾選項打勾（PR 21 已合併）。

### 1. schema v18（design §3.1、§3.2）

- **新表**：
  - `match_results`：欄位照 ADR 0033 §決定 1；`artists` 存原字串；`user_selected` bool；索引 `match_results_selected`（`selected_track_key`）。
  - `track_origins`：主鍵（`track_key`, `origin_plugin_id`）＋ `origin_id`，曲目刪除時 CASCADE。
- **`source_settings` 加兩欄**：`match_target` bool?、`match_rank` int?。
- **孤兒查詢**（`TracksRepository._orphanCondition`）加 `match_results.selected_track_key`；`track_origins` 不算參照者。
- 不建外鍵到 `installed_plugins`。
- 快照、`stepByStep`、三種 migration 測試，新索引的升級與全新兩例。

### 2. `ExternalImport`（`lib/library/external_import.dart`，design §8.4）

一次匯入一個實例，生命週期跟著預覽頁。

- **讀完所有頁**，顯示進度「讀取中 n 首」。
  - 任何一頁失敗就停在錯誤畫面與「重試」，不進匹配。
  - 最後一頁 `truncated` 時照常匹配，並記下來讓預覽頁提示「來源只提供了部分曲目」。
- **逐首匹配**：
  - `match_results` 已有（來源插件, 外部 id）的直接用，不搜尋；包含使用者先前的改選與排除。
  - 其他的對每個目標音源同時搜第一頁，關鍵字是「原標題 空白 第一位歌手」。
  - 以 §8.1 評分，合併所有音源的候選取前 5；第一名過門檻就選它。
  - 單首搜尋失敗標「搜尋失敗」、可重搜，不中斷整批。
  - 節流交給網路層的每插件限流。
- **目標音源**：
  - 預設照 §8.3：已啟用、同時有 `search` 與 `resolveStream`、`match_target` 不是 false；依 `match_rank`，沒有的排後面、依插件清單。
  - 配對模式（來源插件自己能播）時，這次預設排除來源插件。
  - 預覽頁可以臨時改目標並重搜全部「未手動改選」的，不寫設定。
- **確認**：一個 transaction 寫入，未匹配與排除的不進歌單。
  - `playlists` 一列 `kind = local`，名稱是遠端標題；
  - 選定的曲目依原順序寫 `tracks`（upsert）與 `playlist_entries`；
  - 每首寫 `match_results`，包括 `selected_track_key`、`score`、`user_selected`；
  - 選定的寫 `track_origins`。
- **配對模式不寫 `playlist_remote`**，建出的歌單不刷新。
- **取消**：離開預覽頁先確認，進行中的搜尋結果丟掉、什麼都不寫。候選只在記憶體。

### 3. 匯入對話框（design §10.8、§17 第 19 條）

- **僅元資料來源**：關閉對話框，開匯入預覽頁（在音樂庫的巢狀 `Navigator` 裡）。
- **能播的插件的歌單**：對話框多一個選擇，預設仍是「匯入為平台歌單」（現有行為），另一個是「配對到其他音源」，選了就走預覽頁。
  - 不針對任何插件 id。
  - `mixSeed` 的網址不出現這個選擇。
- 開始前顯示首數與「每首會在 n 個音源搜尋」（可以放在預覽頁開頭）。

### 4. 匯入預覽頁（design §10.9）

- **標頭**：遠端標題、首數、進度「已匹配 n／總數」、取消，以及目標音源的 chip。`truncated` 時多一行「來源只提供了部分曲目」。
- **每首一列**：原標題、歌手、時長｜選定的候選（標題、上傳者、音源、時長、分數），或「匹配失敗」「搜尋失敗」「已排除」。
- **展開一首**：看前 5 名、換選、「重搜」（自訂關鍵字）、「排除」。
- **底部**「建立歌單」：匹配完才可按，未匹配的數目寫在旁邊。建立後開新歌單的詳情。
- 版面沒有定稿：照 ADR 0024 與既有元件決定，回報時列出版面選擇。
- 大歌單（一千首）要能捲動、不卡。

### 5. 設定「音樂庫」區的「匹配目標音源」（design §8.3、§10.10）

- 接在「首頁排行」下面，做成同樣可勾選、可拖曳的清單：
  - 列出所有已啟用、同時有 `search` 與 `resolveStream` 的插件；
  - 拖曳後整批寫 `match_rank`，取消勾選寫 `match_target = false`；
  - 拖曳與寫入失敗的處理照「首頁排行」。
- 沒有可用的插件時顯示說明。
- 移除插件時，`source_settings` 那一列照既有行為刪除，確認新欄位一起刪掉。

### 6. `fmp-test-meta`（dev asset，design 與上層 implement 的重播用）

- 只有 `playlistFromUrl` 與 `importPlaylist`、沒有 `resolveStream` 的測試插件，跟 `fmp-test` 一樣只在 dev flavor 用、不連網。
- 至少有這幾張歌單：
  - `meta-basic`：多頁；有幾首能匹配到 `fmp-test` 的搜尋結果、有幾首匹配不到；
  - 一張最後一頁 `truncated`；
  - 一張某頁失敗。
- 在它旁邊的 `README.md` 寫用法（同 `fmp-test`），並更新 `verify-on-device` 的 `references/runtime-state.md` 的測試插件表。

### 7. 字串三語言（slang）

## 設計空間

版面（預覽頁的列、展開方式、chip 的位置、對話框的選擇用 radio 或 segmented）由實作者決定並回報。行為或範圍上 design 沒涵蓋的決定停下回報，不自行拍板，例如：要不要新增設定、改變刷新或既有匯入的行為、新增插件能力。

## 驗收

- 測試（上層 `implement.md` § 19 逐條）：
  - **`ExternalImport`**：
    - 沿用 `match_results` 不搜尋；
    - 合併前 5、門檻；
    - 搜尋失敗不中斷；
    - 讀取任一頁失敗不進匹配；
    - 取消後不寫；
    - 確認的 transaction 寫入三張表，未匹配不進歌單；
    - 能播插件的配對模式不寫 `playlist_remote`，且目標預設不含來源插件；
    - 最後一頁 `truncated` 時照常匹配並顯示提示；
    - 臨時改目標不寫設定。
  - migration 三種、新索引兩例；孤兒查詢加 `match_results` 參照的案例（`only unreferenced tracks are orphans`）。
  - 設定：拖曳寫 `match_rank`、取消勾選寫 `match_target`、寫入失敗退回。
  - 匯入對話框：僅元資料來源開預覽頁；能播的插件預設是平台歌單，選配對走預覽頁。
  - 預覽頁的 widget 測試：改選、重搜、排除、建立、取消確認、`truncated` 提示。
  - guideline 測試：預覽頁（匹配中、完成、有未匹配與失敗、`truncated`）、對話框的新選項、設定的匹配目標。
  - 一千首歌單的匹配以假插件量一次耗時，寫進回報（之後放 PR 描述）。
- `dart format --output=none --set-exit-if-changed lib test integration_test tool`、`build_runner` 後沒有實質變動、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過（Windows 上兩個 `trackDetail` CRLF 失敗是既有的）。動到 lint 時跑 `lint_sentinel`。
- 文件：`app/AGENTS.md`（匯入、匹配、設定音樂庫的段落與閘門清單），以及需要的 `.trellis/spec/app/{data,matching,ui}/index.md`。
- 實機（主對話做）：
  - 重播（Android）：`fmp-test-meta` 的 `meta-basic` → 預覽 → 改選一首、重搜一首、排除一首 → 建立 → 再匯入一次（全部沿用、沒有搜尋）。
  - 真實（匿名，Android）：Spotify 與 QQ 各一張公開歌單（PR 17、18 的那張）走完一次，記首數、匹配成功數、耗時。

## 不做

- 外部歌單的刷新（Spotify、QQ 只匯入，§17 第 19 條）。
- 舊版資料的 `track_origins` 遷移（M5）。
- 從帳號頁匯入的配對模式（只有網址匯入的對話框有）。
