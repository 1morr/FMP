# M4 設計

各項行為以 ADR 0008–0031 為準；M4 新增的跨模組決定在 ADR 0032（宿主 API）、0033（音樂庫、首頁與導覽）、0034（備份與還原），三份都是「提議中」，與本設計一起核准。這份只寫：

- 跨 PR 的結構（模組邊界、資料表、插件契約的落地）；
- ADR 留給「開工時決定」的技術選擇；
- 擁有者決定（`prd.md`「擁有者的決定」，下稱「決定 n」）的落地方式；
- `research/m4-scope-digest.md` §8 的矛盾（下稱「矛盾 n」，第 11 條在 `research/m4-decisions.md` §1 補上）與 §9 的 42 條未定之處（下稱「#n」）的決定。理由在 `research/m4-decisions.md`（下稱「decisions」），這裡只寫結論與落地，必要時補理由。

套件版本在 2026-10-15 以 pub.dev API（`/api/packages/<名稱>`）查證，只取 stable（§15）。沒有打任何音源的真實 API；要實測的寫進 `implement.md` 的各 PR。

## 0. 未定之處對照

### 0.1 矛盾

| 矛盾 | 題目 | 處理 | 落在 |
|---|---|---|---|
| 1 | 備份的四種說法 | 決定 3：資料庫副本、取代並重啟、保留登入 | ADR 0034；§11 |
| 2 | 頁面對照表的七項不在 § M4 範圍 | 決定 1：全部留在 M4，`milestones.md` 補齊 | `prd.md` 範圍；§16 |
| 3 | Spotify、QQ 插件沒寫在範圍 | 決定 1：M4b，id `spotify`、`qqmusic` | §4.8 |
| 4 | `playlist_remote` 沒有刷新間隔 | 加 `refresh_interval_hours`；不保留 `notifyOnUpdate` | §3.1；§17 第 5 條 |
| 5 | `opencc` 建不起來 | OpenCC 字表產生的純 Dart 對照 | §8.2；§17 第 1 條 |
| 6 | Mix 歌單存的欄位開不了新的 Mix | 存插件 id＋種子曲目 | §5.4；§17 第 2 條 |
| 7 | 歌單名稱唯一性 | 不唯一；重新匯入靠遠端 id；不自動改名 | §5.1；§17 第 6 條 |
| 8 | 驗收項太少 | 每半各一條 ADR 測試對照表 | `prd.md` 驗收；`implement.md` |
| 9 | 「前 5 名」的意思 | 所有目標音源合併評分後的前 5 | §8.4；§17 第 7 條 |
| 10 | 導覽 6 項 | 決定 2 | ADR 0033；§10.1 |
| 11 | `required` 與 `userPreference` 重疊 | 一律 `userPreference`，被拒時插件以 `required` 重送 | ADR 0032；§4.3；§17 第 4 條 |

### 0.2 未定之處

甲＝文件已有答案；乙＝技術決定（decisions 的建議）；丙＝擁有者決定（決定 1–4）。

| # | 題目 | 類 | 落在 |
|---|---|---|---|
| 1 | 範圍與驗收 | 丙 1＋乙 | `prd.md` 驗收；`implement.md` 兩半的驗收 |
| 2 | Spotify、QQ 插件 | 丙 1＋乙 | §4.8 |
| 3 | 備份內容與加密 | 丙 3 | ADR 0034；§11 |
| 4 | `importPlaylist` | 乙 | ADR 0032 §決定 1–2；§4.3 |
| 5 | `libraryRead` | 乙 | ADR 0032 §決定 3；§4.4 |
| 6 | `libraryWrite` | 乙 | ADR 0032 §決定 4；§4.5 |
| 7 | `charts` | 乙 | ADR 0032 §決定 5；§4.6 |
| 8 | 檢查案例與副作用 | 乙＋丙 4 | ADR 0032 §決定 7；§4.7、§12 |
| 9 | 宿主與 `fmp-plugins` 同一輪改 | 甲 | §4.1；`implement.md` 通用規則 |
| 10 | 帶憑證錄製的閘門 | 乙 | §12 |
| 11 | 五張表的欄位 | 乙 | ADR 0033 §決定 1；§3.1 |
| 12 | 「已失效」放哪 | 乙 | §3.1、§5.2；§17 第 11 條 |
| 13 | 刷新的交易與中斷 | 乙 | ADR 0033 §決定 2；§5.2 |
| 14 | 重新匯入的辨識 | 甲 | §5.1 |
| 15 | 孤兒與外鍵 | 甲 | §3.1 |
| 16 | Mix 歌單 | 乙 | §5.4 |
| 17 | 來源失效的呈現 | 乙 | §5.3、§10.4 |
| 18 | 排程工作切分 | 乙 | §6 |
| 19 | 設定歸屬 | 乙 | §3.3；§17 第 9 條 |
| 20 | `notifyOnUpdate` | 乙 | §3.4；§17 第 5 條 |
| 21 | 背景失敗的呈現 | 甲 | §5.3、§13 |
| 22 | 繁簡統一 | 乙 | §8.2；§17 第 1 條 |
| 23 | 評分細節 | 乙 | §8.1 |
| 24 | 目標音源 | 乙 | §8.3；§17 第 8 條 |
| 25 | 逐首搜尋的執行 | 乙 | §8.4 |
| 26 | 導覽 | 丙 2 | ADR 0033 §決定 5；§10.1 |
| 27 | 首頁內容 | 丙 2 | §10.2 |
| 28 | 探索頁 | 丙 2 | §9.3 |
| 29 | 首頁排行設定 | 丙 2 | §10.10 |
| 30 | 音樂庫與詳情 | 乙 | §10.3–§10.5 |
| 31 | 匯入入口 | 乙 | §10.8 |
| 32 | 曲目選單 | 乙 | §10.6 |
| 33 | 從帳號匯入電台 | 乙 | §7.4；§17 第 13 條 |
| 34 | 帳號頁的歌單 | 乙 | §7.3 |
| 35 | 備份內容 | 丙 3 | §11 |
| 36 | 備份格式 | 乙 | §11 |
| 37 | 還原路徑 | 乙 | §11 |
| 38 | 備份入口 | 丙 3 | §10.10、§11 |
| 39 | 目錄與分層 | 乙 | §2 |
| 40 | M5 預留 | 乙 | §3.4 |
| 41 | 重播用的測試插件 | 乙 | §4.9 |
| 42 | i18n 與 a11y | 甲 | §10 開頭 |

decisions 的 digest §2 第 11、13、14 條已被 `archive/2026-10/10-15-account-redaction` 的擁有者決定取代（只遮自己的 id、以帳號的 `userId` 登記為已知值）：網易 uid 不論放 query 或路徑都會被遮，別人的 `mid` 照留；剩下的是 #10（§12）。

## 1. 範圍

### 1.1 範圍對照

| 範圍（決定 1） | 節 | PR（`implement.md`） | 半 |
|---|---|---|---|
| 歌單表、孤兒清理 | §3.1 | 1 | M4a |
| 導覽重排、首頁（最近播放）、音樂庫、本機歌單建立／編輯／刪除／排序 | §10.1–§10.3、§10.5 | 2 | M4a |
| 歌單詳情、曲目選單「加入歌單…」 | §10.4、§10.6 | 3 | M4a |
| 首頁的我的歌單、電台區塊 | §10.2 | 4 | M4a |
| 多選（詳情、搜尋、歷史） | §10.7 | 5 | M4a |
| `importPlaylist` 契約、`TrackSummary` 分 P 兩欄、`fmp-test` | §4.2、§4.3、§4.9 | 6 | M4a |
| YouTube `importPlaylist`（含 Mix 網址） | §4.3 | 7 | M4a |
| 匯入與刷新引擎、`playlist_remote` | §5.1–§5.3 | 8a | M4a |
| 匯入對話框、手動刷新、狀態列 | §10.4、§10.8 | 8b | M4a |
| B 站、網易 `importPlaylist` | §4.3 | 9 | M4a |
| `playlist-refresh` 工作、每張歌單的間隔 | §6.1 | 10 | M4a |
| Mix 歌單 | §5.4 | 11 | M4a |
| 帶憑證錄製、`mutates` | §4.7、§12 | 12 | M4a |
| `libraryRead`、帳號頁「歌單」 | §4.4、§7.3 | 13 | M4a |
| `libraryWrite`、加入／移除遠端、在遠端新增 | §4.5、§7.1、§7.2 | 14 | M4a |
| `libraryLiveRooms`、從帳號匯入電台 | §4.4、§7.4 | 15 | M4a |
| 匹配核心、繁簡字表 | §8.1、§8.2 | 16 | M4b |
| Spotify、QQ 插件 | §4.8 | 17、18 | M4b |
| 匯入預覽、`match_results`、`track_origins`、匹配目標設定 | §8.3、§8.4、§10.9 | 19 | M4b |
| `charts` 契約、排行快取、`charts:<pluginId>`、排行間隔、`chart_settings` | §4.6、§6.2、§9.1 | 20 | M4b |
| 首頁排行、探索頁、設定頁「音樂庫」區、探索的多選 | §9.2、§9.3、§10.10 | 21 | M4b |
| 備份與還原、設定頁「備份與還原」區 | §11 | 22 | M4b |

### 1.2 M4 不做的事

| 項目 | 理由與去處 |
|---|---|
| 舊資料與舊備份檔匯入 | M5（ADR 0010 §決定 4）；§3.4 是對照表 |
| 下載、歌單詳情的下載按鈕、孤兒查詢加 `downloads` | M6 |
| 歌詞端如何用評分核心、歌詞匹配結果 | M7 |
| 來源失效時「另存為本地歌單」、曲目收藏、網易「疑似換版本」 | 功能凍結待辦（ADR 0019） |
| 「加入遠端歌單」預先勾出已含該曲目的歌單 | 之後加選填匯出（§17 第 10 條） |
| 自動定期備份、備份加密 | 舊版沒有；決定 3 沒有要 |
| 佇列與歷史依影片分組 | 只在歌單詳情做（M3 `implement.md`「PR 20 留下的」） |
| 開始 Mix 前的「佇列非空先確認」 | ADR 0031 的待辦 |
| Linux、macOS、iOS 的實作 | 平台任務（Mac 到貨後）；本設計沒有原生依賴（§15） |

### 1.3 實機驗證方式

閘門寫在各節；實機照 ADR 0027（2026-10-13 修訂：Android 每個使用者看得到的 PR，Windows 只在改到平台各自實作時與里程碑驗收）與 `verify-on-device` skill，回報寫平台與模式。真實帳號照決定 4 與 `implement.md` 的通用規則。

