# M2 設計

各項行為以 ADR 0008–0027 為準。這份只寫：

- 跨 PR 的結構；
- ADR 留給「開工時決定」的技術選擇；
- 擁有者七個決定（`prd.md`「擁有者的決定」，下稱「決定 n」）的落地方式；
- `research/m2-scope-digest.md` §5 的 25 條未定之處（下稱「§5.n」）的決定。每條附理由與依據（ADR 章節、舊版行為、M1 先例，或查證過的慣例）。

套件與 API 的事實在 2026-10-01 查證：context7（`audio_service`、`flutter_cache_manager`、`connectivity_plus`）、Android 官方文件，以及本機 pub cache 與 Flutter 3.47.5 SDK 的原始碼（`just_audio` 0.10.6、`audio_service` 0.18.19、`smtc_windows` 1.1.0、`flutter_cache_manager` 3.4.2、`cached_network_image` 4.0.0、`media_kit` 1.2.6、`path_provider_windows` 2.3.0）。版本號以 digest §3（pub.dev API）為準，加依賴時再核對一次。

## 0. 未定之處對照

| §5 | 題目 | 決定在 |
|---|---|---|
| 1 | 播放歷史的資料與頁面 | §3.1、§3.2、§7.8、§9.7 |
| 2 | 佇列持久化與 `tracks` 的先後 | §3.1、§7.7 |
| 3 | 「播放」設定組欄位 | §3.3 |
| 4 | E19 範圍 | 決定 3；§7.6 |
| 5 | 輸出裝置的平台條件 | §7.6、§9.2 |
| 6 | 系統媒體控制細節 | §8 |
| 7 | 圖片快取與媒體 client | 決定 1；§4 |
| 8 | 離線功能裡 M2 做不到的 | §5.4、§1.2 |
| 9 | 排程器沒有工作 | 決定 2（M3）；§1.2 |
| 10 | 啟動維護清單內容 | §6 |
| 11 | `cache.db` 位置與 lint | §2、§4.2 |
| 12 | 移除插件的事件 | §4.4 |
| 13 | 佇列操作入口 | §7.3 |
| 14 | 臨時播放觸發、`detached` | §7.2、§7.3 |
| 15 | M3 功能的測試 | §1.2、§12 |
| 16 | 離線時 ADR 0016 與 0018 的優先序 | §5.3 |
| 17 | 輸入框內的快捷鍵 | §9.5 |
| 18 | `AudioController` 名稱、Debug 頁資料 | §11、§1.2 |
| 19 | 網址期限的兩個數字 | §7.4 |
| 20 | 快取鍵的「音質偏好」 | §7.4 |
| 21 | 舊資料匯入的預留 | §3.6 |
| 22 | 播放頁分頁內容、分頁記憶、右側面板 | §3.4、§9.3、§9.4 |
| 23 | 毛玻璃的偵測 | §9.3 |
| 24 | Android 返回鍵 | 決定 7；§9.1 |
| 25 | 位置存檔時機、計時器擁有者 | §7.7、§1.2 |

## 1. 範圍

### 1.1 M2 範圍對照

| 範圍（`milestones.md` § M2 與決定 1–7） | 節 | PR（`implement.md`） |
|---|---|---|
| 完整 `QueueModel`、`RecoveryPolicy` | §7.1–§7.5 | 1、7、9、10、11、12 |
| 播放頁 B、播放列三段、快捷鍵全表、焦點三區 | §9 | 17、18a、18b |
| 右側「正在播放」面板（決定 6） | §9.4 | 19 |
| 系統媒體控制 | §8 | 16a、16b |
| E19 速度、音量、輸出裝置（決定 3） | §7.6 | 13 |
| 播放歷史與「歷史」導覽項（決定 5） | §7.8、§9.7 | 15 |
| 統一快取庫、離線狀態 | §4、§5 | 2、4、5 |
| 媒體 client、封面磁碟快取（決定 1） | §4.1、§4.3 | 3、4 |
| 啟動維護清單、log 保留 7 天（決定 2） | §6 | 6 |
| 「播放」設定組（決定 4） | §3.3 | 8 起逐步接上 |
| 音質與格式偏好進插件（決定 4） | §7.4、§10 | 8 |
| Android 返回鍵（決定 7） | §9.1 | 16a |

### 1.2 M2 不做的事

| 項目 | 理由與去處 |
|---|---|
| `BackgroundScheduler`、lint `fmp_periodic_timer_owner`、排程器的「上次成功時間」表與三組刷新間隔設定 | 決定 2：M3 與第一個真工作（電台狀態）一起做。M2 的週期計時器只在 `lib/playback/`（ADR 0018 §決定 11 的允許擁有者），M3 加 lint 時不會有違規 |
| `mix`、`live` 模式與它們的測試（Mix 修剪、開直播取消音樂請求） | 插件能力 `mix`、`live` 在 M3（`milestones.md:63`）。`QueueModel` 只在有呼叫端時加模式，不為 M3 先蓋（§7.2）。驗收範圍的調整見 §12 |
| `detached` 模式 | ADR 只有名字沒有定義（§5.14）；它對應的舊版「脫離佇列」只出現在臨時播放，`temporary` 已涵蓋（§7.2） |
| 「已下載曲目照常播放、未下載的淡化並跳過」（ADR 0016 §決定 7） | 下載在 M6；M2 沒有「已下載」的概念，§5.3 的規則留好 M6 接上的位置但不先寫分支 |
| 歌詞內容、`trackDetail` 的詳細資料 | M7、M3。M2 的歌詞欄只有「沒有歌詞」的空狀態（§9.3），詳細欄只放現有資料（決定 6） |
| 被取代的 `resolveStream` 取消網路工作（ADR 0018 §決定 6，M1 follow-up 5） | 要讓宿主知道每個 `fmp.http.request` 屬於哪一次插件呼叫，需要改宿主 API 的呼叫上下文；M2 的網址快取與進行中請求共用（§7.4）已消掉重複解析。留給 M3 動插件 API 時一起設計 |
| ADR 0025 §決定 5 Debug 頁要讀的播放資料（下次重試時間、串流格式等） | M3 有讀的人時再加欄位，M2 不預留（`PlaybackState.Retrying` 已帶 `attempt` 與 `delay`） |
| 設定頁「鍵盤快捷鍵」清單、全域快捷鍵 | M8（ADR 0024 §決定 8、`milestones.md:110`） |
| Linux（`audio_service_mpris`）、macOS、iOS 的系統媒體控制 | 平台任務（ADR 0026 §決定 4 修訂） |
| `POST_NOTIFICATIONS` 與 `PermissionGateway` | Android 13 起媒體工作階段的通知不受通知權限限制（§8.3）；權限閘道在 M6（ADR 0020 §決定 9） |
| 舊資料匯入 | M5（ADR 0026 §決定 2「M5 起」；§3.6 說明 M2 的格式怎麼對得上） |

## 2. 新增的模組與目錄

```
lib/
  app/
    startup_maintenance.dart        # 啟動維護清單（§6）
  core/network/
    media_http_client.dart          # 媒體 client（§4.1）
    network_status.dart             # NetworkStatus 與狀態機（§5）
  data/
    cache/                          # 快取模組：唯一擁有快取目錄與 cache.db（§4.2）
      cache_database.dart           # 第二個 @DriftDatabase
      cache_tables.dart
      cache_store.dart              # 索引、淘汰、用量、清除、移除插件
      image_cache_manager.dart      # flutter_cache_manager 的三個介面接到 cache_store
    repositories/                   # tracks、queue、player_state、play_history、各設定組、layout_state
  domain/
    track_info.dart                 # TrackInfo（曲目鍵＋顯示資料，§3.1）
  platform/
    cache_directory/                # getApplicationCacheDirectory（path_provider 只在平台層）
    connectivity/                   # connectivity_plus（§5.1）
    media_controls/                 # audio_service、smtc_windows（§8.1）
  playback/
    playback_session.dart           # 唯一碰 AudioBackend 的協作者（§7.1）
    playback_event_router.dart      # 純函數：後端事件 → 控制器動作（§7.1）
    now_playing_publisher.dart      # 系統媒體控制的唯一出口（§8.2）
    queue_store.dart                # 佇列與播放狀態的持久化（§7.7）
  plugins/
    plugin_artwork.dart             # 每插件的封面 cache manager（§4.3）
  ui/
    history/                        # 歷史頁（§9.7）
    player/                         # 播放列、播放頁、佇列、詳細、右側面板
drift_schemas/cache_database/       # cache.db 的快照（§4.2）
```

`fmp_layer_imports` 的表（`packages/fmp_lints/lib/src/rules/layer_imports.dart`）要改的地方：

| 表 | 改動 | PR |
|---|---|---|
| `externalPackageOwners` | 加 `flutter_cache_manager: lib/data/cache`、`cached_network_image: lib/ui/artwork`、`audio_session: lib/playback/backends`。`connectivity_plus`、`audio_service`、`smtc_windows`、`path_provider` 已在 `platformPackages`（只准在 `lib/platform/`） | 4、13 |
| 新的 `restrictedImports`（被匯入端 → 允許的匯入端） | 一個通用機制取代逐條特例：`lib/playback/backends/audio_backend.dart` 只給 `lib/playback/backends/`、`lib/playback/playback_session.dart`、`lib/playback/playback_providers.dart`（組裝點）；`TrackEndReason` 所在的 `backend_rules.dart` 只給 `lib/playback/backends/`、`lib/playback/playback_event_router.dart`；`lib/platform/cache_directory/` 只給 `lib/data/cache/`、`lib/main.dart`、`lib/platform/platform.dart`（組裝點，PR 4 加） | 1、4 |

- 這三條就是 ADR 0018 §如何確認的兩條（`app/AGENTS.md:410-411` 寫明等 M2）與 ADR 0016 §如何確認的「快取目錄只經快取模組取得」。
- 用同一張表而不是三個特例：`sealedDirectories`（只准自己匯入）是它的特例，但不併進來，免得動到 M1 的閘門。
- 每條都照 `.trellis/spec/app/lints/index.md` 寫雙向變異案例。

快取模組放在 `lib/data/cache/`，不另開頂層目錄（§5.11）：