| 節 | 模式 | 怎麼驗 |
|---|---|---|
| §10 本機歌單、導覽、首頁、多選 | 重播（`fmp-test`） | 建歌單、加曲目、排序、全部加入、隨機加入、多選；導覽在 compact（Android）與 large（Windows）各看一次 |
| §5 匯入與刷新 | 重播為主；每個插件的公開歌單真實匿名一次 | `fmp-test` 的 §4.9 歌單走完新增、移除、重複、部分完成、來源失效、需要登入；真實：三平台各匯入一張公開歌單、手動刷新一次 |
| §6 排程 | 重播 | 改 dev 資料庫讓一張歌單到期，重啟後 log 有那張的刷新；切到背景時不跑 |
| §7 帳號資料與遠端寫入 | 真實（決定 4：擁有者登入、只動「FMP 測試」歌單）＋重播 | 三平台列歌單、匯入私人「FMP 測試」一次；對它加入、移除一首各一次；「在遠端新增歌單」只以重播驗；B 站從帳號匯入電台一次 |
| §8 匹配 | 重播（`fmp-test-meta`）＋真實匿名 | 預覽頁改選、重搜、排除；Spotify、QQ 各匯入一張公開歌單一次 |
| §9 排行 | 重播＋真實匿名 | 三平台各抓一次榜單；停用一個榜單後首頁不顯示、快取刪掉 |
| §11 備份 | 重播資料 | 兩平台各匯出一次、交換還原，登入保留 |

## 2. 模組與 lint

### 2.1 新增的模組與目錄

```
lib/
  core/matching/                  # 評分核心（純函式，不依賴 data、plugins）、繁簡字表（產生檔）
  domain/playlist.dart            # PlaylistKind、PlaylistRemoteStatus、RefreshResult 等列舉與值型別
  data/repositories/
    playlist_repository.dart      # playlists、playlist_remote、playlist_entries
    match_repository.dart         # match_results、track_origins
    chart_settings_repository.dart
  data/database/database_backups.dart   # 既有；加匯出與還原暫存（§11）
  library/                        # 歌單 service、匯入、刷新器、playlist-refresh 工作、遠端操作、外部匯入的匹配流程
  charts/                         # 排行快取的讀寫、charts:<pluginId> 工作
  app/backup.dart                 # 備份與還原的流程（與 data_reset.dart 同處）
  ui/
    home/                         # 首頁、探索頁
    library/                      # 音樂庫、歌單詳情、建立／編輯、匯入對話框、匯入預覽、加入歌單對話框
    accounts/                     # 既有；加「歌單」頁與「從帳號匯入電台」
    tracks/                       # 既有；加多選（track_selection）與兩個選單項目
    settings/                     # 既有；加「音樂庫」「備份與還原」兩區
test/fixtures/plugins/
  test_plugin/                    # 既有 fmp-test；加 importPlaylist、libraryRead、libraryWrite、charts（§4.9）
  meta_test_plugin/               # 新：fmp-test-meta，只有 importPlaylist（§4.9）
app/tool/opencc/                  # TSCharacters.txt（釘 commit）、LICENSE、產生器（§8.2）
```

- **`lib/library/`、`lib/charts/` 是新的頂層目錄**，照 `lib/radio/` 的理由：要用資料、插件、排程器，不屬於任何既有層；放 `ui/` 會讓背景工作依賴介面，放 `scheduler/` 會讓排程器認得它們。
- **評分核心放 `lib/core/matching/`**：M7 歌詞直接用，不能在 `library/` 裡。它的輸入輸出是自己的值型別（標題、歌手、時長），`library/` 負責從 `TrackSummary` 轉過來（`core/` 不准 import `plugins/`）。
- **備份流程放 `lib/app/`**：要讀插件清單、帳號列、關資料庫、重啟，只有組裝層能全部 import；`VACUUM INTO` 與換檔留在 `lib/data/`（M3 PR 14b 的分法）。

### 2.2 lint 的改動

| 規則 | 改動 | PR |
|---|---|---|
| `fmp_layer_imports` 的 `forbiddenLayerImports` | `core/`、`domain/`、`data/`、`scheduler/` 不 import `library/`、`charts/`；`library/`、`charts/` 不 import `ui/`；`charts/` 不 import `library/` | `library/` 那半條 8a、`charts/` 那半條 20（規則跟著第一個檔案進來） |
| `fmp_layer_imports` 的 `externalPackageOwners` | `unorm_dart`、`string_similarity` → `lib/core/matching/` | 16 |
| `fmp_source_id_literal` 的 `officialPluginIds` | 加 `spotify`（PR 17）、`qqmusic`（PR 18） | 17、18 |

- 每條都照 `.trellis/spec/app/lints/index.md` 寫雙向變異案例（`packages/fmp_lints/test/rules/layer_imports_test.dart`），`tool/lint_sentinel.dart` 加違規行，同步 `app/AGENTS.md` § Lint 的表。

## 3. 資料

### 3.1 主資料庫的新表與欄位

ADR 0033 §決定 1 是欄位清單；這裡補型別、索引與理由。

| 表 | 欄位 | 說明 | PR |
|---|---|---|---|
| `playlists` | `id` int 自增、`kind` text、`name` text、`description` text?、`artwork_json` text?（同 `tracks.artwork_json`）、`sort_order` int、`created_at` int、`updated_at` int、`mix_plugin_id` text?、`mix_seed_source_id` text?、`mix_seed_cid` int? | CHECK：`kind = 'mix'` 時兩個 Mix 欄位非空，否則三個都空（`player_state` Mix 欄位的做法）。整張表在 PR 1 一次建好（M3 `developer_settings` 的先例：欄位清單已定案，只做一次 migration） | 1 |
| `playlist_entries` | `id` int 自增、`playlist_id` int（連帶刪除）、`position` int、`track_key` text（`RESTRICT`）、`remote_item_id` text?、`unavailable` bool（預設假）、`seen_generation` int（預設 0） | 索引 `playlist_entries_playlist`（`playlist_id`, `position`）與 `playlist_entries_track_key`（孤兒查詢的 `RESTRICT` 檢查，同 `queue_entries` 的理由）。後三欄只有匯入歌單用，一樣在 PR 1 建 | 1 |
| `playlist_remote` | ADR 0033 §決定 1 的欄位；`writable`、三個 `*_overridden` bool 預設假；`refresh_generation` int 預設 0；唯一（`plugin_id`, `remote_id`） | `last_result` 空＝還沒刷新完過；`last_refreshed_at` 只在 `complete` 或 `partial` 時寫（§6.1 用它算到期） | 8a |
| `match_results` | ADR 0033 §決定 1；`artists` 存原字串（插件給的 `uploader`），`user_selected` bool | 索引 `match_results_selected`（`selected_track_key`）：孤兒查詢 | 19 |
| `track_origins` | 主鍵（`track_key`, `origin_plugin_id`）、`origin_id` | 一首曲目可以同時是 Spotify 某首與 QQ 某首的匹配結果 | 19 |
| `source_settings`（既有） | 加 `match_target` bool?、`match_rank` int? | §8.3 | 19 |
| `network_settings`（既有） | 加 `chart_refresh_interval_minutes` int? | 空＝60，`0`＝關閉，選項 0／30／60／120／240（ADR 0017 §決定 6） | 20 |
| `chart_settings` | 主鍵（`plugin_id`, `chart_id`）、`enabled` bool?、`sort_order` int? | 排行工作要讀它決定抓哪些（B12），所以跟工作同一個 PR 建；設定頁在 PR 21 | 20 |

- **孤兒查詢**（`TracksRepository._orphanCondition`）：PR 1 加 `playlist_entries`、PR 19 加 `match_results.selected_track_key`；各自在 `queue_repository_test.dart` 的 `only unreferenced tracks are orphans` 加一個被它參照的案例。`track_origins` 是 CASCADE、不算參照者：曲目被清掉時它的來源紀錄一起走（`match_results` 的列還在，下次匯入同一首時依然沿用，選定的曲目因 `RESTRICT` 不會被清）。
- **刪歌單**：`playlist_entries`、`playlist_remote` 連帶刪除；曲目留到下次啟動維護（ADR 0019 §決定 1）。
- **不建外鍵到 `installed_plugins`**：`playlist_remote.plugin_id`、`playlists.mix_plugin_id`、`chart_settings.plugin_id`、`match_results.origin_plugin_id` 都只是字串；插件移除後歌單保留，曲目照「音源未安裝」標示（ADR 0030 §決定 10）。移除插件時 `chart_settings` 的列由 `PluginInstaller.remove` 刪（同 `source_settings`），歌單不刪。
- **`position`**：不設唯一，讀取依（`position`, `id`）。改順序（本機拖曳、刷新套用）一次整批重寫該歌單的 `position`，不需要 `queue_entries` 的負值技巧。
- **寫曲目一律 `TracksRepository.upsert`**。注意 M3 留下的「最後寫入為準」：帶 cid 而沒帶 `partIndex`／`parentTitle` 的 upsert 會清掉那一 P 的兩欄；ADR 0032 §決定 1 要插件一定要給，宿主不另外保護（保護就得讀舊值合併，`upsert` 的語意會變）。

### 3.2 schema 版本與測試

- 依合併順序遞增：v15（PR 1）→ v16（PR 8a）→ v17／v18（PR 19、20，先合併的拿 v17）。實際號碼以合併順序為準；同時開兩個動 schema 的分支時，後合併的重排。
- 每次都照 `.trellis/spec/app/data/index.md` § 改 schema：快照、`stepByStep`、三種 migration 測試（空資料升級、資料完整性、不改使用者設定過的值）。
- 新索引照 `migration_test.dart` 的 `indexes queue_entries.track_key` 寫升級來的與全新建的兩例。
- `source_settings`、`network_settings` 加欄位後，既有列的值不變、新欄位是空（ADR 0010 §決定 3）。

### 3.3 設定的歸屬（§17 第 9 條）

| 設定 | 放哪 | 預設 | 設定頁 |
|---|---|---|---|
| 排行刷新間隔 | `network_settings.chart_refresh_interval_minutes`（「網路」組，與電台間隔同表示法） | 60 分 | 「網路」區，電台間隔之後 |
| 匯入歌單的刷新間隔 | `playlist_remote.refresh_interval_hours`（每張歌單的資料，不是設定組） | 新匯入 24 小時（常數） | 歌單的編輯對話框 |
| 匹配目標音源 | `source_settings.match_target`、`match_rank`（每音源設定表，ADR 0011 §決定 7） | 已啟用、同時有 `search` 與 `resolveStream` 的插件都勾；順序依插件清單 | 「音樂庫」區 |
| 首頁排行的榜單 | `chart_settings` | 全部啟用；順序依插件清單、再依插件的 `chartList` | 「音樂庫」區 |