- 它要用 drift，而 `drift` 的擁有者是 `lib/data`（`app/AGENTS.md:195`）；
- ADR 0010 §決定 1「只有資料層能存取資料庫」不必為第二個資料庫開例外；
- `externalPackageOwners` 是一對一的表，放頂層就要改成一對多。

## 3. 資料

### 3.1 曲目顯示資料：把 `tracks` 表提前到 M2（§5.1、§5.2）

**決定**：佇列與播放歷史都以外鍵參照 `tracks`。把 ADR 0019 的 `tracks` 表提前到 M2，只建表與 repository，不帶 M4 的其他表。

**理由**：

- **ADR 0010 §決定 2「只存事實」與「曲目以 `TrackKey` 字串為唯一鍵」**：
  - 快照的做法是在每個佇列項目、每筆歷史各存一份曲名與封面，同一首重複存好幾份；
  - M4 加 `tracks` 時還要把快照搬進去，是一次改寫使用者資料的 migration。
- **ADR 0019 §決定 1 的孤兒定義**已經寫「沒有被歌單項目、佇列、下載紀錄參照」，表示原設計就是佇列參照 `tracks`。
- **M4 的影響**：只加欄位（可空欄位的 migration 不碰資料）與 `track_origins` 等新表；刷新與匯入照 ADR 0019 §決定 2 更新元資料時，佇列與歷史自動顯示新曲名。
- **M5 的影響**：舊 `PlayHistory` 是快照（`docs/audit/data.md` §1.2），匯入時先以快照 upsert `tracks` 再寫歷史，鍵逐字相同（`TrackKey`，`app/AGENTS.md:213-216`）。

**欄位**只放 M2 用得到、而且是音源給的事實；全部來自 `TrackSummary`（`lib/plugins/source_dto.dart`）：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `track_key` | text，主鍵 | `TrackKey.format` 的輸出 |
| `source_type_id`、`source_id`、`cid` | text、text、int? | 曲目鍵三段，查詢與 M5 對照用 |
| `title` | text | |
| `uploader` | text? | |
| `duration_ms` | int? | |
| `artwork_json` | text? | `[{url, width?}]`，ADR 0016 §決定 4 的 DTO 原樣 |
| `updated_at` | int（UTC epoch 毫秒） | 最後一次 upsert |

- **寫入時機**：曲目進入佇列、臨時播放、寫歷史之前 upsert，同鍵以新值覆蓋（音源是權威，ADR 0019 §決定 2 同一方向）。搜尋結果本身不寫。
- **上層型別**：`lib/domain/track_info.dart` 的 `TrackInfo`（曲目鍵三段、曲名、上傳者、時長、`List<TrackArtwork>`）。`TrackSummary` 是插件 DTO，在 `lib/plugins/` 加轉換；`domain/` 不 import `plugins/`。
- **孤兒清理**：從 M2 起登記在啟動維護清單（§6）。M2 的參照者只有佇列與歷史，M4 在同一個查詢加歌單項目，M6 加下載紀錄。
- **ADR 0019 一行更正**：`tracks` 提前到 M2，孤兒定義加上「播放歷史」（§11）。這是 ADR 層級的範圍改動，列入 §12 請擁有者確認。

### 3.2 主資料庫的新表

| 表 | 欄位 | 說明 | PR |
|---|---|---|---|
| `network_settings`（單列） | `cache_limit_mb` int? | 「網路」組，見 §3.3 | 5 |
| `playback_settings`（單列） | 見 §3.3 | 「播放」組 | 8 |
| `tracks` | 見 §3.1 | | 14 |
| `queue_entries` | `position` int 主鍵、`track_key` FK→`tracks`（`ON DELETE RESTRICT`）、`shuffle_rank` int? | 佇列的每個位置；隨機順序以位置為單位（ADR 0018 §決定 5），所以 `shuffle_rank` 跟著位置走，不跟著歌 | 14 |
| `player_state`（單列） | `current_position` int?、`position_ms` int、`loop_mode` text、`shuffle_enabled` bool、`volume` real、`muted` bool、`updated_at` int | ADR 0018 §決定 10 列的其餘欄位。`Mix 身分`、`模式` 不建（§7.2、§7.7） | 14 |
| `play_history` | `id` int 自增主鍵、`track_key` FK→`tracks`（`RESTRICT`）、`played_at` int；索引 `played_at` | 一次播放一列 | 15 |
| `layout_state`（單列） | `player_tab` text?、`panel_expanded` bool?、`panel_width` real? | 依裝置記住的版面狀態，見 §3.4 | 18a |

- 列舉一律存 `converters.dart` 寫死的字串（`app/AGENTS.md:213`）。
  - `loop_mode`：`off`／`all`／`one`；
  - `player_tab`：`lyrics`／`queue`／`details`；
  - 音質：`high`／`medium`／`low`；
  - 格式偏好：`opus,aac`／`aac,opus`（與舊版 `audioFormatPriority` 的字面值相同，M5 直接對得上）。
- **佇列寫入**：以差量寫，同一個 transaction 只改受影響的列。
  - 操作有插入、移除、移動、整份取代、改隨機順序；
  - 位置位移先把受影響的列改成負值再改回，避開主鍵衝突。
  - 閘門：repository 測試以固定種子跑一串隨機操作，每一步讀回都等於 `QueueModel` 的狀態。

### 3.3 設定組的欄位（決定 4，§5.3；ADR 0026 §決定 2「在引入該組的里程碑定案」）

「播放」組 `playback_settings`：欄位全部可空，空＝沒設定過，預設只在 Notifier 套用（`app/AGENTS.md` § 設定）。

| 欄位 | 設定名 | 預設 | 選項 | 舊版欄位（`data.md` §7） | 用到它的 PR |
|---|---|---|---|---|---|
| `audio_quality` | 音質 | `high` | 高／中／低 | `audioQualityLevelIndex`（0） | 8 |
| `audio_format_priority` | 格式偏好 | `opus,aac` | Opus 優先／AAC 優先 | `audioFormatPriority` | 8 |
| `remember_position` | 記住播放位置 | 開 | 開關 | `rememberPlaybackPosition` | 10 |
| `temp_play_rewind_seconds` | 臨時播放回佇列倒退秒數 | 10 | 0／3／5／10／15／30（舊版 `_rewindOptions`） | `tempPlayRewindSeconds` | 10 |
| `skip_preview_clips` | 跳過試聽片段 | 開 | 開關 | 無（ADR 0018 §決定 7 新增） | 12 |
| `output_device_id`、`output_device_name` | 輸出裝置（只有 Windows） | 空＝系統預設 | 播放列選單 | `preferredAudioDeviceId／Name` | 13 |
| `restart_rewind_seconds` | 重啟恢復時倒退秒數 | 0 | 同上 | `restartRewindSeconds` | 14 |
| `play_history_limit` | 播放歷史保留筆數 | 10000 | 1000／5000／10000／50000（舊版 `_options`） | `playHistoryLimit` | 15 |
| `auto_scroll_to_current` | 切歌時捲到目前歌曲 | 關 | 開關 | `autoScrollToCurrentTrack` | 18b |

- **整張表在 PR 8 一次建好**：欄位清單在本設計已定案，只做一次 migration。
  - repository 的 `write`／`clear` 照 M1 外觀組的形狀一次涵蓋全部欄位；
  - Notifier 的各欄位 setter 與設定頁的那一列，跟著用到它的 PR 加（`.trellis/spec/app/data/index.md`「只加有人呼叫的方法」）。
- **「網路」組 `network_settings`**：只有「快取上限」，選項 128／256／512／1024 MB，空＝平台層宣告的預設（ADR 0016 §決定 3）。
  - 放「網路」組：ADR 0011 §決定 7 的八組裡，快取的內容都是網路抓來的，M3 的刷新間隔與 M3 之後的網路設定也在這組。
  - 舊版的快取設定不匯入（ADR 0016 §決定 3）。
- **速度不持久化**（ADR 0018 §決定 10、E19）。
- **音量、靜音不是設定**，隨佇列存在 `player_state`（ADR 0018 §決定 10）。靜音記住靜音前的音量；重啟後維持靜音，取消靜音回到記住的值。決定 3「記住、靜音」照字面落地；舊版的靜音前音量只在記憶體。

### 3.4 版面狀態不進設定組（§5.22）

- 播放頁右欄上次的分頁、右側面板的展開與寬度，放在 `layout_state`，不放外觀組。
- 理由：
  - ADR 0024 §決定 4 說「依裝置記住」；
  - 設定包含在備份裡（ADR 0011 §決定 7），M4 還原到另一台裝置時，手機會帶來桌面的面板寬度。
  - `layout_state` 不屬於任何設定組，M4 的備份不收它。
- 寬度在資料庫只擋明顯的壞值（例如 > 1600），實際範圍在讀取時依視窗夾取（舊版 `app_layout.dart` 的 `detailPanelStoredMax` 同一做法）。

### 3.5 schema 版本與測試

- 主資料庫依 PR 合併順序遞增：v2 `network_settings`（PR 5）→ v3 `playback_settings`（PR 8）→ v4 `tracks`、`queue_entries`、`player_state`（PR 14）→ v5 `play_history`（PR 15）→ v6 `layout_state`（PR 18a）。實際號碼以合併順序為準。
- 每次都照 `.trellis/spec/app/data/index.md` § 改 schema：快照、`stepByStep`、三種 migration 測試（空資料升級、資料完整性、不改使用者設定過的值）。
- 新表沒有舊資料，「不改使用者值」的案例以「升級後既有表（`appearance_settings` 等）的使用者值不變」代表。
- 外鍵：`queue_entries`、`play_history` 的 `RESTRICT` 有 cascade 反例測試。刪一個仍被參照的 `tracks` 列會失敗；孤兒清理只刪沒人參照的列。

### 3.6 M5 匯入的對應（§5.21）

M2 的格式都能從舊資料推出，不必為匯入預留欄位：