- 「音樂庫與同步」組在 M4 沒有欄位、不建空表（M3 design §16 第 5 條的理由）。
- 都在資料庫裡，所以都跟著備份走（ADR 0034 §決定 2）。
- `network_settings` 的 Notifier 照電台間隔的寫法加 `chartRefreshInterval`（對外 `Duration?`，`null`＝關閉）與 setter（選項以外的值丟 `ArgumentError`）。

### 3.4 M5 匯入的對照

M4 不寫轉換程式；建表時確認舊資料放得進去（decisions #40）。

| 舊（`lib/data/models/`、`docs/audit/data.md`） | 新 |
|---|---|
| `Playlist.name`、`description`、`createdAt`、`updatedAt`、`sortOrder` | `playlists` 同名欄位（名稱不唯一，舊的唯一性不帶過來） |
| `Playlist.coverUrl` | `playlists.artwork_json`（`[{url}]`） |
| `Playlist.sourceUrl` 非空、`importSourceType` | `kind = imported`；`playlist_remote.plugin_id`＝音源 id；`remote_id` 由 `legacy_import` 從舊網址換算（M5 定，`lib/legacy_import/` 准用官方 id） |
| `Playlist.hasCustomCover` | `playlist_remote.artwork_overridden`（名稱、描述的旗標為假：舊版不分） |
| `Playlist.refreshIntervalHours`、`lastRefreshed` | `refresh_interval_hours`（舊值原樣，ADR 0017 §決定 6）、`last_refreshed_at` |
| `Playlist.ownerName` | `owner_name`；`ownerUserId` 不存（M5 可拿它與舊帳號的 userId 比，給 `writable` 初值） |
| `Playlist.notifyOnUpdate`、`useAuthForRefresh` | 丟掉（前者沒有讀者、後者 ADR 0019 否決） |
| `Playlist.isMix`、`mixSeedVideoId` | `kind = mix`、`mix_plugin_id = youtube`、`mix_seed_source_id`；`mixPlaylistId` 丟掉（§5.4） |
| `Playlist.trackIds`（有序） | `playlist_entries`，依陣列順序寫 `position` |
| `Track.isAvailable` 為假 | 含該曲目的匯入歌單項目 `unavailable = true`（§17 第 11 條） |
| `Track.originalSongId`、`originalSource` | `track_origins`（`origin_plugin_id` 與舊字串相同：`spotify`、`qqmusic`）；是否同時寫 `match_results` 由 M5 定 |
| `Track.viewCount`、`isVip`、`bilibiliAid`、`unavailableReason` | 不匯入（沒有讀者） |
| `Settings.rankingRefreshIntervalMinutes` | `network_settings.chart_refresh_interval_minutes`（原樣） |
| `Settings.homeRankingSourcePriority`、`disabledHomeRankingSources` | `chart_settings`：該音源每個榜單的 `sort_order`、`enabled = false` |
| 舊備份的 `trackKeys` | `TrackKey` 字面輸出不變，直接對到 `tracks.track_key` |

## 4. 宿主 API v1 的擴充（ADR 0032）

### 4.1 原則

- 都在 v1 內，`hostApiVersion` 維持 1（ADR 0028 §決定 1）。同步點照 ADR 0028 §決定 9；`SourcePlugin` 的方法只在引入它的 PR 加。
- **順序**：FMP 先合併宿主契約與 `fmp-test`，`fmp-plugins` 再實作並開 PR 改 `FMP_REF`；`.js` 有改動時 manifest 版本提高、index 重產（ADR 0030 §決定 3）。
- 每個能力的 `fmp-test` 假實作與契約同一個 PR，讓 UI 能以重播驗（§4.9）。
- `checks.dart` 的 `trackFields` 跟著 `TrackSummary` 的新欄位加（`.trellis/spec/app/plugins/index.md` 的 Quality Check）。

### 4.2 `TrackSummary` 的分 P 兩欄（PR 6）

- `partIndex?`（正整數）、`parentTitle?`（不空）；兩個要嘛都有、要嘛都沒有（單一個是 `ParseError`）。
- 宿主把它們寫進 `TrackInfo.partIndex`、`parentTitle`（M3 PR 20 已有），顯示照 `TrackInfo.displayTitle`。
- 搜尋結果也可以帶（B 站的搜尋不會），宿主不分來源一律照收。

### 4.3 `importPlaylist`（PR 6；插件 7、9、17、18）

形狀見 ADR 0032 §決定 2。落地：

- `ImportPlaylistExports`（`playlistFromUrl`、`importPlaylist`）進 `requiredExports`。回傳值驗證：`items` 可以是空陣列（空歌單）；`cursor` 空字串拒收（同 `mix`）；`total` 非負；`mixSeed` 只在插件宣告 `mix` 時收。
- **依序問**：`PlaylistImporter` 照 `pluginRegistryProvider` 的順序問已啟用、宣告 `importPlaylist` 的插件；插件拋錯就停、不再問下一個（電台 `addFromUrl` 的規則）。都回 `null` 時提示「無法辨識這個網址」。
- **認證**：請求的 `auth` 由插件標（宿主沒有「這是歌單」的資訊，同 `live`）。私人歌單的重送在插件內（ADR 0032 §決定 2）；各插件 repo 以 Node 測試守「無權限＋`credentialsAttached` 為假＋已登入 → 重送一次 `required`；已帶憑證被拒 → 不重送」。
- **各插件**（舊 Dart 程式碼是規格，decisions §6 的實測放在各 PR 開頭）：
  - YouTube：一般清單以 innertube `browse` 續取；Mix 網址（`list=RD…`）與 `mix:<videoId>` 簡寫回 `mixSeed`（舊 `youtube_mix_shorthand.dart`，種子至多 64 字）；`remoteItemId` 是 `setVideoId`；`total` 不給（標頭筆數含隱藏影片）。
  - B 站：收藏夾；多 P 影片照舊版在匯入時展開成各 P（舊 `import_service.dart` 的 `_expandMultiPageVideos`），每個分 P 帶 `cid`、`partIndex`、`parentTitle`；`total` 給收藏夾的媒體數只在不展開時相等，所以**展開後不給 `total`**。
  - 網易：歌單詳情只給前幾首完整資料、其餘以 id 分批補（舊版做法 PR 9 讀原始碼確認）；`163cn.tv` 短網址由 `playlistFromUrl` 發請求展開。
- 慣例：MusicFree `importMusicSheet`／`getMusicSheetInfo`。

### 4.4 `libraryRead`（PR 13、15）

- `LibraryReadExports`（`libraryPlaylists`；選填 `libraryLiveRooms`）。`knownExports` 收兩個，沒宣告 `live` 而匯出 `libraryLiveRooms` 拒載。
- `libraryPlaylists` 分頁同 `importPlaylist`；宿主讀完所有頁才顯示（帳號歌單通常不多；超過 20 頁停下、顯示已讀的並記 warning）。
- 網易用哪個端點交給插件 PR：自己的 uid 已登記為已知值，query 或路徑都會被遮。

### 4.5 `libraryWrite`（PR 14）

- `LibraryWriteExports`（三個），manifest 驗證：宣告 `libraryWrite` 沒宣告 `libraryRead` 是 `Unsupported`。
- `results` 長度與輸入不同是 `ParseError`；`error` 以結構化錯誤的轉換轉成 `AppError`（`plugin_runtime` 的同一個函式）。
- 網易寫入的 `X-Real-IP`：沿用 M3 design §16 第 14 條已核准的做法——先以真實連線測「不帶」，不行才只在必要的請求送，寫進插件 README（PR 14 的實測就是決定 4 的那一次加入與移除）。

### 4.6 `charts`（PR 20）

- `ChartsExports`（`chartList`、`chart`）。`chartList` 回傳的 `chartId` 不重複、`title` 不空；`chart` 的 `tracks` 可以是空的（空榜單顯示「沒有內容」）。
- 宿主每次刷新先呼叫 `chartList`（常數，不發請求），再對啟用的榜單逐一 `chart`。插件新增的榜單預設啟用；插件拿掉的榜單，它的 `chart_settings` 列留著無害（讀時以 `chartList` 為準）。
- YouTube 的榜單照舊版（YouTube Music「New This Week」依觀看數排）、B 站 `ranking/v2` 音樂區、網易官方熱歌榜，都由插件決定。

### 4.7 `checks.json` 的擴充與 `mutates`

- 四個能力的案例見 ADR 0032 §決定 7。`FmpChecks` 加四個鍵；`checkShapes`、`PluginCheck.run`、d.ts 同一個 PR 加（各能力自己的 PR）。
- **`mutates` 欄位**（PR 12 加 `PluginCheck.mutates` 與各處的略過，第一個用它的是 PR 14）：照 `FmpLoginCheck` 的 `requiresLogin: true` 寫法——`FmpLibraryReadCheck` 必填 `requiresLogin: true`，`FmpLibraryWriteCheck` 必填 `requiresLogin: true` 與 `mutates: true`（`checkShapes` 收它，`parseChecks` 不是 `true` 就拒收）。略過的地方與字樣：
  - `HealthCheck`：結果「略過：會改動遠端」，不呼叫插件；
  - `record_test.dart`（命令列錄製與冒煙）：略過並印出理由；
  - `DevCaseRuns`：真實與錄製模式略過並顯示同一句；重播照跑。
  - 契約測試（`contract_test.dart`）照常重播。
- `mutates` 的案例的 fixture 一律手寫，`meta.edited` 寫「mutates：手寫」；插件庫的 `test/login_fixtures_test.dart` 已擋沒標 `meta.edited` 的 `requiresLogin` 案例，`mutates` 的案例都同時 `requiresLogin`，不另加閘門。

### 4.8 Spotify、QQ 插件（PR 17、18）

- 官方 id `spotify`、`qqmusic`，只宣告 `importPlaylist`，請求 `never`（ADR 0012 §決定 7）。各自的 PR 把 id 加進 `officialPluginIds`。
- Spotify：抓 `open.spotify.com/embed/playlist/<id>` 頁面的 `__NEXT_DATA__`（舊 `spotify_playlist_source.dart`）；超過 100 首時是否完整是 PR 17 開頭的實測。抓不到就停下回報：可能牽動決定 1 的範圍。
- QQ：`u6.y.qq.com/cgi-bin/musics.fcg` 加自簽 `sign`（舊 `qq_music_sign.dart`，只要 MD5 與 base64，宿主 `crypto.md5` 已有）、`pageSize = 1000`。
- `TrackSummary` 對外部歌曲的用法：`sourceId`＝外部歌曲 id、`title`、`uploader`＝歌手（多位以 ` / ` 連接）、`durationMs`；沒有 `artwork` 也可以。宿主不把它們寫進 `tracks`（它們不能播），只進匹配流程（§8.4）。
- 首次啟動引導照 ADR 0030 §決定 12 不改：官方插件預設全勾，Spotify、QQ 也裝。

### 4.9 測試插件

`fmp-test` 隨各 PR 加假實作（不連網，狀態存在插件 isolate 的記憶體，到 App 重啟為止），寫進它的 README；`test_plugin_bundle_test.dart` 守關鍵字。

| 能力 | 假實作 | PR |
|---|---|---|
| `importPlaylist` | `playlistFromUrl` 認 `https://fmp.test/playlist/<id>` 與 `https://fmp.test/mix/<sourceId>`（後者回 `mixSeed`）。歌單：`pl-basic`（5 首、每頁 3 首，第 1、4 首是同一首）、`pl-grow`（每刷新一次輪流新增一首、移除一首、倒序）、`pl-partial`（第 2 頁 `NetworkError`）、`pl-gone`（`NotFound`）、`pl-auth`（未登入 `AuthRequired`，登入後回 3 首、`writable: true`）、`pl-unavailable`（第 2 首 `unavailable`）、`pl-parts`（一支 3 P 的影片展開成 3 首，帶 `partIndex`、`parentTitle`） | 6 |
| `libraryRead` | 登入後 `libraryPlaylists` 回 `pl-auth`（可寫）與 `pl-basic`（不可寫）；`libraryLiveRooms` 回五個直播間 | 13、15 |
| `libraryWrite` | `pl-auth` 的內容在記憶體：`addToPlaylist` 第一次 `added`、再加同一首 `alreadyPresent`；`sourceId` 是 `fail` 的那首 `failed`；`removeFromPlaylist` 同理；`createPlaylist` 回 `pl-new-<n>`（空歌單，之後可以匯入） | 14 |
| `charts` | `chartList` 回 `hot`、`new`、`broken`；`hot` 5 首、`new` 3 首、`broken` 以 `NetworkError` 失敗 | 20 |

- **`fmp-test-meta`**（PR 19，新的 dev asset 插件）：只宣告 `importPlaylist`，認 `https://fmp.test/meta/<id>`；`meta-basic` 的歌曲標題、歌手、時長取 `fmp-test` 搜尋結果的三首（重播時匹配得到），外加一首什麼都匹配不到的（時長 999 秒）。只在 dev 打包，`test_plugin_bundle_test.dart` 一起守。

## 5. 匯入與刷新

### 5.1 從網址匯入（PR 8a、8b）

`lib/library/playlist_importer.dart` 的 `PlaylistImporter`：

1. `playlistFromUrl` 依序問（§4.3）→ 得到（插件, `playlistId`）或（插件, `mixSeed`）。
2. `mixSeed` → §5.4。
3. 插件沒有 `resolveStream`（僅元資料來源）→ 交給匯入預覽（§8.4），不建歌單。
4. （插件, `playlistId`）已在 `playlist_remote` → **重新匯入＝刷新那一列**（ADR 0019 §決定 2，M12），開它的詳情；不覆寫名稱、間隔等本地設定。從帳號頁與從網址匯入同一張也是同一列。
5. 否則取第一頁；**第一頁成功才建列**（`playlists` 一列 `kind = imported`、名稱取遠端標題；`playlist_remote` 一列，間隔 24 小時、`writable` 取回應或帳號頁清單的值），第一頁失敗就什麼都不建、提示錯誤。之後的頁交給刷新器（§5.2），代際從 1 開始。
- 名稱不唯一，不自動改名（§17 第 6 條）。
- 帳號頁的匯入（§7.3）從第 4 步開始，`playlistId` 直接來自 `libraryPlaylists`。

### 5.2 刷新器（PR 8a）

`lib/library/playlist_refresher.dart` 的 `PlaylistRefresher.refresh(playlistId, {trigger})`，演算法見 ADR 0033 §決定 2。補充：

- **互斥**：全 App 一個 FIFO 鎖，同時只刷一張。手動、寫入後、排程三種觸發都排進同一個鎖；排程那一輪每張各取一次鎖，所以手動請求最多等目前那一張刷完（等於插隊在下一張之前）。
- **比對**（每頁一個 transaction）：
  - 記憶體裡維護這次刷新的狀態：已見過的 `remote_item_id` 集合、每個曲目鍵已出現的次數、依遠端順序的項目 id 清單。
  - 有 `remote_item_id` 的遠端項目：找同歌單同 `remote_item_id` 的項目；沒有 `remote_item_id` 的：找同曲目鍵、依目前 `position` 排序的第 k 個項目（k＝這個曲目鍵在遠端已出現的次數）。
  - 找到就寫 `seen_generation = g`、`unavailable`、`remote_item_id`；找不到就接在尾端（`position = max + 1`）。
- **完整套用**（一個 transaction）：刪 `seen_generation < g`、依記憶體的清單重寫 `position`（0 起）、`playlists` 的名稱／描述／封面在旗標為假時寫遠端值、`playlist_remote.owner_name`、`writable`（回應給了才寫，ADR 0032 §決定 2）、`last_result = complete`、`last_refreshed_at`、`status = active`、`updated_at`。
- **不完整**：只寫 `last_result = partial`、`last_refreshed_at`、`status = active`。
- **失敗**：`NotFound` → `status = sourceGone`；`AuthRequired` → `authRequired`；其他 → `last_result = failed`（`status` 不動）。都不碰項目。
- **過期**：每頁寫入前與套用前檢查（a）`refresh_generation` 仍是 g（另一次刷新開始了）、（b）觸發者仍有效（排程工作的 `JobContext.isCurrent`；間隔改成不啟用、插件停用或移除時刷新器把進行中的那張標為取消）。過期就停、不寫。
  - 更正（PR 10）：間隔改成不啟用或那一列被刪，是排程工作監看間隔、讓那張的 `isCurrent` 變假；刷新器只自己看插件停用或移除。
- **刷新期間**歌單頁顯示資料庫現況（舊順序加尾端新增），不加暫存表。
- **插件不在清單**（停用、移除）：刷新器直接回「音源已停用／未安裝」，不寫任何東西。
- 慣例：Finamp 的 id 集合差集。

### 5.3 狀態與呈現（PR 8b）

| 狀態 | 條件 | 詳情頁狀態列 | 自動刷新 |
|---|---|---|---|
| 正常 | `status = active`、`last_result = complete` | 「上次刷新：<時間>」 | 照常 |
| 部分完成 | `last_result = partial` | 「上次刷新：部分完成」＋時間 | 照常 |
| 刷新失敗 | `last_result = failed` | 「刷新失敗」＋「重試」 | 照常（下一輪再試） |
| 來源失效 | `status = sourceGone` | 「來源失效：遠端歌單已刪除或無權限」＋「重試」 | 停止 |
| 需要登入 | `status = authRequired` | 「需要登入才能刷新」＋「登入」（開帳號頁該列） | 停止 |
| 音源不可用 | 插件停用或未安裝 | `sourceUnavailableProvider` 的字樣 | 不跑 |

- 自動刷新不跳 toast，只更新狀態（ADR 0013 §決定 5）；手動刷新失敗照 ADR 0013 的呈現表提示，離線時（失敗且狀態不是 `online`）顯示離線字樣。
- 唯讀副本就是原本的歌單，曲目照常能播。
- 項目 `unavailable` 的曲目在列上標「已失效」，點了照常嘗試播放（播放失敗照 ADR 0018 處理）。

### 5.4 Mix 歌單（PR 11，§17 第 2 條）

- 建立：匯入對話框的 `mixSeed` → `mix({seed})` 呼叫一次（驗證並取標題）→ `playlists` 一列 `kind = mix`、名稱＝回傳的標題、`mix_plugin_id`、`mix_seed_source_id`、`mix_seed_cid`。不存曲目。
- 歌單卡與詳情：「Mix 播放」（`startMixFrom` 以種子開始，取代佇列，ADR 0031 §決定 9）、編輯（只有名稱）、刪除；詳情頁不列曲目，顯示種子曲目（以曲目鍵查 `tracks`，沒有就只顯示 id）。
- 插件不在清單或沒宣告 `mix`：「Mix 播放」停用並顯示原因。
- 曲目選單的「開始 Mix」不變（M3）；「存成 Mix 歌單」不做（舊版也沒有）。

## 6. 排程工作（ADR 0017、0033 §決定 4）

### 6.1 `playlist-refresh`（PR 10）

- `lib/library/playlist_refresh_job.dart`，`FmpApp` 常駐（`RadioStatusJobs` 的做法）。登記一次：`SchedulerJob(id: 'playlist-refresh', pluginId: null, interval: 30 分, run:)`。
- 每次執行：讀到期的歌單（ADR 0033 §決定 4 的條件，`last_refreshed_at` 為空也算到期），依 `last_refreshed_at` 由舊到新逐張 `PlaylistRefresher.refresh(trigger: scheduled)`。
- 單張失敗只寫那張的狀態、繼續下一張；到期的全部失敗才丟錯讓排程器退避。沒有到期的就是成功。
- 失敗的那張不寫 `last_refreshed_at`，下一輪（30 分鐘後）再試；`sourceGone`、`authRequired` 不再選它。
- 間隔改成不啟用、插件停用或移除：下一輪自然不選；進行中的那張被取消（間隔由排程工作監看、插件由刷新器看，§5.2 的更正）。
- 這個工作沒有 `pluginId`，插件停用不會整批移除它；「同一插件依序」對它不適用（它本身就是依序）。

### 6.2 `charts:<pluginId>`（PR 20）

- `lib/charts/chart_jobs.dart`，照 `RadioStatusJobs`：每個「已啟用、宣告 `charts`、至少一個啟用榜單」的插件一個工作，間隔是排行間隔（關閉＝`interval: null`，只有手動刷新會跑）。
- 每次執行：`chartList` → 啟用的榜單逐一 `chart` → 寫快取（§9.1）。單一榜單失敗只在記憶體標那一個「更新失敗」（`radioQueryFailuresProvider` 的做法），其他繼續；全部失敗才丟錯。
- 只在插件實例、間隔、啟用榜單集合改變時重新登記；榜單在設定頁停用時立即重新登記（全停用就移除工作）並刪那個榜單的快取（ADR 0017 §決定 5、ADR 0016 §決定 4）。
- 手動刷新：首頁排行區塊與探索頁的「刷新」對該插件的工作 `runNow`；離線回 `offline`。