| 舊 | 新 |
|---|---|
| `PlayQueue.trackIds`（指 `Track.id`） | 先寫 `tracks`，再依序寫 `queue_entries`；`currentIndex` → `current_position` |
| `PlayQueue.isShuffleEnabled`（排列不持久化，`playback.md` §3.1） | `shuffle_enabled`；`shuffle_rank` 由匯入時重新產生（等同舊版重啟時的行為） |
| `PlayQueue.loopMode`、`lastPositionMs`、`lastVolume` | `loop_mode`、`position_ms`、`volume`（`muted` 為假） |
| `PlayHistory`（快照） | upsert `tracks` 後寫 `play_history`，`played_at` 照搬 |
| `Settings` 的播放欄位 | §3.3 的對照欄 |

## 4. 媒體 client 與快取庫

### 4.1 媒體 client（決定 1、ADR 0012 §決定 1）

`lib/core/network/media_http_client.dart`：`MediaHttpClientFactory.create(pluginId, allowedHosts)`，每插件一個，與 `SourceHttpClient` 一起在插件載入時以 manifest 建立（`lib/plugins/plugin_registry.dart`）。

| 規則 | 內容 | 來源 |
|---|---|---|
| 不帶憑證 | 不掛認證、cookie 攔截器；標頭只經 `mediaRequestHeaders`（`Referer`、`User-Agent`、`Origin`、`Range`） | ADR 0012 §決定 1、`media_headers.dart` |
| 每跳檢查 | `followRedirects: false`，每跳以同一份 `AllowedHosts` 檢查、只准 `https`、最多 5 跳；每跳只帶媒體標頭 | ADR 0012 §決定 1；與 `SourceHttpClient` 同一份規則（`app/AGENTS.md:296-300`） |
| 大小上限 | 呼叫端給 `maxBytes`；封面 10 MiB。先看 `Content-Length`，再邊收邊數，超過就中止、刪掉暫存檔，丟 `Unsupported` | M1 follow-up 7 |
| 逾時 | 連線 10 秒、兩次收到資料之間 15 秒、整個請求 30 秒 | OkHttp 的連線與讀取預設 10 秒；圖片放寬讀取間隔給慢的 CDN |
| 錯誤 | 傳輸錯誤 `NetworkError`；429 與帶 `Retry-After` 的 503 是 `RateLimited`；404、410 是 `NotFound`；其他狀態碼 `UnexpectedError`（狀態碼進 log） | ADR 0013 §決定 2 |
| 不重試 | 封面下一次顯示時自然再抓；M6 下載需要時自己決定 | 「最簡方案」 |
| 網路紀錄 | 每跳一筆，tag `network`，欄位同 `SourceHttpClient`，加一個 `client` 欄位（`source`／`media`）；兩種 client 都寫 | ADR 0011 §決定 4。加欄位是 log 檔格式的擴充，`network log` 群組一起改 |
| 網路狀態 | 結果回報給 §5 的狀態機 | ADR 0016 §決定 6 |

M1 留下的「封面轉址不經 `allowedHosts`、沒有大小上限與逾時」（`app/AGENTS.md:532-534`）在 PR 4 換掉 `Image.network` 時一併解決。

### 4.2 `cache.db` 與快取模組（ADR 0016 §決定 2，§5.11）

- **位置**：
  - 平台快取目錄（`getApplicationCacheDirectory()`）下的 `fmp_cache/`，裡面有 `cache.db` 與 `files/`。
  - Windows 的快取目錄是 `%LOCALAPPDATA%\<公司>\<ProductName>`（`path_provider_windows` 2.3.0 的 `getApplicationCachePath`），dev 與 prod 的 ProductName 不同，自然分開（`app/AGENTS.md:119-120`）。
  - 多一層 `fmp_cache/` 是為了不和同目錄的其他東西混在一起（舊版 prod 的 ProductName 相同）。
- **平台層**：`lib/platform/cache_directory/` 解析路徑（`path_provider` 只准在平台層）。`main()` 注入，只有 `lib/data/cache/`（與組裝點）能 import（§2 的 `restrictedImports`）。快取上限預設與 `ImageCache` 大小另放 `lib/platform/cache_sizes/`（`PlatformCapabilities.cache`），因為設定頁與 `main()` 也要讀（PR 4）。
- **索引**：
  - `cache_entries`：`id` 自增主鍵（`flutter_cache_manager` 的 `CacheObject.id` 是 int）、`key` text、`category` text（M2 只有 `image`）、`plugin_id` text?、`relative_path`、`size_bytes`、`last_access`、`valid_until`、`etag`?；
  - 唯一限制是（`category`、`plugin_id`、`key`）：兩個插件給同一個網址時各存一份，各自經自己的 `allowedHosts` 下載，`removePlugin` 只刪自己的（PR 4；原先寫 `key` 唯一，第二個插件寫入會撞限制）。
  - 索引建在 `last_access`、`plugin_id`。
- **與主資料庫不同的規則**：快取可以隨時丟（ADR 0016 §決定 1）。
  - **開不起來**（檔案損壞）：清空 `fmp_cache/` 裡面重開一次，不顯示錯誤頁；第二次也失敗時封面只顯示佔位圖，App 照常。快取庫由 `cacheStoreProvider` 第一次被讀時開啟，不拖慢啟動（PR 4）。主資料庫則是停在錯誤頁（ADR 0010 §決定 3）。
  - **schema 版本**：仍以 `drift_dev` 存快照到 `drift_schemas/cache_database/`，並有自己的 `schema_test`，守「改了表卻沒加版本」。
  - **升級與降級**：版本不同就刪表重建，不寫逐步 migration（revert 後的降級走同一條路）。升級測試只斷言「舊版本開啟後是空的、可以寫入」。
  - `build.yaml` 的 `databases:` 加第二個資料庫。

### 4.3 封面接到快取庫（ADR 0016 §決定 4，決定 1）

ADR 0016 §決定 4 的主路線「`cached_network_image` 的自訂 cache manager 接到快取庫」可行，不走 fallback。依據：

- `cached_network_image` 4.x 的 widget 收 `cacheManager: BaseCacheManager?`，依賴 `flutter_cache_manager` ^3.4.1（4.0.0 的 pubspec 與 `cached_image_widget.dart`；4.0.4 是最新版，digest §3）。
- `flutter_cache_manager` 的 `CacheManager(Config(key, repo:, fileSystem:, fileService:))` 三個都是可替換的介面（context7 `/baseflow/flutter_cache_manager` 的「Customize」）。
  - `CacheInfoRepository` 有 `get`、`insert`、`update`、`delete`、`getObjectsOverCapacity`、`getOldObjects` 等；
  - `FileSystem` 只有 `createFile`；
  - `FileService.get` 回傳 `FileServiceResponse`（內容 stream、長度、`validTill`、`eTag`、副檔名）。
- 它的 `CacheStore` 每次取檔先檢查檔案存在，不在就刪索引並當未命中（3.4.2 `cache_store.dart` 的 `retrieveCacheData`）。所以統一淘汰器從背後刪檔不會讓它回傳不存在的檔案。

做法：

- `lib/data/cache/image_cache_manager.dart` 的 `FmpImageCacheManager` 以三個轉接實作組成。
  - `repo` 讀寫 `cache_entries`（`category = image`、`plugin_id` 固定）；
  - `fileSystem` 指到 `fmp_cache/files/`；
  - `fileService` 用該插件的 `MediaHttpClient`。
  - `getObjectsOverCapacity`、`getOldObjects` 回空清單：淘汰只由快取庫依位元組做（§4.4），不讓兩套規則並存。
- **每插件一個實例**：`artworkCacheManagerProvider(pluginId)` 在 `lib/plugins/plugin_artwork.dart` 組合快取庫與該插件的媒體 client。
  - 每跳檢查要用那個插件的 `allowedHosts`；
  - 索引也要記所屬插件。
  - 放在插件層，是因為 `allowedHosts` 由插件層持有；UI 與播放層都從這裡拿。
- `ArtworkImage`（`lib/ui/artwork/artwork_image.dart`）改用 `CachedNetworkImage`。
  - 多收一個 `pluginId`；
  - 解碼尺寸照舊以高（`memCacheHeight`）；
  - `pickArtwork` 不動。
- 系統媒體控制的封面先經同一個 cache manager 取得本機檔，再交給平台（§8.2）。

### 4.4 上限、淘汰、清除、移除插件（ADR 0016 §決定 2–3，§5.12）

- **寫入時淘汰**：每次寫入後，總量超過上限就依 `last_access` 由舊到新刪到上限以下，不分類別。改上限時也跑一次。不用計時器（ADR 0017 §決定 1「快取淘汰：寫入時觸發」）。
- **設定頁「網路」組**：快取上限、各類別用量（M2 只有「封面」）、「清除快取」。清除會一併清 Flutter 的 `ImageCache`（`imageCache.clear()` 與 `clearLiveImages()`）。
- **移除插件**：快取庫提供 `removePlugin(pluginId)`，在快取庫層測。
  - 事件來源是插件頁的「移除」，在 M3（`app/lib/plugins/install/` 目前沒有移除路徑）；
  - M3 接上時只呼叫這一個方法。
- **記憶體 `ImageCache`**：大小由平台層宣告，`main()` 在 `runApp` 前套用（ADR 0016 §決定 4）。
  - Android 100 張／50 MB、Windows 200 張／80 MB，沿用舊版 `lib/main.dart:156-164` 的數字與理由；
  - 快取上限的預設也由平台層宣告：Android 128 MB、Windows 256 MB（ADR 0016 §決定 3）。

## 5. 網路狀態與離線

### 5.1 分工（ADR 0016 §決定 6、ADR 0009 §決定 6）

- **平台層** `lib/platform/connectivity/`：介面 `NetworkInterfaces`，只回答「有沒有網路介面」與它的變化，Android、Windows 以 `connectivity_plus` 實作。
  - 宣告欄位 `PlatformCapabilities.networkInterfaces`。
  - 它的 README 寫明「有介面不代表能上網」，所以它只負責 `NoInterface`。
- **網路層** `lib/core/network/network_status.dart`：`NetworkStatus`（`online`、`noInterface`、`unreachable`）與狀態機。
  - 輸入是介面變化，以及兩種 client 每次請求的結果；
  - 以 provider 對外。