## 7. 遠端操作與帳號資料

### 7.1 加入遠端歌單（PR 14）

- 入口：曲目選單與多選的「加入遠端歌單…」，條件是曲目所屬插件宣告 `libraryWrite`、在清單上、`CredentialStore.state` 是 `active`。多選時所有選取的曲目要屬於同一個這樣的插件，否則這一項停用並說明。
- 對話框：開啟時 `libraryPlaylists`（讀完所有頁）→ 只列 `writable` 的歌單、勾選框；「在遠端新增歌單」輸入名稱 → `createPlaylist` → 新歌單出現在清單並已勾選。按「加入」直接送出（不加確認框，ADR 0019 §決定 4），每個勾選的歌單一次 `addToPlaylist`。
- 結果：提示「已加入 n 個歌單」，有 `alreadyPresent` 附「m 首已存在」，有失敗附「k 項失敗」與「詳細」（列出歌單與錯誤）。
- 之後：對每個成功的目標，若它在 `playlist_remote` 裡（同插件、同 `remote_id`），排一次刷新（`trigger: afterWrite`）。

### 7.2 從遠端歌單移除（PR 14）

- 入口：匯入歌單詳情的曲目選單與多選，條件是 `playlist_remote.writable`、插件宣告 `libraryWrite`、已登入。
- 確認框列出首數 → `removeFromPlaylist`（`sourceId`、`cid`、`remoteItemId`）→ `removed` 與 `notPresent` 的項目從本地刪 → 背景刷新一次 → 有 `failed` 時提示並列出（ADR 0019 §決定 4）。

### 7.3 帳號頁的「歌單」（PR 13）

- 帳號頁已登入、宣告 `libraryRead` 的那一列多一個「歌單」按鈕，開一頁（在設定的內容區內）：`libraryPlaylists` 的清單（封面、名稱、首數、可寫標記），已匯入的（`playlist_remote` 有同插件同 id）標「已匯入」並停用勾選；工具列「匯入所選」。
- 匯入所選：逐張走 §5.1 第 4 步起，進度「n／總數」；失敗的列出、其他照做（ADR 0013 §決定 5）。
- 「在遠端新增歌單」只放在加入遠端的對話框（舊版同）。
- 匯入後的刷新帶不帶憑證依音源設定與插件的重送（§4.3），取代舊版「帳號頁匯入一律帶登入」（M12）。

### 7.4 從帳號匯入電台（PR 15，§17 第 13 條）

- 帳號頁那一列的「⋯」選單「從帳號匯入電台」，條件是插件匯出 `libraryLiveRooms` 且宣告 `live`、已登入。
- `libraryLiveRooms` → 逐一以 `RadioRepository.add` 寫入（重複回 `false`）→ 提示「新增 n 個，m 個已在電台清單」。不再呼叫 `liveStatus`：`LiveRoom` 已有顯示資料。

## 8. 匹配（ADR 0019 §決定 5、6）

### 8.1 評分核心（PR 16）

`lib/core/matching/`，純函式：

- **正規化**：NFKC（`unorm_dart`）→ 小寫 → 繁簡統一（§8.2）→ 去掉裝飾標點與空白（保留 CJK、字母、數字）→ 把括號內容（`()`、`（）`、`[]`、`【】`、`「」`）抽出來另外比。
- **標題分**：主標題（去掉括號後）的 Dice（`string_similarity`）；兩邊括號內容的集合不同時乘 0.9（例如一邊是 `Live`），不整首否決（MusicBrainz 的延伸資訊不整段刪）。
- **歌手分**：以 ` / ` `、` `,` `&` `;` `feat.` `ft.` `×` ` x ` 拆開；每位原歌手與候選的上傳者取 Dice，另外原歌手正規化後出現在候選的標題裡算 1.0；取最佳。B 站、YouTube 的上傳者常是頻道而不是歌手，所以標題裡的歌手名也算。
- **時長**：差距超過 max(10 秒, 原時長的 5%) 直接淘汰；之內以 `1 - 差距／門檻` 線性給分。任一邊缺時長不設門檻、時長分 0.5。
- **總分**＝0.6×標題＋0.3×歌手＋0.1×時長；**第一名到 0.6 才自動選**，否則是「匹配失敗」。
- 權重與門檻以一份手寫的測試語料（約 50 對真實的公開歌名與上傳標題，不連網）校準後寫死；語料與結果在測試檔裡，改權重就要語料全綠。
- 不看播放量等來源特有的訊號（ADR 0019 §決定 6）。
- 介面：`MatchScore score(MatchQuery query, MatchCandidate candidate)`、`List<Ranked<T>> rank<T>(MatchQuery, Iterable<(T, MatchCandidate)>, {int limit})`（同分依呼叫端給的順序，穩定排序）。M7 直接用。

### 8.2 繁簡統一的字表（PR 16，§17 第 1 條）

- 不用 `opencc` 套件：stable 1.1.0 依賴 build hooks 穩定前的實驗 API（`native_assets_cli ^0.8.0`），預編譯庫沒有 Android、iOS（decisions #22 的查證表）。
- 比對只需要「兩邊折成同一個字」，不需要正確的簡體文字：兩邊都經同一張字級對照，`乾隆` 折成 `干隆` 也兩邊一致，不需要詞組轉換與原生庫。`pinyin` 套件把兩岸共用的字保留不轉（實跑 `週杰倫`→`週杰伦`），`周杰伦` 與 `週杰倫` 會失配，不採。
- **做法**：
  - `app/tool/opencc/TSCharacters.txt`：OpenCC `data/dictionary/TSCharacters.txt` 的副本，釘在 PR 16 開工當天 `master` 的 commit，檔頭註明來源網址、commit 與 Apache-2.0；同目錄放 OpenCC 的 `LICENSE`（有 `NOTICE` 時一併放）。
  - `app/tool/opencc/generate_ts_characters.dart`：讀它（每行「繁體字 TAB 候選…」，多個候選取第一個），產生 `lib/core/matching/ts_characters.g.dart`（`const Map<int, int>`，碼位對碼位；產生檔頭寫來源 commit），提交。
  - 測試：重新產生的內容等於已提交的（讀 `tool/` 的副本，不連網）；一組已知字對（`週→周`、`倫→伦`、`乾→干`、`著→着`）；簡體字經過不變。
- **授權標示**：`lib/app/licenses.dart` 在啟動時以 `LicenseRegistry.addLicense` 登記 OpenCC 的 Apache-2.0 全文（文字由產生器一併輸出成常數），M9 的「關於」頁以 `showLicensePage` 顯示。測試斷言登記的條目含 `OpenCC` 與 `Apache License`。
- 要完整 OpenCC（詞組）時改 `flutter_opencc_plus`（0.1.4，Apache-2.0，原生；decisions #22），先在 Android 與 Windows 各建一次。

### 8.3 目標音源（PR 19，§17 第 8 條）

- 預設：已啟用、同時宣告 `search` 與 `resolveStream` 的插件都是目標（含網易；舊版只有 B 站與 YouTube 是因為當時網易不能播）。`match_target = false` 的排除。
- 順序：`match_rank` 由小到大，沒有的排在後面、依插件清單順序。同分依這個順序（ADR 0014 §決定 9）。
- 設定頁「音樂庫」區一個可拖曳、可勾選的清單（舊版首頁排行設定頁的樣式）；拖曳後整批寫 `match_rank`。匯入預覽頁可以臨時改目標並重搜，不寫設定。
- 網易可能匹配到只有試聽的歌：`previewOnly` 由播放處理（M2），評分不看來源特有的訊號。

### 8.4 外部匯入的流程（PR 19）

`lib/library/external_import.dart` 的 `ExternalImport`（一次匯入一個實例，生命週期跟著預覽頁）：

1. 讀完所有頁（進度「讀取中 n 首」）；任何一頁失敗就停在錯誤畫面與「重試」，不進匹配（§17 第 18 條：外部匯入沒有「部分完成」）。
2. 對每首（依序）：
   - `match_results` 有（插件, 外部 id）→ 直接用（含使用者先前的改選與排除），不搜尋；
   - 否則對每個目標音源同時搜尋第一頁（關鍵字＝原標題＋空白＋第一位歌手），以 §8.1 評分、合併所有音源的候選、取前 5 名（§17 第 7 條）；第一名過門檻就選它。
   - 單首搜尋失敗標「搜尋失敗」並可重搜，不中斷整批（ADR 0013 §決定 5）。
   - 節流交給網路層的每插件限流（ADR 0013）；不交給排程器。
3. 預覽頁（§10.9）讓使用者改選、重搜（自訂關鍵字，同一套評分）、排除。
4. 確認：一個 transaction——`playlists` 一列 `kind = local`（名稱＝遠端標題），選定的曲目依原順序寫 `tracks`（upsert）與 `playlist_entries`；每首寫 `match_results`（`selected_track_key`、`score`、`user_selected`；未匹配與排除的 `selected_track_key` 為空）；選定的寫 `track_origins`。未匹配的歌不進歌單，只在預覽頁標示（§17 第 12 條）。
- 離開預覽頁先確認並取消（進行中的搜尋結果丟掉）。App 在背景時只要行程還在就繼續。
- 開始前顯示首數與「每首會在 n 個音源搜尋」；大歌單的耗時見 `implement.md` 的風險。
- 候選清單只在記憶體；結果持久化只靠 `match_results`（ADR 0014 §決定 9）。

## 9. 排行（ADR 0016 §決定 4、0017）

### 9.1 快取（PR 20）

- 快取庫 `cache.db` 加 `CacheCategory.chart`；鍵 `chart:<pluginId>:<chartId>`，內容是 `{fetchedAt, tracks}` 的 JSON 檔，所屬插件記在索引（移除插件時 `CacheStore.removePlugin` 一起刪）。
- 讀：先顯示快取並標「更新於 <時間>」；沒有快取時，在線顯示載入中、不在線顯示離線空狀態（ADR 0016 §決定 7）。被淘汰視為沒有快取。
- 榜單停用或插件停用時刪那些鍵（ADR 0016 §決定 4）。
- `lib/charts/chart_cache.dart` 只經 `CacheStore` 寫；`lib/charts/` 不直接碰 `lib/data/cache/` 的表。

### 9.2 首頁的排行區塊（PR 21）