- **生命週期**：`appLifecycleProvider`（`AppLifecycleState`）放在 `lib/app/`。
  - 回到 `resumed` 時重新查一次介面：`connectivity_plus` README 寫明 Android 8 起背景收不到變化通知，應在恢復時再查。
  - 這是事件觸發，不是輪詢。

### 5.2 轉換規則

| 從 | 事件 | 到 |
|---|---|---|
| 任何 | 系統回報沒有介面 | `noInterface` |
| `noInterface` | 介面出現，或任何請求拿到 HTTP 回應 | `online` |
| `online` | 30 秒內第 3 次 `NetworkError`，期間沒有任何成功 | `unreachable` |
| `unreachable` | 任何請求拿到 HTTP 回應（不論狀態碼），或介面變化 | `online` |

- 時間以 `clock` 取，用時間戳判斷 30 秒，不開計時器。
- 閘門：單元測試在 `fakeAsync` 裡跑完所有轉換後斷言沒有待執行的計時器（ADR 0016 §如何確認「沒有計時器輪詢」）。
- 只有我們自己的 HTTP client 回報。播放後端的串流中斷不是「請求」，不算。
- `noInterface` 遇到回應就離開（Windows 的 NCSI 在 proxy、VPN 後面會誤報，ADR 0016 §決定 7 的更正），遇到失敗不變（介面消失前送出的請求晚一點才失敗）。

### 5.3 離線時的播放：ADR 0016 §決定 7 與 ADR 0018 §決定 7 的先後（§5.16）

兩條各管一件事：ADR 0016 管「離線時哪些曲目能播」（本機檔才能播），ADR 0018 管「目前這首失敗了怎麼辦」。合起來的規則：

1. 狀態不是 `online`，而目前這首沒有本機檔：
   - 佇列裡之後還有本機檔：跳過去，這次離線期間只提示一次（ADR 0016）。M6 才有本機檔，M2 不寫這個分支。
   - 沒有：停在這首等網路（`RecoveryPolicy` 的 `WaitForNetwork`）。
     - 狀態是 `Retrying`，`delay` 為空，畫面顯示「等待網路連線」；
     - 不計入 1／3／9 秒的重試次數，也不算一次跳過（ADR 0018「不在 Online 時暫停計數」）。
     - 回到 `online` 時立刻從原位置重試。
2. 狀態是 `online` 而解析或串流以 `NetworkError` 失敗：照 ADR 0018 重試 1／3／9 秒，仍失敗才跳過。
3. 等網路的期間不跳任何提示：全域離線提示已經在畫面上，ADR 0016 也要求離線期間背景的 `NetworkError` 不跳 toast。

- **與 ADR 0016「整個佇列不能播就停止」的關係**：「停止」解讀為「不再往下跳」，停在目前這首等網路，而不是進 `Failed`。
  - 理由：舊版網路恢復時會自動重試並歸零（`playback.md` §3.6）；ADR 0018 的「暫停計數」也表示要等。
  - 進 `Failed` 的話，使用者在網路恢復後還得自己按播放。
  - 這是解讀，列入 §12 確認。

### 5.4 M2 各頁的離線狀態（§5.8）

| 畫面 | 離線時 |
|---|---|
| 外殼 | 內容區頂端一條全域離線提示（`noInterface`／`unreachable` 兩種文字），不用 toast |
| 搜尋 | `noInterface`、`unreachable` 都照常送出使用者按下的搜尋；失敗時顯示共用的離線空狀態元件與「重試」，已有的結果照常顯示 |
| 歷史、設定 | 完整可用（本機資料）；封面讀不到時顯示佔位圖 |
| 播放列、播放頁 | 依 §5.3 顯示「等待網路連線」 |

- **搜尋在離線時仍送出**：ADR 0016 §決定 6「使用者操作照常發請求」與 §決定 7 的更正（2026-10-01，擁有者決定）。
  - 兩種離線狀態都要靠請求拿到回應才回得到 `online`（§5.2）；擋掉使用者操作，誤報的 `noInterface` 永遠回不來。
  - 「離線中不發背景請求」不變；M2 沒有背景請求。
- widget 測試（ADR 0016 §如何確認）涵蓋 M2 存在的四個畫面。其餘頁面（音樂庫、下載、歌詞、插件、登入）跟著各自的里程碑。

## 6. 啟動維護清單（決定 2，ADR 0017 §決定 1，§5.10、§5.25）

- **位置**：`lib/app/startup_maintenance.dart`。
  - 清單的項目分屬各層（log 在 `core/`、孤兒曲目在 `data/`），由 App 的組裝層收集；
  - ADR 0017 說的「service 層」在 `app/` 沒有對應目錄，不為它新開。
- **形狀**：`StartupMaintenanceTask { String id; Future<void> Function() run; }` 的有序清單，每個項目在加入它的 PR 登記。
- **何時**：第一幀畫完之後依序跑一次（`FmpApp` 的 `initState` 以 `SchedulerBinding.addPostFrameCallback` 排一次），每個行程只跑一次。
  - 「第一個畫面後」取第一幀之後，而不是 `runApp` 之後：維護不能拖慢第一個畫面。
- **失敗**：每項各自 try。
  - 失敗以 `log.report` 寫進錯誤歷史，接著跑下一項；
  - 不重試、不跳提示（ADR 0013 §決定 5「背景工作不跳 toast」）；
  - 下次啟動自然再跑。
- **M2 的項目**：
  1. **log 保留 7 天**（ADR 0025 §決定 3）：`logs/` 底下最後修改超過 7 天的 `fmp*.jsonl` 刪掉。
     - 目前在寫的 `fmp.jsonl` 剛寫過 `App started`，不會被刪；
     - 大小輪替照舊，兩個限制先到先刪；
     - 不做設定項。
  2. **孤兒曲目**（ADR 0019 §決定 1，因 §3.1 提前）：刪掉沒有被 `queue_entries`、`play_history` 參照的 `tracks` 列。
- 診斷包暫存（M3）、更新檔（M9）各自在它們的里程碑登記。M2 不放空的登記點。

## 7. 播放核心

### 7.1 拆出 `PlaybackSession` 與 `PlaybackEventRouter`（ADR 0018 §決定 1，M1 follow-up 8）

- M1 的路由與後端呼叫都在 `PlaybackController`（700 行）。PR 1 先拆，行為不變，之後的功能才有地方放。
- **`PlaybackSession`**：唯一持有 `AudioBackend` 的協作者。
  - 負責開流、前瞻、代際與來源 id 的過濾；
  - 把後端事件轉成帶「這是哪一代」的事件交給控制器。
- **`PlaybackEventRouter`**：純函數，(後端事件, 控制器目前的快照) → 動作（往下一首、交給 `RecoveryPolicy`、忽略）。單元測試直接餵事件。
- **控制器**：仍是唯一入口與 `PlaybackState` 唯一的寫入者。
- 兩條匯入規則（§2）在同一個 PR 進 lint。現有的控制器測試不改期望，證明拆分不改行為。

### 7.2 `QueueModel`（ADR 0018 §決定 4、5，§5.14、§5.15）

純 Dart，不碰資料庫與後端。`QueueState` 的每個項目是 `QueueEntry(TrackInfo)`，UI 直接讀顯示資料。M1 的 `queueTracksProvider` 刪掉（`app/AGENTS.md:443-446`）。

| 項目 | 規則 | 依據 |
|---|---|---|
| 模式 | 只有 `queue` 與 `temporary` | `mix`、`live` 在 M3；`detached` 不做，見下 |
| 循環 | `off`／`all`／`one`，依序輪轉 | 舊版 `cycleLoopMode`（`playback.md` §3.1） |
| 隨機開啟 | 產生位置的排列，目前位置排第一 | 舊版 `queue_manager.dart:753-767` |
| 隨機關閉 | 從目前位置依序往下 | 舊版 |
| 拖曳 | 只移動歌、不動位置的排列；拖進本輪已播的位置，本輪不再播 | ADR 0018 §決定 5 |
| 下一首播放 | 新位置的排序在目前之後；連續加入依加入順序；其他未播位置的相對順序不變 | ADR 0018 §決定 5 |
| 加入佇列（附加） | 位置加在最後；隨機開啟時，排序插在剩下未播的隨機一處，其他未播的相對順序不變 | 舊版 `_addToShuffleOrder` 的「之後的隨機位置」；只有「下一首播放」被 ADR 改掉 |
| 跳到某首（佇列中點選） | 隨機開啟時，那個位置的排序移到目前之後再往下；其他未播的不變 | ADR 0018 §決定 5「其餘未播位置不變」 |
| 一輪結束 | 循環 `all`：隨機開啟時產生新的排列；`off`：停在 `Idle` | Spotify 等以「輪」重排 |
| 上一首 | 播放超過 3 秒回到開頭，否則往前一個（依排列） | 舊版 `previousTrackThresholdSeconds = 3`；M1 只有「第一首回開頭」 |
| 上限 | 任何加入會超過 10,000 首就整批不加，控制器發 `QueueFull` 事件（§7.9） | ADR 0018 §決定 4；整批拒絕比部分加入好預期（M4 的歌單「全部」沿用） |
| 移除、清空 | 移除目前這首時往下一首；清空即停止並回到 `Idle` | 舊版 |

**臨時播放**（D1，ADR 0018 §決定 4「保留最早快照並回到佇列」；舊版 `playback.md` §3.10）：

- **進入**：還不是臨時播放時，記下快照（佇列目前位置、播放位置、是否在播）；已經是臨時播放時只換曲目、快照不變。臨時曲目不放進佇列。
- **回到佇列**：臨時曲目播完、按下一首或上一首、被跳過（ADR 0018 §決定 7）時觸發。
  - 載入快照的那一首；
  - 「記住播放位置」開著時，從快照位置倒退「臨時播放回佇列倒退秒數」，否則從頭；
  - 原本在播才自動播。
  - 佇列原本是空的時停在 `Idle`。
- **單曲循環**：循環的是臨時曲目，模式維持 `temporary`。舊版這裡會丟掉回佇列的點（`playback.md` §3.10 的觀察），兩個旗標合成一個模式後不會再發生。
- **其他操作**：在佇列中點選某首，結束臨時播放並丟掉快照；「下一首播放」插在快照位置之後。

**`detached` 不做**（§5.14）：

- `grep` 全部 ADR 只有 ADR 0018 §決定 4 一個詞。
- 對應的舊版狀態是「脫離佇列」（`_isPlayingOutOfQueue`，`playback.md` §1.2、§3.5），而它只在臨時播放時出現。
- 舊版兩個旗標並存正是上面那個 bug 的來源。
- ADR 0018 加一行更正（§11），列入 §12。

**`mix`、`live` 不在 M2**：

- 它們的插件能力在 M3；`QueueModel` 的 Mix 修剪雖是純邏輯，但沒有呼叫端。
- 依「不為想像中的需求加抽象」與 ADR 0009 §決定 4 同樣的精神，連同測試在 M3 加。

### 7.3 佇列的使用者入口（§5.13、§5.14）

| 位置 | 點一下 | 選單（右鍵、長按、尾端「⋯」） |
|---|---|---|
| 搜尋結果 | 臨時播放（D1） | 播放、下一首播放、加入佇列 |
| 歷史 | 臨時播放 | 同上，加「從歷史移除」 |
| 佇列（播放頁分頁、手機底部面板） | 跳到這首 | 下一首播放（移到目前之後）、從佇列移除；拖曳把手重排；標題列「清空佇列」（確認框） |
| 播放列、播放頁 | — | 隨機、循環按鈕；快捷鍵 Ctrl+S、Ctrl+R |

- M1 的「點一首＝整份搜尋結果當佇列」（`search_page_test.dart` 的 `tapping a result plays the whole list from it`）改成臨時播放。那個測試改寫。
- M2 沒有「整份加入」的入口：歌單的「全部加入佇列」在 M4（D2）。
- 隨機開啟時，佇列分頁的標題列有一行說明：「隨機順序跟著位置；拖曳只換歌，不改順序」。這是 ADR 0018 §後果「隨機位置語意要在佇列頁說清楚」。

### 7.4 串流解析：網址快取、期限、音質偏好（ADR 0016 §決定 5，§5.19、§5.20）

- **記憶體網址快取**（`StreamResolver` 內）：
  - 鍵＝曲目鍵（已含 cid，即分 P）＋音質＋格式偏好；
  - LRU 64 筆；
  - 有效到 `expiresAt − 5 分鐘`，`expiresAt` 為空時解析後 5 分鐘內有效；
  - 播放失敗（開不起來、中斷、HTTP 拒絕）作廢那一筆；
  - 用途是下載時不讀不寫（M6）。
- **進行中的請求共用**：同一個鍵正在解析時，第二個呼叫拿同一個 `Future`。
  - 這解掉 M1 follow-up 4 的「前瞻解析比目前這首播完還慢時會多解析一次」；
  - 也是 ADR 0016 的「預取與播放共用這一份」。
- **期限邊界統一成 5 分鐘**（§5.19）：M1 的 `ResolvedStream.expiryMargin = 30 秒`（前瞻在過期前重新解析、交接前檢查）改用同一個 5 分鐘常數。
  - 兩個數字回答的是同一個問題：「這個網址還夠不夠撐完開流與接下來的播放」。
  - Android 只緩衝 10–20 秒（`playback.md` §3.3），30 秒的邊界會讓剛接上的那首在播到一半時過期。
  - B 站網址的期限約 2 小時，5 分鐘的代價可以忽略。
  - ADR 0016 已寫 5 分鐘，不需要更正 ADR。
- **音質與格式偏好進插件**（決定 4，§5.20）：
  - `StreamRequest` 加可選欄位 `quality`（`high`／`medium`／`low`）；
  - 格式偏好不加欄位，改由宿主把平台的 `formats`（本來就是「依偏好排序」，`lib/platform/audio/audio.dart`）依使用者的編碼順序重排後送出。
  - **由插件挑，不由宿主重排候選**：網易的音質是請求參數（`level`），一個回應只有一種音質（`playback.md` §3.2）。宿主事後重排做不到，所以偏好必須是輸入。
  - **ADR 0014 相容性**：
    - 加的是送給插件的可選欄位，不認得的插件照舊忽略；
    - DTO 的封閉檢查只針對插件回傳的物件；
    - 宿主 API 還沒發佈（ADR 0014 §後果「一經發佈就要維持相容」；fmp-plugins README 寫明重寫完成前會變）。
    - 所以 `hostApiVersion` 維持 1，`fmp-plugin.d.ts`、`sourceDtoShapes` 同步加欄位（`type_definitions_test.dart` 守）。
  - B 站插件的改動見 §10。

### 7.5 `RecoveryPolicy` 完成（ADR 0018 §決定 7，M1 follow-up 1、2、9）

`decideRecovery` 加三個輸入：網路狀態、「跳過試聽片段」、這一首已重解析過的次數。結論加三種：`WaitForNetwork`、`PlayAsPreview`、`ReResolve`。

| 情況 | 處理 |
|---|---|
| `NetworkError`、`RateLimited`、中斷、提前結束 | `online`：1／3／9 秒重試，仍失敗跳過；不是 `online`：`WaitForNetwork`（§5.3） |
| `Unavailable`、`NotFound`、需登入與驗證類、`Unsupported`、`ParseError`、`UnexpectedError` | 立即跳過並提示 |
| 插件丟 `Unavailable(previewOnly)` | 跳過（沒有可播的串流） |
| 插件回傳 `previewOnly: true` 的結果（新的可選輸出欄位，§10） | 「跳過試聽片段」開：跳過並提示；關：`PlayAsPreview`，播放並在播放列與播放頁標「試聽」（D4） |
| 開不起來、解碼失敗 | 換候選一次；再失敗跳過（`Unsupported`） |
| 開流時 HTTP 403／404／410（後端回報狀態碼，§7.6） | 作廢網址快取、重解析一次（`ReResolve`）；仍被拒就換候選一次；再不行跳過：404、410 → `NotFound`，403 → `Unavailable`（原因不明） |
| 緩衝飢餓 15 秒 | 第一次重解析；同一首第二次跳過 |
| 桌面輸出裝置失敗 | 暫停並提示，不跳過 |
| 一首正常播放 10 秒 | 重試計數歸零。以位置前進累計，不開計時器 |
| 跳過的去處 | `queue` 往下一首（D3）；`temporary` 回到佇列 |
| 連續跳過 | 達佇列長度或 10 首就停在 `Failed` 並提示一次 |

- **CDN 403 的對應**（M1 follow-up 1）：
  - M1 把所有開不起來對到 `Unsupported`，畫面上是「視為 bug」的通用訊息；
  - 403 多半是網址失效或 CDN 拒絕，先重解析是最便宜的修法（舊版也在失敗時先作廢快取，`playback.md` §3.3）。
  - 重解析後仍 403，對使用者就是「無法取得這個內容」。現有字串 `errors.unavailable` 已有這句。
  - `Unavailable.reason` 改成可空：ADR 0013 §決定 1 列的原因都對不上，ADR 0013 加一行更正（§11）。
- **緩衝飢餓 15 秒**：計時是一次性的 `Timer`，進入 `Buffering` 時開、離開時取消，不是週期計時器。

### 7.6 後端：E19、契約案例、Android 音訊中斷（決定 3，§5.4、§5.5，M1 follow-up 4）

`AudioBackend` 加的成員：

| 成員 | 內容 | 兩個引擎 |
|---|---|---|
| `setVolume(double)` | 0–1；換來源與前瞻交接後維持 | just_audio `setVolume`；media_kit `setVolume`（0–100，乘 100） |
| `setSpeed(double)` | 夾到 0.5–2.0；換來源後維持 | just_audio `setSpeed`；media_kit `setRate`（`media_kit` 1.2.6 `platform_player.dart`） |
| `OutputDevices? outputDevices` | 只有 Windows 不為空：裝置清單 stream、目前裝置、`select(device?)`（空＝系統預設） | media_kit 的 `audioDevices` stream、`setAudioDevice`、`AudioDevice.auto()` |

- **能力宣告**：`PlaybackSupport.outputDeviceSelection`（`lib/platform/audio/`），Windows 真、Android 假。
  - 組裝點的 `assert` 讓宣告與 `outputDevices` 是否為空一致；
  - UI 只看宣告決定是否顯示入口（ADR 0009 §如何確認「宣告為沒有的能力，UI 不出現入口」）。
- **偏好裝置**：
  - 存 `output_device_id`（mpv 的裝置名）與 `output_device_name`（顯示用描述）；
  - 裝置清單第一次就緒時套用一次（舊版 `audio_provider.dart:1252-1302`）；
  - 找不到那個裝置就用系統預設，不清掉偏好。
  - 播放中裝置消失：mpv 的 `ao` 錯誤 → 後端發 `OutputDeviceFailed` 事件 → 暫停並提示（ADR 0018 §決定 7）。
- **速度**：0.5、0.75、1.0、1.25、1.5、1.75、2.0（舊版 `app_constants.dart:43-51`），放在播放頁的「⋯」選單（決定 3）；不持久化，重啟回到 1.0。
- **音量**：
  - 播放列滑桿與 Ctrl+↑／↓，一次 5%（YouTube 說明中心的鍵盤快捷鍵：方向鍵調整音量 5%）；
  - 點喇叭圖示切換靜音。
- **Android 音訊中斷與拔耳機**（§5.6，舊版 `playback.md` §3.7）：
  - `AudioPlayer(handleInterruptions: false)`，`JustAudioBackend` 自己聽 `audio_session` 的事件。
  - 不用 just_audio 的內建處理，原因是 just_audio 0.10.6 的內建處理在 duck 結束時無條件把音量乘 2（`just_audio.dart` 的 `setVolume(min(1.0, volume * 2))`）。音樂用途開始 duck 時它不減半，所以結束時會把使用者音量放大一倍，破壞 E19 的音量。
  - 對應：
    - duck：後端內部把實際輸出乘 0.5，結束還原；不改使用者音量。
    - 暫停類與 unknown 類中斷：發 `Interrupted` 事件。
    - 暫停類中斷結束：發 `InterruptionEnded(resume: true)`。
    - 拔耳機（`becomingNoisy`）：發 `BecameNoisy`。
  - 由控制器決定暫停或續播：控制器是唯一寫狀態的地方，`_playWhenReady` 才不會和引擎的實際狀態分岔。
  - 這不影響 M1 的「換歌不放音訊焦點」：焦點的取得與釋放仍由 `handleAudioSessionActivation` 管。
  - `audio_session` 改為直接依賴（它本來就是 `just_audio`、`audio_service` 的傳遞依賴），擁有者 `lib/playback/backends`。
  - Windows 沒有焦點與中斷（舊版也沒有）。