- 每個啟用的榜單依使用者順序一個子區塊：榜單名稱與音源、前 5 首（點一下臨時播放，選單照 `TrackRowMenu`）、「查看全部」（開探索頁的那個分頁）。
- 全部停用就沒有這個區塊（不保留「至少留一個」，決定 2）。

### 9.3 探索頁（PR 21）

- 首頁「查看全部」開的子頁（在首頁的巢狀 `Navigator` 裡）。每個啟用的榜單一個分頁，完整清單、多選（§10.7）、工具列「刷新」。

## 10. 介面

共同規則：字串三語言（slang，ADR 0024 §決定 7）；新頁面加進 guideline 測試（淺色、深色，400／1000 寬）；離線照 `.trellis/spec/app/ui/index.md` § 離線（本機資料照常顯示）；曲目列照 M3 #234 以 `sourceUnavailableProvider` 取代上傳者顯示「音源已停用／未安裝」；有快捷鍵的按鈕 tooltip 附按鍵。

### 10.1 導覽（PR 2，決定 2）

- `ShellDestination { home, search, library, radio, settings }`；三種導覽元件照它的順序；App 開在首頁。
- **每個目的地一個巢狀 `Navigator`**（放在 `IndexedStack` 裡）：歌單詳情、歷史、探索、帳號頁的歌單頁在內容區內開，導覽與播放列留著。系統返回鍵與 Esc（不在輸入框時）先 pop 目前目的地的 `Navigator`，到根才交給原本的行為。再點一次目前的導覽項回到該目的地的根（Material 的慣例）。
- 焦點三區與快捷鍵不變（Ctrl+F 先切到搜尋目的地再聚焦）；`app_shell_test.dart` 的導覽與快捷鍵群組跟著改。
- ADR 0031 §如何確認的「四個導覽項（三種視窗寬度）」改成五個（§16 的更正）。

### 10.2 首頁（PR 2、4、21）

- 區塊依序：排行（PR 21）、我的歌單（PR 4）、電台（PR 4）、最近播放（PR 2）。
- **最近播放**：`play_history` 最新 20 筆（與歷史頁同一份資料，不去重），點一下臨時播放；「查看全部」開歷史頁。
- **我的歌單**：依 `sort_order` 前 20 張歌單卡；「查看全部」切到音樂庫。
- **電台**：依 `sort_order` 前 20 個電台（封面、標題、狀態標記，`RadioEntry` 的四種狀態），點一下 `playLive`；「查看全部」切到電台。
- 沒有內容的區塊不顯示；全部都沒有時顯示說明（「搜尋並播放歌曲，或匯入歌單」）。
- **首次啟動引導**：沒有任何已啟用、具 `search` 能力的插件時，首頁也顯示 `plugin_onboarding` 的同一個元件（§17 第 16 條）。

### 10.3 音樂庫（PR 2）

- 頂端「歷史」一列（開歷史頁）；下面是歌單卡（ADR 0033 §決定 8），compact 是清單、expanded 以上是格狀。拖曳排序後整批寫 `sort_order`。
- 工具列「新增」（建立對話框）、「匯入」（§10.8，PR 8b 起）。
- 歌單卡選單：Mix 播放（Mix，PR 11）、全部加入佇列、隨機加入（§17 第 14 條：打亂後加入佇列）、編輯、刷新（匯入，PR 8b）、刪除（確認框；匯入歌單寫明「只刪本機的副本」）。
- 空的時候說明怎麼建立或匯入。

### 10.4 歌單詳情（PR 3、8b）

- ADR 0033 §決定 9 的內容。狀態列見 §5.3（PR 8b）。
- 「全部」＝全部加入佇列（D2）；「隨機加入」同上但打亂；超過 10,000 首整批拒絕並提示（`QueueFull`，ADR 0018 §決定 4）。點一首＝臨時播放（與搜尋結果相同）。
- 曲目以 `TrackKey.formatGroup` 分 P 分組：同一支影片的連續分 P 收在一個群組標題（影片標題）下。
- 本機歌單：拖曳重排、選單「從歌單移除」；匯入歌單沒有這兩項（ADR 0019 §決定 4）。

### 10.5 建立與編輯（PR 2、10）

- 欄位：名稱（必填）、描述、封面（預設第一首的封面；「自訂」照舊版以圖片網址，「使用預設」清回）。匯入歌單的編輯另有自動刷新間隔（1／6／12／24／48／72／168 小時或不啟用，PR 10）。
- 匯入歌單改名稱、描述、封面時把對應的 `*_overridden` 設為真；「使用遠端的」清回假，下一次刷新寫回遠端值。

### 10.6 曲目選單（PR 3、14）

- `TrackRowMenu` 加「加入歌單…」（PR 3）：對話框列 `local` 歌單（勾選多張）與「新增歌單」；加入後提示。同一首可以重複加入同一張本機歌單（不設唯一，ADR 0019）。
- 「加入遠端歌單…」（PR 14，§7.1）、「從遠端歌單移除」（PR 14，§7.2）。
- 套用在所有用 `TrackRowMenu` 的地方（搜尋、歷史、佇列、歌單詳情、探索、首頁的曲目區塊）。Mix 模式下佇列的選單照 M3 的禁止規則。

### 10.7 多選（PR 5、21）

- 共用元件在 `lib/ui/tracks/track_selection.dart`：長按或「⋯」選單的「選取」進入；頂端換成選取列（已選 n 首、全選、取消、動作）；Esc 或返回離開。
- 動作：加入佇列、加入歌單、加入遠端歌單（PR 14 起）、從本機歌單移除（只在本機歌單詳情）、從遠端歌單移除（只在可寫的匯入歌單詳情，PR 14 起）。
- 用在歌單詳情、搜尋、歷史（PR 5），探索（PR 21）。佇列不用（佇列有自己的編輯）。
- 鍵盤：Ctrl+A 全選（在選取模式內）；Shift＋點選範圍選取（桌面）。

### 10.8 匯入對話框（PR 8b、11、19）

- 一個文字欄（網址或 `mix:` 簡寫）→「匯入」→ §5.1。
- 可播放音源的歌單：對話框內顯示進度（「已讀 n 首」），完成後關閉並開詳情；失敗顯示錯誤、不建歌單。
- 僅元資料來源：關閉對話框、開匯入預覽頁（§10.9）。
- `mixSeed`：建好 Mix 歌單後開它的詳情（PR 11）。

### 10.9 匯入預覽頁（PR 19）

- 全頁（音樂庫的巢狀 `Navigator` 裡）。標頭：遠端標題、首數、進度「已匹配 n／總數」、取消；目標音源的 chip（臨時改目標並重搜全部未手動改選的）。
- 每首一列：原標題、歌手、時長｜選定的候選（標題、上傳者、音源、時長、分數）或「匹配失敗」「搜尋失敗」「已排除」；展開看前 5 名、換選、「重搜」（自訂關鍵字）、「排除」。
- 底部「建立歌單」（匹配完才可按；未匹配的數目寫在按鈕旁）。
- 慣例：舊版 `import_preview_page.dart` 的內容（換候選、處理未匹配）；改成全頁是因為大歌單放不進對話框（ADR 0019 §決定 5 稱「匯入預覽頁」）。

### 10.10 設定頁的兩個新區（PR 21、22）

- 區塊順序：帳號、外觀、播放、音樂庫、網路、插件、備份與還原、關於（開發者模式下最後是 Debug）。ADR 0024 §決定 6 加一行（§16）。
- **音樂庫**（PR 21；PR 19 先放匹配目標音源，這一區在 PR 19 出現）：「首頁排行」可拖曳、可勾選的榜單清單（依插件分組顯示名稱）；「匹配目標音源」同樣的清單（§8.3）。
- **網路**區多「排行刷新間隔」（PR 20）。
- **備份與還原**（PR 22）：「匯出備份」「從備份檔還原」（§11）。

## 11. 備份與還原（ADR 0034，決定 3）

- **`lib/data/database/database_backups.dart`**（既有）加：
  - `export(File target)`：`VACUUM INTO` 暫存檔 → 以 `sqlite3` 開暫存檔執行清除（ADR 0034 §決定 2 的清單，寫成 `backupExcludedTables` 與 `backupDeviceColumns` 兩份常數）→ `VACUUM` → 關閉。
  - `stage(Uint8List bytes) → StagedBackup`：寫到 `backups/staged-<UTC>.db` → SQLite 標頭（`SQLite format 3\0`）→ `user_version`（0 或大於 `schemaVersion` 拒絕）→ `PRAGMA integrity_check` → 以 `AppDatabase` 開啟（跑 migration）→ 讀 `installed_plugins` 的 id、名稱、版本、網域給確認框 → 關閉。任何一步失敗刪暫存、拋出可分辨的拒絕理由（`BackupRejected { newerVersion, notFmpBackup, corrupt }`）。
  - `carryOver(StagedBackup, CarriedState)`：把目前的 `accounts` 列、`layout_state` 列、輸出裝置兩欄、`plugin_dev_folder` 寫進暫存檔（先刪暫存檔裡的同類資料）。
  - `restoreStaged(StagedBackup)`：同 M3 的 `restore`（關閉、原檔改名、換檔）。
  - **表的歸類閘門**：`backupExcludedTables` 加上「帶走」清單要等於 `allTables`；新表沒歸類就紅（ADR 0034 §如何確認）。
- **`lib/app/backup.dart`**：
  - 匯出：`export` 到暫存 → 讀位元組 → `FileDialogs.saveFile(name: 'fmp-backup-<UTC>.db', mimeType: 'application/vnd.sqlite3')` → 刪暫存。成功提示存好的位置。
  - 還原：`FileDialogs.pickFile` → `stage` → 確認框（插件與網域、警告、「目前的資料會被取代；取代前會自動備份」）→ `DatabaseBackups.create`（失敗就停）→ 讀目前的帳號列等 → `carryOver` → `restoreStaged` → 重啟（M3 PR 14b 的平台重啟）。
- **Debug 頁的「從備份還原」**（`backups/fmp-*.db`，整份副本）改走同一條：`stage`（以檔案）→ 確認框 → 自動備份 → `carryOver` → 換檔 → 重啟。`DataReset.restoreAndRestart` 不再清 secure storage 與登入 WebView（§17 第 15 條）。「重設資料」不變（照舊清全部）。
- `FileDialogs.pickFile(extension: 'db')` 在 Android SAF 上是否篩得到 `.db`，PR 22 實測；篩不到就讓 `FileDialogs` 收「不篩選」並以內容判斷（`stage` 本來就驗）。
- 換裝置還原後：插件從備份來，`plugin_storage` 是空的（插件重新取得匿名 cookie）；排程的上次成功時間是空的（到期的各跑一次）；登入是這台原本的。
- 慣例：NewPipe、AntennaPod 的資料庫匯出入；舊版保留裝置的輸出裝置與下載資料夾。