- **契約測試**（`test/playback/backends/audio_backend_contract.dart`，假後端與兩個真後端同一份）新增：
  - 音量、速度在 `open` 之前設定也生效，且在換來源與前瞻交接後維持；
  - 速度夾在 0.5–2.0；
  - **前瞻開不起來**（M1 follow-up 4）：目前這首照常播完，發 `SourceEnded(目前, completed)` 而不是 `SourceAdvanced`；失敗以 `SourceFailed(前瞻的 id, open)` 回報，不算在目前這首上。
  - 開流被 HTTP 拒絕時 `SourceFailed.httpStatus` 帶狀態碼。
    - 從 ExoPlayer 的 `InvalidResponseCodeException` 與 mpv 的 `HTTP error 403` log 行取得；
    - 解析是 `backend_rules.dart` 的純函數，以錄下的兩種錯誤文字做單元測試；
    - 真後端另在實機以會回 403 的網址手動確認。
  - 輸出裝置：Windows 選 `auto` 之後仍在播；裝置失敗發 `OutputDeviceFailed`（真後端實機手動）。
- **單曲循環**（ADR 0018 §決定 4「網址有效時 seek 回 0 不重解析」）：
  - 做法是把同一份解析結果設成前瞻，引擎無縫接上，控制器收到 `SourceAdvanced` 時佇列不動、記一筆歷史；
  - 網址快過期時照 §7.4 先重新解析。
  - 不用「播完再 seek」：mpv 播到清單結尾就閒置（`media_kit` 預設沒有 `keep-open`），兩個引擎行為不同；前瞻的路徑 M1 已有兩平台的契約。
  - 效果與 ADR 相同：不重解析、每圈一筆歷史。

### 7.7 持久化與啟動恢復（ADR 0018 §決定 10，§5.2、§5.25）

- `lib/playback/queue_store.dart` 把控制器的佇列操作轉成 §3.2 的差量寫入，播放位置寫 `player_state`。
- **存檔時機**：
  - 佇列操作當下；
  - 播放中每 10 秒（`Timer.periodic`，只在 `Playing` 時開）；
  - 暫停、seek、App 進入 `hidden` 或 `paused` 時（`appLifecycleProvider`，§5.1）；
  - 音量改變時（拖曳結束）。
  - 「進背景」取 `hidden` 或 `paused`，與 ADR 0017 §決定 3 的「看不見」同一個定義。桌面縮到托盤是 `hidden`，M8 不必再改。
- **臨時播放不持久化**：
  - 臨時播放期間，`player_state` 停在快照（佇列的那一首與位置），位置存檔不覆寫它；
  - 重啟後回到佇列的那個點，等同臨時播放結束。
  - 理由：
    - ADR 0018 §決定 10 的「模式」要持久化，是為了 Mix（重啟後仍在 Mix）；
    - 臨時播放是單首、短暫的狀態，舊版也不持久化（`playback.md` §3.10）；
    - 存下來的話，還要存臨時曲目與整份快照。
  - 列入 §12。`Mix 身分` 與 `mode` 欄位在 M3 跟 Mix 一起加。
- **啟動恢復**：
  - 讀回佇列、循環、隨機排列、音量；
  - 「記住播放位置」開著時，目前這首的位置＝存下的位置 − 「重啟恢復時倒退秒數」，關著時從頭。
  - 狀態是 `Idle`，播放列顯示這首。**按播放才解析**：啟動時不送請求，離線時開 App 也不會一進來就失敗。舊版啟動時就解析並載入（`playback.md` §1.2）。
  - 恢復後的第一次播放不記歷史：開始原因是 `restore`，舊版「啟動恢復不算」（`playback.md` §3.9）。

### 7.8 播放歷史（E15，§5.1）

- **何時寫**：每次「開始一首」在第一次 `ready` 時寫一筆。「開始一首」包括：
  - 換歌、臨時播放、前瞻接上；
  - 單曲循環的每一圈（D6）。
- **不算的**：同一次開始裡的重試與換候選、啟動恢復、臨時播放結束回到佇列（舊版 `playback.md` §3.9）。
- 寫入前 upsert `tracks`（§3.1）。
- **保留**：每寫一筆就裁掉超過「播放歷史保留筆數」的最舊列（舊版每寫一筆就裁，`play_history_repository.dart:21-52`）。改小保留筆數時當下裁一次。
- **寫入失敗**不影響播放：`log.report`，不提示。舊版 fire-and-forget，但沒有記錯。

### 7.9 播放事件與提示（M1 follow-up 2，ADR 0023）

- 控制器多一個 `events` stream：
  - `TrackSkipped(error)`、`PlaybackStopped(error)`（連續跳過到上限）；
  - `QueueFull`、`OutputDeviceFailed`、`PreviewPlaying`。
- 外殼以 `ref.listen` 轉成 `Toaster` 呼叫（`app/AGENTS.md:494-502`：在 listener 裡，不在 build 裡）。
- 去重交給 `Toaster` 的 5 秒同類同音源。
- `NetworkError` 在離線時本來就不會產生跳過（§5.3），所以沒有額外的靜音規則。
- M1 的「停在 `Failed` 時提示一次」併進同一個 listener。

## 8. 系統媒體控制（ADR 0018 §決定 8，§5.6）

### 8.1 平台層能力

- **目錄**：`lib/platform/media_controls/`。
  - `media_controls.dart`：介面 `SystemMediaControls`，提供 `publish(NowPlaying)`、`commands` stream（播放、暫停、上一首、下一首、seek、停止）、`dispose`；
  - `media_controls_android.dart`、`media_controls_windows.dart`：兩個實作。
- **宣告**：`PlatformCapabilities.mediaControls`，帶 `supportsSeek`（Android 真、Windows 假）。舊版 `now_playing_publisher.dart:283-284` 的「SMTC 不支援 seek」。
- `main()` 在開好資料庫後、`runApp` 前初始化，以 provider 注入（ADR 0018 §決定 1「轉接器由平台層經 provider 注入」）。
- **初始化失敗**：記 log，宣告改為沒有。ADR 0009 §決定 2 允許實作在啟動時寫宣告。
  - App 照常啟動，舊版也是失敗時退回不接系統的 handler（`playback.md` §3.8）。

### 8.2 `NowPlayingPublisher`

- **位置**：`lib/playback/now_playing_publisher.dart`。它是 ADR 0018 §決定 1 列的播放協作者，放播放模組；平台層只做轉接。
- **輸入**：控制器的狀態、佇列、進度、播放能力。
- **輸出**：不可變的 `NowPlaying`（曲名、上傳者、時長、封面本機檔、是否在播、位置、速度、按鈕）。
- **推送規則**（Harmonoid 的慣例，ADR 0018 §決定 8）：
  - 只在值改變時推，推送依序排隊、不重疊；
  - 位置只在狀態改變與 seek 時推（`audio_service` 由系統依速度外推）；
  - Windows 的 timeline 播放中最多每 5 秒推一次。這是從進度 stream 節流，不是計時器；舊版 `audio_provider.dart:2415-2432` 也有節流。
- **按鈕依播放能力推導**：
  - 有下一首（或循環 `all`）才有「下一首」；
  - `Retrying`、`Loading` 時播放鍵是暫停；
  - `Idle` 而佇列有歌時可以播放。
- **封面**：
  - 先經 §4.3 的 cache manager 拿到本機檔（每跳檢查、大小上限、逾時都套用）；
  - Android 交 `file://` 的 `artUri`：`audio_service` 0.18.19 對 `file` scheme 直接把路徑交給平台，不再自己下載；
  - Windows 見 §8.4。
- **系統按鍵** → `commands` → 控制器（唯一入口）。

### 8.3 Android（`audio_service` 0.18.19）

- **`AndroidManifest.xml`**（context7 `/ryanheise/audio_service` 的設定文件）：
  - 加 `WAKE_LOCK`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK` 權限；
  - `com.ryanheise.audioservice.AudioService` 服務：`foregroundServiceType="mediaPlayback"`，`exported`，帶 `MediaBrowserService` intent filter；
  - `MediaButtonReceiver`。
- **不需要 `POST_NOTIFICATIONS`**：Android 官方〈Notification runtime permission〉頁寫明媒體工作階段的通知不受這項限制。
  - 前景服務本身不需要這個權限就能啟動。
  - M2 不請求、不宣告；M6 的下載通知照 ADR 0020 §決定 9 處理。
- **`MainActivity`** 改繼承 `AudioServiceActivity`（與服務共用 `FlutterEngine`），另外覆寫兩處：
  - **`provideFlutterEngine`**：`audio_service` 0.18.19 的 `AudioServicePlugin.getFlutterEngine` 以 `DartEntrypoint.createDefault()` 啟動，不帶 intent 的 `dart_entrypoint_args`。
    - 原樣使用的話，`--fmp-dev-plugin` 在 Android 會失效。這是 `verify-on-device` 與 `app/AGENTS.md:367-371` 的開發入口。
    - 覆寫成：快取裡沒有引擎時自己建，以 `executeDartEntrypoint(createDefault(), getDartEntrypointArgs())` 啟動，再放進 `FlutterEngineCache`，鍵用 `AudioServicePlugin.getFlutterEngineId()`。
    - `audio_service` 之後就拿到同一個引擎。
    - Flutter 3.47.5 的 `FlutterActivity.getDartEntrypointArgs()`、`DartExecutor.executeDartEntrypoint(entrypoint, args)` 都存在（SDK 原始碼）。
  - **`popSystemNavigator`**：見 §9.1。
- **`AudioService.init` 設定**：
  - `androidStopForegroundOnPause: true`（舊版）；
  - 通知按鈕為上一首、播放／暫停、下一首；
  - `systemActions` 含 seek，讓 Android 13 起的通知有進度條；
  - 不放快轉、倒轉鍵，不必再定一組秒數（App 內 5 秒，舊版系統 10 秒）。
  - 不傳 `cacheManager`：封面一律是 `file://`，`audio_service` 不會用它下載。
    - 代價：`AudioService.init` 仍會建出 `DefaultCacheManager`，它的預設索引（`sqflite`）在 Android 私有目錄開一個空的 `libCachedImageData` 資料庫（`flutter_cache_manager` 3.4.2 的 `CacheStore` 建構時就 `repo.open()`）。
    - 接受這個空檔：要避開就得讓平台層 import `flutter_cache_manager` 的型別，擁有者表就要改成一對多（§2）。