## 12. 帶憑證錄製與 `mutates`（PR 12）

M3 留下的（`app/AGENTS.md` § 插件的插件開發工具「已知限制」、account-redaction design §10）：隔離環境只把已存憑證當 `loginVerify` 的輸入；`recordCase` 只在結果是 `LoginAccount` 時換值。M4 的 `libraryRead` 案例需要登入、又不是 `login`。

- **隔離環境帶憑證**：`runIsolatedCase` 在真實與錄製模式、案例標 `requiresLogin` 時，把該插件 `CredentialStore` 的 `activeCredentials` 放進隔離環境的記憶體憑證存放（注入照 ADR 0012 的規則走，網路紀錄記 `credentials: true`）；重播模式不放（fixture 本來就是遮過的）。沒登入照舊「略過」。
- **換值擴大**：所有 `requiresLogin` 的案例，寫檔前以該插件 `accounts` 列的 `userId`、`displayName`、頭像換掉錄到的流量（`scrubAccount`），再以 `accountLeaks` 檢查，換完仍看得到就不寫。不靠鍵名（分不出自己和別人）。`login` 案例的行為不變（它的帳號來自結果）。
- **`mutates`**：§4.7。
- **健康檢查**同樣：`requiresLogin` 的非 `login` 案例在已登入時帶憑證跑；`mutates` 略過。
- 閘門（測試檔內雙向變異）：`dev_case_runs_test.dart`／`account_scrub_test.dart`——含自己顯示名稱的 `libraryPlaylists` 回應換值後才寫、換值後仍有殘留就不寫；改一個無關欄位（歌單標題）不擋；重播模式不帶憑證；`mutates` 在真實、錄製、健康檢查、命令列錄製都不呼叫插件、在重播照跑。

## 13. 錯誤與 log

- tag：`library`（匯入、刷新、遠端操作）、`charts`、`matching`（外部匯入）、`backup`。訊息英文，結構化欄位放插件 id、歌單 id、筆數、代際，不放歌單名稱與曲名（ADR 0011 §決定 6：診斷包不含歌單內容）。
- 背景（`playlist-refresh`、`charts:*`、寫入後的刷新）：錯誤經 `log.report` 進錯誤歷史，不提示；狀態寫進資料庫或記憶體標記（§5.3、§6.2）。
- 使用者操作（匯入、手動刷新、加入／移除遠端、備份、還原）：照 ADR 0013 的呈現表提示；部分成功列出失敗項。
- 新的 log 行：`Playlist refresh finished`（`playlistId`、`result`、`added`、`removed`、`generation`）、`Playlist refresh discarded`（過期）、`Chart refresh finished`、`Backup exported`、`Backup restore staged`、`Backup restored`（不記檔名路徑以外的內容；路徑經家目錄替換）。

## 14. 測試策略

各節的閘門合起來；這裡列分層與共用的做法。

| 層 | 內容 | PR |
|---|---|---|
| 資料庫 | migration 三種、CHECK、外鍵、孤兒、索引；`playlist_repository_test.dart` 的 `stored format`、排序、重寫 `position` | 1、8a、19、20 |
| 刷新器 | ADR 0019 §如何確認＋ADR 0033 §如何確認的案例；以假插件（腳本化的頁）與記憶體資料庫；**先寫測試再寫實作** | 8a |
| 排程 | 排程器的假時鐘模式（`background_scheduler_test.dart` 的寫法）：到期選擇、全部失敗才退避、互斥、取消 | 10、20 |
| 插件契約 | 各能力的 `*_capability_test.dart`、`type_definitions_test.dart`、`checks_test.dart`、`contract_runner_test.dart`；四個官方插件與兩個新插件在 `fmp-plugins` CI | 6、13、14、15、20 |
| 匹配 | 評分核心的語料、繁簡字表的重產比對、自動與手動重搜同分 | 16 |
| 外部匯入 | `ExternalImport` 以假插件：沿用 `match_results`、合併前 5、門檻、搜尋失敗不中斷、取消 | 19 |
| 備份 | 真的檔案資料庫（`Directory.systemTemp`）：ADR 0034 §如何確認的全部 | 22 |
| widget | 導覽、首頁、音樂庫、詳情（四種狀態列）、多選、匯入對話框、預覽頁、帳號頁歌單、設定兩區；guideline | 各 UI PR |
| 整合 | 不新增整合測試檔（端到端由實機驗收）；外殼改動照 `app/AGENTS.md` § 驗證跑 `toast_layering_test.dart` 並加新路由 | 2、3、19 |

- 零聯網照舊；需要 HTTP 的以假 adapter 或 `fmp-test`。

## 15. 新增的依賴

2026-10-15 pub.dev API 的 `latest`；加依賴時再核對一次，裝當前 stable。

| 套件 | 版本 | 授權 | 用途 | 擁有者 | PR |
|---|---|---|---|---|---|
| `unorm_dart` | 0.3.3（2026-10-04） | MIT | NFKC | `lib/core/matching/` | 16 |
| `string_similarity` | 2.2.0（2026-04-04） | MIT | Dice | `lib/core/matching/` | 16 |

- 兩個都純 Dart、沒有依賴、五平台；不需要 plugin registrant 或 16KB 對齊檢查。
- 沒有選的：`opencc`（§8.2）、`flutter_opencc_plus`（備案）、`pinyin`（資料對比對有缺口）、`flutter_open_chinese_convert`（沒有 Windows）、`fuzzywuzzy`（GPL-2.0，ADR 0019 否決）。
- 拖曳排序與多選用 Flutter 內建（`ReorderableListView`、`SliverReorderableList`），不加套件。

## 16. 文件同步與既有 ADR 的更正

只加一行補充或更正，不改決定（根 `AGENTS.md` § Decisions）。**擁有者核准本設計後，PR 0 一次加**（標「各 PR」的在用到它的 PR 加）；規劃階段不動既有 ADR。下面「原文」是要加的句子。

| 文件與位置 | 原文 | 何時 |
|---|---|---|
| ADR 0010 §決定 4 末尾 | 補充（2026-10-15，M4 PR 0）：`app/` 的備份檔與還原見 ADR 0034；本 ADR 只管舊版備份檔（JSON）的匯入（M5）。 | PR 0 |
| ADR 0011 §決定 7 末尾 | 補充（2026-10-15，M4 PR 0）：「音樂庫與同步」組在 M4 沒有欄位、不建表——排行刷新間隔在「網路」組、匹配目標音源在每音源設定表、首頁排行在 `chart_settings`、匯入歌單的間隔在 `playlist_remote`（ADR 0033）；「設定包含在備份中」的備份見 ADR 0034（裝置專屬的值不帶走）。 | PR 0 |
| ADR 0012 §決定 2 末尾 | 補充（2026-10-15，M4 PR 0）：歌單匯入與刷新的請求一律 `userPreference`；讀私人歌單被拒、這次沒帶憑證而使用者已登入時，插件以 `required` 重送一次（ADR 0032 §決定 2）。 | PR 0 |
| ADR 0015 §決定 4 末尾 | 補充（2026-10-15，M4 PR 0）：案例可標 `mutates: true`（會改動遠端），只在契約測試重播；健康檢查、冒煙、錄製一律略過，fixture 手寫（ADR 0032 §決定 7）。 | PR 0 |
| ADR 0017 §決定 6 末尾 | 補充（2026-10-15，M4 PR 0）：排行間隔在「網路」組；匯入歌單的間隔是每張歌單的資料，刷新由一個全域工作每 30 分鐘檢查到期的歌單、依序刷（ADR 0033 §決定 4）。 | PR 0 |
| ADR 0019 §決定 1 末尾 | 補充（2026-10-15，M4 PR 0）：`playlist_remote` 另有刷新間隔（空＝不啟用，新匯入 24 小時），舊版的 `notifyOnUpdate` 不保留；Mix 歌單存插件 id 與種子曲目；欄位見 ADR 0033 §決定 1。 | PR 0 |
| ADR 0019 §決定 2 第二條之後 | 補充（2026-10-15，M4 PR 0）：「已失效」記在歌單項目（該遠端歌單上次刷新的觀察），不記在曲目（ADR 0033）。 | PR 0 |
| ADR 0019 §決定 5 末尾 | 補充（2026-10-15，M4 PR 0）：前 5 名是所有目標音源合併評分後的前 5，同分依使用者排序；第一名過門檻才自動選；未匹配的歌只存在 `match_results` 並在預覽頁標示，不進歌單（ADR 0033 §決定 12）。 | PR 0 |
| ADR 0019 §決定 6 末尾 | 更正（2026-10-15，M4 PR 0）：繁簡統一不用 `opencc` 套件（stable 版依賴 build hooks 穩定前的實驗 API、沒有 Android 預編譯庫），改用 OpenCC `TSCharacters.txt` 產生的純 Dart 字級對照（Apache-2.0，M4 `design.md` §8.2）。 | PR 0 |
| ADR 0019 §後果「壞的」第二條之後 | 更正（2026-10-15，M4 PR 0）：改用純 Dart 字表後沒有 native assets，不需要各平台的建置驗證。 | PR 0 |
| ADR 0024 §決定 3 表後 | 補充（2026-10-15，M4 PR 0）：導覽目的地是 首頁｜搜尋｜音樂庫｜電台｜設定，各寬度同一組，每個目的地有自己的巢狀導覽（ADR 0033 §決定 5）。 | PR 0 |
| ADR 0024 §決定 6 的 M3 補充之後 | 補充（2026-10-15，M4 PR 0）：設定頁另有「音樂庫」（首頁排行、匹配目標音源）與「備份與還原」區，順序：帳號、外觀、播放、音樂庫、網路、插件、備份與還原、關於。 | PR 0 |
| ADR 0025 §決定 9 的 M3 更正之後 | 更正（2026-10-15，M4 PR 0）：E16 的備份檔見 ADR 0034；Debug 頁的「從備份還原」與它走同一條還原路徑，保留目前的登入，取代上一則的「還原後要重新登入」。 | PR 0 |
| ADR 0026 §決定 3 的 M3 修訂之後 | 修訂（2026-10-15，M4 規劃時擁有者決定）：M4 拆成 M4a「音樂庫與平台歌單」與 M4b「外部匯入、排行與備份」，M5 依賴 M4b；明細見 `milestones.md`。 | PR 0 |
| ADR 0028 §決定 4 末尾 | 更正（2026-10-15，M4 PR 0）：M4 的 Mix 歌單存插件 id 與種子曲目，不存 `mixId`（續取的 `cursor` 必填，`mixId` 開不了新的 Mix）（ADR 0033 §決定 3）；M4 的四個能力見 ADR 0032。 | PR 0 |
| ADR 0030 §決定 12 末尾 | 補充（2026-10-15，M4 PR 0）：App 開在首頁，首頁也顯示同一個引導（ADR 0033 §決定 6）。 | PR 0（§17 第 16 條確認後） |
| ADR 0031 §決定 3 末尾 | 更正（2026-10-15，M4 PR 0）：M4 的導覽是 首頁｜搜尋｜音樂庫｜電台｜設定，歷史移進音樂庫（ADR 0033 §決定 5）；§如何確認的「四個導覽項」改為五個。 | PR 0 |
| ADR 0031 §決定 11 末尾 | 更正（2026-10-15，M4 PR 0）：M4 的 `playlists.kind = mix` 存插件 id 與種子曲目，不存 Mix 身分（ADR 0033 §決定 3）。 | PR 0 |
| ADR 0032–0034 | 依確認結果修訂，狀態改「已採納」、日期改核准日 | PR 0 |
| `milestones.md` § M4 | 拆成 M4a、M4b 兩節與兩列（依賴：M4a←M3b、M4b←M4a、M5←M4b）；範圍照 `prd.md`；驗收照 `prd.md`（拿掉「`opencc` native assets 建置」）；「舊版頁面對照」表：播放歷史頁 → 「音樂庫頂端的『歷史』」（M4a），帳號頁「管理歌單」與粉絲勳章 → 帳號頁「歌單」「從帳號匯入電台」（M4a），首頁／探索／首頁排行設定 → M4b（排行）與 M4a（其他區塊）等七列標到半 | PR 0 |
| `09-26-fmp-rewrite/task.json` | 子任務清單加本任務 | PR 0 |
| `app/AGENTS.md` | § 資料層（新表與閘門）、§ 插件（四個能力、`mutates`、隔離環境帶憑證）、§ 排程器（兩種新工作）、§ 設定（排行間隔、每音源的匹配欄位）、§ 介面（導覽、首頁、音樂庫、詳情、多選、預覽、設定兩區）、§ Lint；新增 § 音樂庫、§ 排行、§ 備份 | 各 PR |
| `.trellis/spec/app/` | `data/`（歌單 repository、重寫 `position`、備份的歸類清單）、`plugins/`（寫四個能力、`mutates`、`requiresLogin` 的錄製）、`ui/`（外殼的巢狀導覽、首頁、音樂庫、多選）、`settings/`、`lints/` | 各 PR |
| `fmp-plugins` 各插件 README | 能力、端點、私人歌單重送、網易 `X-Real-IP` 的結果 | 各插件 PR |