- **傳遞依賴**：`flutter_cache_manager` 帶進 `sqflite`（Android 有原生插件）。PR 4 以 `zipalign -c -P 16` 確認 APK 內新增的原生庫仍是 16KB 對齊（ADR 0010 §後果的同一項檢查）。
- **閘門**：
  - `test/identity/android_manifest_test.dart` 以 XML 解析斷言權限、服務與 receiver。用解析而非比對字串，改格式不會紅；
  - CI 的 `aapt2 dump permissions` 照舊看 release APK；
  - `MainActivity` 的兩個覆寫沒有自動閘門，實機驗。

### 8.4 Windows（`smtc_windows` 1.1.0）

- **建置需求**：
  - README 的 Requirements 寫「確認已裝 `rustup`」；
  - 套件內的 cargokit 沒有 `cargokit.yaml`（沒有預先編譯的二進位），所以每次建置都從原始碼編 Rust（`flutter_rust_bridge` 釘 2.11.1）。
- **能不能用**：
  - 舊專案在 `ci.yml:176-204` 的 `windows-2022` runner 以同一版建置，workflow 沒有安裝 Rust 的步驟，靠的是 runner 映像內建的 Rust；
  - Flutter 是 3.47.1，與 `app/` 的 3.47.5 同一個 minor。
  - 新 App 的 CI Windows 建置與整合測試會照樣編譯。
  - 本機開發機要有 `rustup`，寫進 `app/AGENTS.md` § 驗證。
- **seek**：不支援（宣告 `supportsSeek: false`）。
- **封面**：
  - `smtc_windows` 以 `RandomAccessStreamReference::CreateFromUri(...).unwrap()` 讀 `thumbnail`（Rust 原始碼 `smtc_internal.rs`），網址不合法時會 panic；
  - Windows 文件只保證 `http`、`https`、`ms-appx`、`ms-appdata` 這幾種 scheme。
  - PR 16b 先在實機試交快取裡的 `file:///` 路徑：可以就用它（經媒體 client）；
  - 不行就交原本的 `https` 網址。那是 Windows 自己去抓，不帶 App 的任何 header 或 cookie，網址已在 DTO 解碼時通過 `allowedHosts`。列為已知例外，寫進 `app/AGENTS.md`。
  - 交出前一律以 `Uri.tryParse` 檢查，避開 panic。
- **音訊中斷**：沒有（舊版也沒有）；裝置問題走 §7.6 的 `OutputDeviceFailed`。

## 9. 介面（ADR 0024）

### 9.1 導覽與 Android 返回鍵（決定 5、決定 7，§5.24）

- 導覽三項：搜尋｜歷史｜設定。三種導覽元件都照 M1 的 `navigation per window class`。
- **返回鍵**：
  1. **播放頁、底部面板、對話框**：都是 route，Navigator 預設就會先關最上面的。
  2. **外殼**：`PopScope(canPop: 目前是第一個分頁)`。不在第一個分頁時，`onPopInvokedWithResult` 換回第一個分頁。
  3. **在第一個分頁**：放行。Flutter 在根 route 沒得 pop 時呼叫 `SystemNavigator.pop()`。
- **為什麼要覆寫 `popSystemNavigator`**：
  - Flutter 3.47.5 的 Android 端 `PlatformPlugin.popSystemNavigator` 先問 delegate；delegate 回假，而且 `FlutterActivity` 不是 `OnBackPressedDispatcherOwner`，就 `activity.finish()`。這是 M1 follow-up 3「任何分頁都直接離開」的原因。
  - `FlutterActivity.popSystemNavigator()` 是留給子類別的掛鉤，註解寫「Hook for subclass」。
  - `MainActivity` 覆寫它：`moveTaskToBack(true)` 並回真。App 退到背景，引擎與播放都不動。
- 不加 MethodChannel，所以不需要 Pigeon（ADR 0009 §決定 5 只管新的 channel）。Dart 端不判斷平台。
- Windows 沒有返回鍵，不受影響。

### 9.2 播放列三段（ADR 0024 §決定 5）

| 內容區寬度 | 控制項 |
|---|---|
| ≥ 840 | 隨機、上一首、播放、下一首、循環、輸出裝置（只在宣告有時）、靜音鈕＋音量滑桿 |
| 600–839 | 上一首、播放、下一首、音量圖示（點開滑桿）、「⋯」（隨機、循環、輸出裝置） |
| < 600 | 播放、下一首 |

- **「內容區寬度」**：外殼裡右側面板旁、導覽以外的整塊。播放列橫跨內容與右側面板的下方，開關面板不改變播放列的分段。
- **點空白處開播放頁**：點擊區與按鈕分開（U3、U4），只有圖示的按鈕都有 tooltip（附按鍵）與語意標籤。
- **狀態文字**：`Retrying` 與等網路時，曲名下方顯示「重試中」或「等待網路連線」；試聽顯示「試聽」標籤。
- **閘門**：
  - `player_bar_test.dart` 的 `controls per width`：邊界 599／600／839／840，Android 宣告下沒有輸出裝置鈕；
  - 曲名 ≥ 160dp；
  - golden 三段。

### 9.3 播放頁 B（ADR 0024 §決定 1、3、4，§5.22、§5.23）

- **路由**：推在根 Navigator 的全螢幕頁，所以提示仍在上面（`ToastHost` 包住 Navigator）。
  - 外殼以 route observer 得知播放頁在最上層時，`toastBottomInsetProvider` 改為只有底部安全區（ADR 0023 §決定 2「全螢幕頁：貼底部安全區」）。
  - `integration_test/toast_layering_test.dart` 加播放頁的案例。
- **版面依整個視窗的 `WindowClass`**：

| 寬度 | 版面 |
|---|---|
| compact、medium | 封面與歌詞切換（點封面切換）；佇列以底部面板開啟；控制在下方 |
| expanded、large | 左右各半。左：封面（上限 420dp）、曲名、上傳者、進度、五個控制（隨機、上一首、播放、下一首、循環）、「⋯」；右：分頁「歌詞｜佇列｜詳細」 |
| extraLarge | 三欄約 1：1.15：0.9：封面與控制｜歌詞｜分頁「佇列｜詳細」 |

- **「⋯」選單**：播放速度（決定 3）、在 expanded 以上切換右側面板。
- **分頁記憶**：上次的分頁存 `layout_state.player_tab`（§3.4）。
  - extraLarge 沒有「歌詞」分頁：記住的是歌詞時顯示佇列，但不覆寫記憶，回到兩欄時仍是歌詞。
- **歌詞欄與分頁**：M2 一律顯示「沒有歌詞」的空狀態。
  - 這是沒有歌詞的曲目的真實畫面（ADR 0024 §考慮過的選項：B 站、YouTube 的曲目常沒有歌詞），M7 接上內容。
  - 保留這一欄，ADR 0024 §如何確認的三個寬度 golden 才有意義。
- **詳細分頁**：與右側面板共用 `TrackDetails` widget（決定 6）。
  - 封面、曲名、上傳者、時長、音源名稱（以 `pluginId` 查插件名稱）；
  - M3 有 `trackDetail` 時補。
- **背景與毛玻璃**：
  - 背景是模糊的封面加遮罩；
  - 右欄、佇列、控制區是約 66% 的 `surface` 色加 `BackdropFilter` 一般模糊，沒有折射。
  - `MediaQuery.highContrastOf` 為真時改成不透明。
  - Flutter 3.47.5 的 `AccessibilityFeatures` 沒有「減少透明度」：有的是 `accessibleNavigation`、`invertColors`、`disableAnimations`、`boldText`、`reduceMotion`、`highContrast`。
  - 所以 ADR 0024 §決定 1 的「減少透明度」目前偵測不到，加一行更正（§11）。
  - 數值放 `AppLayout`／`AppTokens`（`fmp_design_tokens`）。
- **閘門**（ADR 0024 §如何確認）：
  - guideline 測試：淺色、深色 × 最淺、最深的測試封面；
  - golden：1000、1400、1800 寬，只守結構；
  - 播放頁加進 `test/ui/guidelines_test.dart`。

### 9.4 右側「正在播放」面板（決定 6，ADR 0024 §決定 3）

- **出現條件**：整個視窗 ≥ 840（expanded 以上）才有，常駐在內容區右側，屬於內容的焦點區。
- **可收起**：面板標題列的按鈕與播放頁「⋯」都能切換，記在 `layout_state.panel_expanded`。預設展開，照 ADR「常駐」。
- **可拖寬**：
  - 面板與內容之間有拖曳把手（M3 規定可調寬的 pane 間隔要放 drag handle）；
  - 下限 320dp、上限視窗寬 × 0.4、預設 412dp（M3 fixed pane 的建議值），extraLarge 預設 480dp。數字取舊版 `lib/core/constants/app_layout.dart` 與它的理由；
  - 拖曳結束才寫入。
- **內容**：與播放頁「詳細」同一個 `TrackDetails`；佇列是空的時顯示空狀態。
- 把手可以用鍵盤聚焦，左右鍵調寬。

### 9.5 App 內快捷鍵全表與輸入框（ADR 0024 §決定 8，§5.17）

| 按鍵 | 動作 | 焦點在輸入框時 |
|---|---|---|
| 空白鍵 | 播放／暫停 | 讓給輸入框 |
| Ctrl+←／→ | 上一首／下一首 | 讓給輸入框 |
| Shift+←／→ | 倒轉／快轉 5 秒 | 讓給輸入框 |
| Ctrl+↑／↓ | 音量 ±5% | 讓給輸入框 |
| Ctrl+S | 隨機 | 讓給輸入框 |
| Ctrl+R | 循環 | 讓給輸入框 |
| Ctrl+L／Ctrl+Q | 播放頁右欄切到歌詞／佇列；播放頁沒開時（佇列不空）先開播放頁 | 讓給輸入框 |
| Ctrl+F | 搜尋 | 有效 |
| Ctrl+, | 設定 | 有效 |
| F6 | 換焦點區 | 有效 |
| Esc | 關閉最上層：對話框 → 底部面板 → 播放頁 | 有效 |

- **輸入框內的規則一句話**：導覽類（Esc、F6、Ctrl+F、Ctrl+,）在輸入框內也有效，其餘都讓給輸入框。
  - 前者是 M1 的先例：要能從輸入框離開（`shell_shortcuts.dart` 檔頭、`app/AGENTS.md:520-525`）；
  - 後者照 ADR 字面「焦點不在輸入框時有效」，打字時不需要切隨機或音量。
  - 不必逐鍵查 `DefaultTextEditingShortcuts` 在各平台是否用到。實作上是同一個 `TextInputAwareAction`。
- **Ctrl+L、Ctrl+Q 在 compact、medium**：Ctrl+L 切到歌詞，Ctrl+Q 開佇列的底部面板。
- **表的位置**：抽成共用的 `PlaybackShortcuts`，外殼與播放頁各包一層。
  - 播放頁是另一個 route，不在外殼 `Shortcuts` 之下；放在 Navigator 之上又會搶走對話框裡的空白鍵。
  - 對話框開著時照 M1 不作用。
- **閘門**：`app_shell_test.dart` 的 `shortcuts` 群組加新鍵與輸入框案例；播放頁另有一組。

### 9.6 焦點區與 Esc（ADR 0024 §決定 8）

- 播放頁有自己的焦點區：控制區｜右欄分頁（extraLarge 另有歌詞欄）。F6 在頁內循環，Tab 只在區內。
- 外殼的三區在播放頁之下不動，關閉播放頁後焦點回到開啟它的元件。
- Esc 由頁面的 `Shortcuts` 處理（`Navigator.maybePop`）；對話框沿用 Flutter 內建的 Esc 關閉。

### 9.7 歷史頁（決定 5、E15）

- 依時間倒序，以日為組（今天、昨天、日期）。
- 列的動作見 §7.3；標題列有「清除全部歷史」（確認框）。
- 以 drift 的分頁查詢搭配 `ListView.builder`，一萬筆不一次載入。
- 離線完整可用。
- 加進 guideline 測試。

### 9.8 設定頁

- M2 起有三組：外觀、播放、網路。expanded 以上改成 list-detail：左邊分組、右邊內容（ADR 0024 §決定 6）。PR 5 第一次有第二組時改。
- 「播放」組依 §3.3 各列隨 PR 加；「網路」組是快取（§4.4）。

## 10. `1morr/fmp-plugins` 的改動

公開 repo，擁有者自己的（全域指示「`1morr` 的 repo 直接做」），以該 repo 自己的 PR 合併；本機 clone 在與 FMP 同層的 `fmp-plugins/`。

| 何時 | 改動 | 驗證 |
|---|---|---|
| PR 8 | B 站 `resolveStream` 讀 `quality`，選 DASH 音訊的頻寬層級放最前面，其他層級依序在後當備援。高＝最高頻寬、中＝中間、低＝最低（舊版 `audio_stream_quality_fallback.dart:9-20`）；沒給時當 `high`（目前行為）。`checks.json` 的 `resolveStream` 輸入加 `"quality": "high"` 與 `expiresAtPattern` | FMP 端 `FMP_PLUGIN_DIR=… flutter test test/plugins/contract/contract_test.dart`（重播） |
| PR 8 | 重錄 `resolveStream` 的 fixture（真實連線，一個案例三個 GET，ADR 0027 §決定 2 的最少操作），讓遮蔽後的網址保留 `deadline` | 同上；人工逐檔看過沒有憑證 |

- **`expiresAtPattern`**：ADR 0016 §如何確認要求契約斷言 `expiresAt` 與 fixture 網址內的期限一致。
  - 宿主不懂各音源的參數（ADR 0014），所以由插件在自己的 `checks.json` 宣告一個正規式（一個擷取群組，單位 unix 秒），契約執行器逐一核對候選；
  - B 站是 `[?&](?:deadline=|hdnts=exp=)(\d+)`。
- **把 `deadline` 從 `_bilibiliSigned` 拿掉**：目前遮蔽會整個拿掉 `deadline`（`lib/core/redaction/redaction_lists.dart` 的 `_bilibiliSigned`），fixture 裡沒有期限，這條檢查會恆真。
  - `deadline` 是公開的時間戳，不是憑證；簽名參數 `upsig` 等照舊遮蔽，網址照樣不能用。
  - 這是改遮蔽名單，PR 8 的檢查要試著攻破。
- `previewOnly` 的輸出欄位（§7.5）B 站不需要，只在測試插件 `fmp-test` 加一個會回傳它的關鍵字。M3 的網易插件使用。

## 11. 文件更正

只加一行補充或更正，不改決定（`AGENTS.md` § Decisions）。PR 0 隨本設計一起合併，或在用到它的 PR：

| 文件 | 更正 | 何時 |
|---|---|---|
| ADR 0025 §決定 5 | 「播放控制仍只經 `AudioController`」→ ADR 0018 的 `PlaybackController`（§5.18） | PR 0 |
| ADR 0026 §決定 3 的表 | M2 的「背景排程器」改到 M3（決定 2）；媒體 client 與封面磁碟快取從 M6 提前到 M2（決定 1） | PR 0 |
| ADR 0019 §決定 1 | `tracks` 在 M2 先建（欄位見 M2 design §3.1）；孤兒定義加「播放歷史」 | PR 0（擁有者確認後） |
| ADR 0018 §決定 4 | `detached` 沒有定義，不實作；脫離佇列的情況由 `temporary` 涵蓋 | PR 0（同上） |
| ADR 0024 §決定 1 | Flutter 3.47 沒有「減少透明度」的 API，目前只依高對比改不透明 | PR 18a |
| ADR 0013 §決定 1 | `Unavailable` 的原因可為空（CDN 拒絕而原因不明） | PR 12 |
| ADR 0014 §決定 5 | `resolveStream` 輸入另含可選的音質偏好；輸出可標 `previewOnly`；宿主 API 發佈前在 v1 內擴充 | PR 8、PR 12 |
| `milestones.md` § M2、§ M3 | M2 範圍：排程器移到 M3，加入媒體 client 與封面磁碟快取、右側面板、歷史導覽項；M3 範圍加入排程器；M2 驗收的範圍調整（§12） | PR 0 |
| `app/AGENTS.md` | 「媒體 client 延到 M6」（`:321-323`）、「封面以 `Image.network`」（`:532-534`）、播放段 M1 的限制（`:397-446`）隨各 PR 改寫；§ 驗證加 Windows 建置需要 `rustup` | 各 PR |
| `lib/ui/player/queue_tracks.dart` 註解 | 「曲目的資料表在 M2 的音樂庫才有」不正確（`tracks` 原屬 M4）；這個檔在 PR 10 刪除 | PR 10 |
| `.trellis/spec/app/playback/index.md` | 「實機驗證」段改成指向 `verify-on-device` skill（M1 follow-up 6） | PR 1 |
| `.claude/skills/verify-on-device` | Android 以 `am start --esal dart_entrypoint_args` 帶參數的做法若因 `AudioServiceActivity` 改變，同步改 | PR 16a |

## 12. 需要擁有者明確確認的決定

這些改動到 ADR 層級的範圍或解讀，核准本設計時請逐條確認：

1. **`tracks` 表提前到 M2**（只有表與 repository，欄位見 §3.1），佇列與歷史以外鍵參照；孤兒清理從 M2 起進啟動維護清單；ADR 0019 加一行更正。
2. **離線而整個佇列都不能播時，停在目前這首等網路，恢復後自動續播**，不進 `Failed`（§5.3，對 ADR 0016 §決定 7「停止」的解讀）。
3. **`detached` 不實作**（ADR 0018 加一行）；**`mix`、`live` 模式與它們的測試**（Mix 修剪、開直播取消音樂請求）跟著 M3；**ADR 0016 的已下載曲目離線案例**跟著 M6。M2 驗收的「ADR 0016、0017、0018 的測試」不含這些，排程器的測試（ADR 0017）也跟著決定 2 到 M3。
4. **插件 API v1 在發佈前擴充**：`StreamRequest.quality`（可選輸入）、`StreamResult.previewOnly`（可選輸出），`hostApiVersion` 不變；fmp-plugins 的 B 站插件跟著改。
5. **遮蔽名單拿掉 B 站的 `deadline`**，讓 `expiresAt` 的契約檢查不再恆真（§10）。
6. **臨時播放不持久化**：重啟回到進入臨時播放前的佇列位置（§7.7）。
7. **播放頁分頁與右側面板的狀態存在不屬於設定組的 `layout_state`**，M4 的備份不收（§3.4）。
8. **`Unavailable` 的原因可為空**，CDN 403 重解析後仍被拒時使用（§7.5，ADR 0013 加一行）。

## 13. 回滾

- 每個 PR 獨立合併；只動 `app/`、`docs/`、`.trellis/`、`.claude/skills/verify-on-device/`，以及 PR 16b 在 CI 缺 Rust 時才需要的 `ci.yml` 步驟。舊專案與 `release.yml` 不動。
- **schema 變更**：App 還沒發版，revert 一個加表的 PR 等於回到上一版快照。
  - dev 資料庫已升級的本機，刪掉 dev 資料目錄重來（`app/AGENTS.md` § 資料目錄）。
- **`cache.db`**：本來就可以丟。
- **`AudioServiceActivity` 與 manifest**：PR 16a 單獨 revert 後回到 M1 的 `FlutterActivity`。
- **fmp-plugins 的改動**：在該 repo 單獨 revert。
  - `quality` 是可選輸入，FMP 不送時插件行為同今天；
  - FMP 先 revert 也不會壞。