## 17. 需要擁有者確認的決定

這些改動到 ADR 的文字、舊版行為，或是本設計才提出的產品行為（標「新」）。第 1–14 條來自 decisions「需要擁有者確認的技術決定」，照建議寫；第 15–18 條是本設計新提出的（標「新，已確認」）。**2026-10-15 擁有者核准：18 條全部照建議。**另決定「在遠端新增歌單」不做真實實測，只用測試插件重播驗。

1. **繁簡統一改用 OpenCC 字表產生的純 Dart 對照**，不用 `opencc` 套件；ADR 0019 §決定 6 與 §後果更正，`milestones.md` 的「`opencc` native assets 建置」驗收換成繁簡測試。建議：照做（§8.2）；要完整 OpenCC 時改 `flutter_opencc_plus` 並先實測建置。
2. **Mix 歌單存「插件 id＋種子曲目」**，不存 `mixId`；ADR 0028 §決定 4、ADR 0031 §決定 11 更正。建議：照做（`cursor` 必填，`mixId` 開不了新的 Mix；舊版也存種子）。
3. **`checks.json` 的案例可標 `mutates: true`**：只在契約重播跑，健康檢查、冒煙、App 內錄製略過；ADR 0015 §決定 4「一份四用」的例外。建議：照做（否則健康檢查會改你的遠端歌單）。
4. **私人歌單的刷新**：以 `userPreference` 讀，被拒且這次沒帶憑證、使用者已登入時，以 `required` 重送一次；ADR 0012 §決定 2 補一行。效果：關掉「以登入身分瀏覽與播放」仍能刷新自己的私人收藏夾，公開收藏夾不登入也能匯入。建議：照做。
5. **`playlist_remote` 加刷新間隔（空＝不啟用、新匯入 24 小時）；不保留舊 `notifyOnUpdate`**（舊版只存不讀）；ADR 0019 §決定 1 補一行。建議：照做。
6. **匯入不再自動改名**（舊版 `_generateUniqueName`）：名稱不唯一，重新匯入靠遠端 id。建議：照做。
7. **匹配的「前 5 名」是所有目標音源合併評分後的前 5**（舊版每音源各 5 個）；ADR 0019 §決定 5 補一行。建議：照做（與 ADR 0014 §決定 9「比較取最高分」一致）。
8. **（新）匹配目標音源預設含網易**（舊版只有 B 站、YouTube），可在設定頁拖曳排序與取消勾選。建議：照做（網易現在能播；不想要可以取消）。
9. **（新）「音樂庫與同步」設定組在 M4 不建表**：排行間隔放「網路」組，匹配目標放每音源設定表，首頁排行放 `chart_settings`，每張歌單的間隔放 `playlist_remote`。建議：照做（沒有欄位的空表沒有讀者）。
10. **（新）「加入遠端歌單」對話框不預先勾出已含該曲目的歌單**（舊版 B 站有），重複的由插件略過並回報「已存在」。建議：照做；要的話之後加選填匯出。
11. **「已失效」記在歌單項目**（該遠端歌單上次刷新的觀察），不記在曲目；ADR 0019 §決定 2「曲目……可用狀態」補一行。建議：照做（同一首在本機歌單不受影響；符合 ADR 0010「只存事實」）。
12. **未匹配的外部歌曲只存在 `match_results` 並在預覽頁標示**，不進本地歌單；同一首再匯入時沿用先前的匹配與改選。建議：照做（歌單項目一定要有曲目；ADR 0014 §決定 9「結果持久化、匹配失敗保留並標示」的落地）。
13. **（新）「從帳號匯入電台」用中性字樣**，不寫「粉絲勳章」，只在插件提供時出現。建議：照做（宿主沒有音源分支）。
14. **（新）歌單卡保留舊版的「隨機加入」**（ADR 0018 沒有寫）。建議：照做（舊版行為、成本很小）。
15. **（新，已確認）Debug 頁的「從備份還原」也保留目前的登入**：與設定頁的還原走同一條路徑（§11），M3 PR 14b「還原先清憑證與登入 WebView」的行為拿掉；ADR 0025 §決定 9 更正。「重設資料」照舊清全部。建議：照做（決定 3 的「保留登入」若只套用在設定頁，兩個還原入口的結果會不同；一條路徑也少一份程式碼）。
16. **（新，已確認）App 開在首頁，首頁也顯示首次啟動引導**：沒有任何已啟用、具 `search` 能力的插件時，首頁與搜尋頁顯示同一個引導；ADR 0030 §決定 12 補一行。建議：照做（導覽的第一項是首頁，新使用者打開 App 看到的是首頁；不做的話首頁只會是一片空白，要自己找到搜尋頁）。替代：首次啟動時開在搜尋頁。
17. **（新，已確認）只屬於這台的值不跟著備份走**：除了決定 3 排除的四張表，備份檔另清掉輸出裝置（兩欄）、插件開發資料夾路徑、插件開發工具補的標記列；還原時保留這台目前的值。建議：照做（舊版匯入時就保留這台的輸出裝置；開發資料夾路徑在別台沒有意義，還可能含使用者名稱）。
18. **（新，已確認）外部匯入（Spotify、QQ）讀歌單時任何一頁失敗就不進匹配**，停在錯誤畫面與「重試」，不建「部分」的歌單（§8.4）。建議：照做（外部匯入建出的是本機歌單、之後不會刷新，缺頁的清單建了就永遠缺；平台歌單的「部分完成」靠下一次刷新補齊，這裡沒有下一次）。
19. **（新，2026-10-21 已確認）能播的插件的歌單也可以「配對到其他音源」**：匯入對話框認出網址屬於有 `resolveStream` 的插件時多一個選項「配對到其他音源」（預設仍是「匯入為平台歌單」），選了就走 §8.4 的匯入預覽、建 `local` 歌單、不刷新；只有 `importPlaylist` 的插件只有這一條路。不針對任何插件 id，所有能播的插件都有。插件端沿用 `importPlaylist`，不另加能力或 manifest 旗標（配對是宿主的用法，資料與平台歌單完全相同；私人歌單以 `required` 重送照舊）。這次匯入的目標音源預設不勾來源插件自己，預覽頁的 chip 可勾回。Spotify、QQ 照 §4.8 只做匯入，不刷新、不做成可播的音源。PR 19 開頭在 ADR 0019 §決定 5、ADR 0033 §決定 12、本檔 §5.1 第 3 步、§8.3、§8.4、§10.9 補上。

## 18. 回滾

- 每個 PR 獨立合併；只動 `app/`、`docs/`、`.trellis/`、`.claude/skills/verify-on-device/`，以及 `fmp-plugins` repo。舊專案、`release.yml`、`ci.yml` 不動。
- **schema 變更**：App 還沒發版，revert 一個加表的 PR 等於回到上一版快照；dev 資料庫已升級的本機刪掉 dev 資料目錄重來（`app/AGENTS.md` § 資料目錄）。
- **fmp-plugins**：在該 repo 單獨 revert；index 以腳本重產。FMP 先 revert 宿主契約時，宣告新能力的插件會被拒載（能力名稱 FMP 認得、匯出對不上），所以 `fmp-plugins` 要同步 revert 或 FMP 不 revert 到契約 PR 之前（M3 的同一條）。
- **導覽（PR 2）**：revert 後回到四項導覽，歌單資料仍在資料庫（沒有入口）。
- **備份（PR 22）**：revert 後設定頁沒有備份區；已匯出的檔仍是一般的資料庫副本，Debug 頁的還原（M3 的行為）讀得了它，但會清掉登入。
- **M4a 與 M4b 的界線**：M4a 驗收後才開 M4b 的 PR（PR 16、20 可提前，見 `implement.md`）；M4b 整個不做時 M4a 仍是可交付的一半（本機與平台歌單、遠端編輯、新導覽）。
