# `.trellis/spec/` 規則稽核（2026-09-26，main @ f6898e9b）

分類：**G** 有 test / lint 守住（已打開該 test / lint 核對範圍）；**P** 未設閘門，但現行程式碼有 ≥2 處遵守、沒找到反例；**W** 大致遵守，但有反例，或只有 1 例；**I** 程式碼裡找不到實例：屬於建議或通用最佳實務，或從 owner 全域偏好 / Trellis 模板搬來；**S** 與現行程式碼不符。

約定：
- 「讀 X / 看 Y」這類導覽句，目標檔存在就記 P(nav)。
- 轉述 AGENTS.md 流程政策的句子（approval、on-device、Verification 列）記 P(policy)，證據就是 AGENTS.md。
- 描述「某一處具體程式碼」的事實句，核對屬實就記 P。只有「一般規則卻只有 1 例」才記 W(1例)。
- 路徑以 repo 根為準。

---

## data/index.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 7-9 | core/data 不 import services/providers（1 個例外） | G | `test/support/layer_boundary_static_rule_test.dart` `_lowerLayers` + `_lowerLayerExceptions` | keep |
| 22 | 改 adapter → 讀 sources.md + ADR 0001 | P(nav) | 檔案存在 | keep |
| 23 | Track identity → ADR 0005 + persistence 身分節 | P(nav) | 檔案存在 | keep |
| 24 | 先讀 `kFmpSchemaVersion` dartdoc 再改 model | P(nav) | `database_migration.dart:22-33` | keep |
| 24 | 改 schema 語意要先取得同意 | P(policy) | AGENTS.md § Conventions | keep（重複 AGENTS） |
| 25 | 碰 Isar 的程式碼放 `lib/data/repositories/` | G | `isar_boundary_static_rule_test.dart`；另豁免 `database_catalog.dart`、`database_migration.dart` | 措辭補上兩個豁免 |
| 29 | 跑 AGENTS Verification 對應列 | P(policy) | AGENTS.md | keep |
| 30 | codegen 被 gitignore，改 model 後先 build_runner | P | `.gitignore` 有 `*.g.dart` | keep |
| 31 | 新 host / Timer.periodic / header 字面值 / 跨 feature import → 靜態規則變紅 | G | outbound_hosts / periodic_timer / source_http_policy / layer_boundary 四支 | keep |
| 32 | repository 以外不得出現 `isar.` | G | isar_boundary（兩個 database 檔豁免） | keep |
| 32 | SourceManager 以外不得出現具體 adapter | G | `source_ownership_static_rule_test.dart`（`_recordedDirectImports` 登記 2 處 BilibiliLiveClient） | keep |
| 32 | media request 不帶憑證 | G | `test/data/sources/source_http_policy_test.dart:24` 釘住簽章 | keep |

## data/persistence.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 3-4 | 只有 repositories 碰 Isar | G | isar_boundary；但 `database_catalog.dart`、`database_migration.dart` 也被允許 | 措辭補上兩個豁免 |
| 8-9 | `@collection` + `Id id = Isar.autoIncrement` + part；Settings `Id id = 0` | P | `account.dart:11`、`track.dart:39`、`settings.dart:214` | keep |
| 10-14 | 可變 class、`late`、cascade、不用 const/copyWith/==、手寫 `copy()` | P | 11 個 collection 都沒有 copyWith/==；`Track.copy`、`SourceSettingsEntry.copy` | keep |
| 15 | 轉換寫成 model 上的方法 | W | 有 `PlayHistory.fromTrack/toTrack`、`LiveRoom.toTrack`；反例：`backup_service.dart:425`、`download_scanner.dart:87` 就地組 `Track()` | soften（model↔model 才適用） |
| 16 | 查找 / 排序欄位加 `@Index()` | P | track.dart、play_history.dart | keep |
| 16-18 | getter index 只在 put 時重算，改輸出要 rewrite migration | P | `play_history.dart:45-47` dartdoc、`track.dart:277` | keep |
| 19-21 | `@embedded` 要換新物件，不能原地改 | P | `settings.dart:698-706 _putEntry`、`track.dart:110,192,206` | keep |
| 22-24 | 新 Settings enum 用 `int xxxIndex` + `@ignore` | P | 5 個 `*Index` 欄位（settings.dart:224-364）；`@Enumerated` 在 DownloadTask / PlayQueue | keep |
| 24-25 | source id 絕不做成 enum | P | `SourceIds` 字串；ADR 0001 | keep |
| 26-27 | 預設表是資料不是 schema | P | `settings.dart:59,76` | keep |
| 28-30 | 移除欄位先標 `@Deprecated`；lint 讓其他檔碰不到 | G | `analysis_options.yaml` 有 `deprecated_member_use_from_same_package`；`settings.dart:321-426` | keep |
| 30 | 沒人讀了就直接刪 | P | `6de4dfca` | keep |
| 31-32 | 憑證不存 Isar，存 `SecureKeyValueStore` | P | `Account` model 沒有秘密欄位；3 個 account service 加 `lyrics_ai_config_service.dart` 走 secure store | keep |
| 33-34 | 已註冊 collection 清單 = `database_catalog.dart` | P | 事實 | keep |
| 38-40 | 新增 `_collection<T>` 條目；DB 只由 `openFmpDatabase()` 開 | P | `database_catalog.dart:50-132`；`Isar.open` 只出現在 `database_provider.dart:92`（未設閘門） | keep |
| 44-45 | 照 dartdoc 程序做，不要自己推導 | P(nav) | dartdoc 存在，但只有 10 行 | keep |
| 48-50 | Isar 型別預設 ≠ 業務預設 → 加 `NamedMigrationStep` | P | dartdoc :24-28；4 個 step | keep |
| 51-52 | 與版本無關的修復每次啟動都跑 | P | `repairSettingsInvariants`、`_relinkLyricsMatchesToCidKeys` | keep |
| 53 | 移除的 step 留成 no-op | W(1例) | 只有 `_migrateV2ToV3`（database_migration.dart:229） | keep |
| 54-56 | 新 Settings 欄位要進 backup，或列入排除清單 | G | `settings_backup_coverage_static_rule_test.dart` | keep |
| 57-59 | 高風險時對 DB **副本**跑 real_db_probe | P | `test/manual/real_db_probe.dart` 存在 | keep |
| 63-65 | 具體類別收 `Isar`，沒有 interface，會 log 就 `with Logging` | P | 13 個 repo；repo 裡沒有直呼 `AppLogger` | keep（`DataIntegrityRepository(Isar isar, {…})` 也是另一種形狀） |
| 66-70 | provider 多半在 `repository_providers.dart`，例外清單 | S | 清單不完整：`BackupRepository` 沒有 provider（`backup_service.dart:44` 就地建）；`DataIntegrityRepository` 在 **UI 頁** `developer_options_page.dart:551` 就地建；`TrackRepository` / `SettingsRepository` 雖有 provider 仍被就地建（`audio_controller_provider.dart:41-42`、`stream_resolution_provider.dart:16-17`、`source_auth_context_provider.dart:11`） | fix 清單 |
| 80-82 | 方法命名 get*/save/delete/upsert/update/watch* | W | 反例：`allTracks`、`allPlaylists`、`saveTask`、`deleteTask`、`addHistory`、`clear*` | soften 成「常見動詞」 |
| 82 | 直接回傳 Isar model，不做 mapping | P | 全部 repo | keep |
| 83 | 所有寫入都在 `writeTxn` 內 | P | 抽查沒找到反例 | keep |
| 83-85 | read-modify-write 同一個 txn（`SettingsRepository.update`） | P | `settings_repository.dart:36`；所有設定 notifier 都用 `update` | keep |
| 86-87 | `…InTxn` 假設已在 txn 內；巢狀 writeTxn 會拋 | P | `4bfab27d`；4 個 InTxn 方法 | keep |
| 87-88 | InTxn 要配一個 wrapper | W | `mergeDuplicateTrackMembershipsInTxn`、`remapPlaylistTrackReferencesInTxn`、`relinkLyricsMatchToCidKeyInTxn` 都沒有 wrapper | soften |
| 89-90 | 跨 collection 的原子寫入放 repository | P | `BackupRepository.writeImport`、`DataIntegrityRepository` | keep |
| 91 | 由 repository 在 put 前設 `updatedAt` | W | service 也在設：`stream_resolution_service.dart:450`、`import_service.dart:253,361`、`backup_service.dart:446` | soften / delete |
| 91-92 | 政策數字由呼叫端傳入 | P | `addHistory(keepAtMost:)`、`trimToLimit` | keep |
| 93-94 | list 用 `watch(fireImmediately: true)`，變更通知用 `watchLazy()` | P | account_repository.dart:29、play_history_repository.dart:171 | keep |
| 98-99 | 只用 `TrackKey.format`，不手拼 `'$type:$id'` | P | 17 處使用；手拼的只出現在 log / widget key（`download_service.dart:1054`） | keep |
| 99-100 | 輸出由 track_key_test 釘住 | G | `test/data/models/track_key_test.dart`（釘的是輸出，不管用法） | keep |
| 100-101 | cid backfill 在同一個 txn relink 歌詞 | P | `track_repository.dart:160-166` | keep |
| 105 | repository 測試用真的 Isar，不用 fake | P | test/data/repositories 10 支全用 `initializeIsarForTests` | keep |
| 119 | 只開需要的 schema | P | 只有 migration test 和 probe 開完整 `fmpDatabaseSchemas` | keep |
| 119-121 | 用 FakeIsar / FakeSettingsRepository；`runDatabaseMigrationForTesting` | P | 都存在並有人用 | keep |

## data/sources.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 9 | adapter = `with Logging implements DisposableSource, <caps>` | P | NeteaseSource、YouTubeSource、BilibiliSource | keep |
| 10-13 | capability 是 `abstract interface class … implements SourceCapability` | P | `source_capabilities.dart:19-117` | keep |
| 15-17 | 刻意沒有 BaseSource | P | `base_source.dart:4-5` 註解（未設閘門） | keep |
| 18-19 | 沒人消費的 capability / method 直接刪 | P | `19f721c7`、`cde4769e`、`cd3aa568` | keep |
| 24-27 | 具體 adapter 只在 SourceManager 建 | G | source_ownership；另有 2 筆登記例外（BilibiliLiveClient 在 `radio_source.dart:71`、`bilibili_account_service.dart:84`） | 措辭補上例外 |
| 28 | 實作 `DisposableSource` 才會被 dispose | P | `source_provider.dart:91-93` | keep |
| 29-30 | UI 的音源清單來自 provider，不手寫 | P | explore / search / audio settings 頁都用 provider（非 UI 手寫：`playlist_import_service.dart:320`，不在此範圍） | keep |
| 31-33 | 依 source id 分支有逐檔預算 | G | `source_branch_points_static_rule_test.dart` `_budget` | keep |
| 40-42 | 用 `createApiDio(...)` 建 client，並接受可注入的 `Dio? dio` | G + P | 「no source client builds its own HTTP client」擋 client 建構；3 個 adapter 都能注入 | keep |
| 43-45 | 每源 header / UA / 圖片 host 放 `_bySource` 表 | P | `source_http_policy.dart:43` | keep |
| 46-47 | header 字面值只准出現在 `_headerLiteralOwners`；host 都要列 | G | source_http_policy_static_rule、outbound_hosts | keep |
| 50-53 | media bytes 不帶憑證，界線寫在簽章裡 | G | `source_http_policy_test.dart:24` | keep |
| 54-56 | 使用者或 redirect 來的 URL 走 `SourceUrlPolicy` | W | YouTubeSource 完全沒用 SourceUrlPolicy | soften / 補 |
| 56-57 | 不用子字串比對原始 URL 判斷平台 | W | `youtube_source.dart:191-194` `url.contains('youtube.com')` | 修程式或 soften |
| 61 | adapter 不讀帳號 | P | lib/data/sources 不 import account（layer rule 間接擋 services/account） | keep |
| 61-64 | 憑證逐次以 `authHeaders` 傳入；`_withAuth` 只留 Cookie | P | `source_capabilities.dart:35,42,124`、`netease_source.dart:119` | keep |
| 70-73 | 每源一個 `<Source>ApiException`；呼叫端讀 `kind` | P | 3 個 exception；lib 裡沒人讀 raw code | keep |
| 74-89 | 方法本體的 try/catch 形狀；`_checkResponse` 會 logWarning 並 throw | P | Netease / Bilibili（YouTube 另一種形狀，原文寫的是「Most」） | keep |
| 90-92 | try 裡一律 `return await` | P | 掃過 adapters + services，沒有在 try 內回傳未 await 的 future | keep（未設閘門） |
| 93-95 | 分類順序有意義（login 先於 VIP） | P | `netease_source.dart:885-935` | keep |
| 96-97 | 降音質 fallback 共用，只在 `canFallbackToLowerAudioQuality` 時跑 | P | `audio_stream_quality_fallback.dart:60,91` | keep |
| 98-99 | 回傳來源報的 expiry，不寫死 TTL | W | YouTube 寫死 `_audioUrlExpiry`（AppConstants 1h，`youtube_source.dart:51,466…`） | soften（「來源有報的時候」） |
| 103-104 | 非持久化型別：final / const / named / `X.empty()` | P | base_source.dart、`SearchResult.empty` | keep |
| 105-106 | copyWith 用 `??` + `clearX` 旗標 | P | `AudioStreamRequest.copyWith` | keep |
| 107 | JSON 手寫，不用 freezed / json_serializable | P | pubspec 沒有這兩個套件 | keep |
| 108-110 | factory 以它讀的 API response 命名；防禦式解析 | P | `LiveRoom.fromRoomInfo` 等；17 處 `as int? ?? 0` | keep |
| 111-112 | `==` / `hashCode` 少寫，只在需要識別時 | P | TrackKeyParts、TrackSourceIdentity、LiveRoom | keep |
| 113 | toString 不含 URL / 秘密 | P | 沒找到含 URL 的 toString | keep |
| 117-121 | 歌單匯入 source 走另一套，不要照搬到主 adapter | P | `playlist_import_service.dart:137`；兩個 source 都 throw `Exception(t…)` | keep |
| 125-128 | 注入 Dio 再 stub；fixture 寫在檔內，沒有 fixture 目錄 | P | youtube_source_test / netease_source_test；test 下沒有 json fixture | keep |
| 129-130 | 用 kind 斷言錯誤 | W | `bilibili_live_client_test.dart:1011,1042` 斷言 numericCode / message；`netease_source_test.dart:167,239` 斷言 message | soften |
| 131-133 | 用預設建構子建 adapter 的測試要標 live；新 adapter 加進 `_guardedClasses` | G | `live_source_tag_static_rule_test.dart` | keep |

## services/audio.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 3-4 | 先讀 ADR 0003 | P(nav) | 存在 | keep |
| 10 | UI 的唯一播放入口是 AudioController | P | lib/ui 沒有 `FmpAudioService` / `audioServiceProvider`（未設閘門） | keep |
| 10 | 控制器本身不宣告 provider；兩個檔案刻意互相 import | P | 事實 | keep |
| 10 | 四個 audio provider 放在自己的類別旁 | W | 未列出：`lyricsAutoMatchCoordinatorProvider` 在 `playback_side_effects.dart:215`（不在它的類別旁）；`fmpAudioHandlerProvider`、`windowsSmtcHandlerProvider` 在 `now_playing_publisher.dart` | 補清單或改寫 |
| 11 | 後端差異寫在各成員的 dartdoc | P | `audio_service.dart:11-12` | keep |
| 12-19 | 表格裡的職責描述 | P | 各檔 dartdoc 相符 | keep |
| 21-22 | 協作者不碰 PlayerState；保持「刻意不擁有」段落為真 | P | mix_session_coordinator:43、queue_commands:40、playback_handoff_gate:64、playback_error_presenter:25 | keep |
| 23 | PlayerState 與 QueueState 沒有共用欄位 | G | `audio_seam_static_rule_test.dart:32` | keep |
| 24 | 佇列寫入一律走 `_emitQueueState` | P | 原文已註明未設閘門；`audio_provider.dart:165` 是唯一寫入點 | keep |
| 26-27 | 電台是例外 | P | RadioController | keep |
| 31-33 | 新增 `PlaybackAction` 變體 + router test；applier 不加 `if` | P | `audio_provider.dart:2793-2798` dartdoc + 窮舉 switch | keep |
| 33-35 | 只有 router 可以對 `PlaybackEndReason` 做 pattern match | G | `playback_event_routing_static_rule_test.dart` | keep |
| 35-36 | context 不帶協作者；時間取 `context.now` | P | router 沒呼叫 `DateTime.now()` | keep |
| 37-38 | 原生錯誤轉譯放在後端的共用 rule 檔 | G | `audio_backend_shared_rules_static_rule_test.dart`「no second keyword table」 | keep |
| 39-41 | 每首開播時要做的事 → `PlaybackSideEffect` | P | 3 個 side effect 已註冊 | keep |
| 42-43 | 佇列 → QueueCommands；Mix → MixSessionCoordinator；暫時播放 → TemporaryPlayHandler | P | 檔案存在並有人用 | keep |
| 44-46 | audio_provider 行數雙向 ratchet；調高上限要在 commit body 說明 | G + P | `audio_provider_size_static_rule_test.dart`；body 說明是寫在 test dartdoc 的慣例 | keep |
| 50-54 | 可收斂的決策放共用純函式 rule 檔；複製就會紅 | G | shared rules test 的 `_sharedUnits` / `_delegation` | keep |
| 55-56 | 收斂不了的差異寫進 FmpAudioService 成員 dartdoc | P | audio_service.dart | keep |
| 57-58 | 跨後端的新行為兩邊都寫，或抽成 rule 檔 | P | 與上兩列同一套機制 | keep |
| 59-60 | `platformPlayer:` 是桌面後端的 seam；JustAudio 沒有 | P | `media_kit_audio_service.dart:39` | keep |
| 61-63 | mpv 的 error 與 log 兩條 stream 都訂閱；輸出裝置失敗不怪歌曲 | P | media_kit:378,393；`audio_controller_output_device_failure_test.dart` | keep |
| 64-65 | Android 專屬行為只放在 `JustAudioService.initialize()` | P | just_audio_service.dart:166-210 | keep |
| 69-70 | 每個 await 之後檢查 `isSuperseded` | P | playback_request_session 裡 25 處 | keep |
| 70-71 | 導航與 Mix 有各自的 counter | P | `_navRequestId`、`_mixStartRequestId` | keep |
| 71-72 | 加 counter 之前先看現有的能不能排序 | I | 建議，沒有可指認的實例 | keep 當建議，或刪 |
| 72-74 | 開啟中暫停、暫停時斷流是刻意的 | P | `eef6f1bb`、`349e20d0` | keep |
| 78-81 | 用 `buildTestAudioController` + FakeAudioService | P | harness 存在，廣泛使用 | keep |
| 82 | `testNowPlayingPublisher()` | P | 存在 | keep |
| 83 | budget 設短、注入 `timerFactory:`，不真的等 | W | `audio_controller_handoff_and_errors_test.dart:1245` 真等 2200ms；`audio_controller_output_device_failure_test.dart:184` 1400ms；`queue_manager_test.dart:103` 11s | soften，或修測試 |
| 84 | 用 pumpUntil / drainEventQueue / CountWaiters 等待 | P | 見 testing | keep |

## services/download-and-auth.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 3 | 詞彙 CONTEXT.md；路徑 ADR 0004 | P(nav) | 存在 | keep |
| 7-10 | isolate 同時接 `onError` 與 `onExit` | P | `download_service.dart:831-832`；`3a413e56` | keep |
| 11-13 | `_IsolateMessage`；錯誤以 JSON 傳回再轉回型別 | P | download_service.dart:1780+ | keep |
| 14-16 | 每個 await 後重查 `_shouldAbortBeforeRegistration` | P | 6 處 | keep |
| 17-19 | 手動跟隨 redirect（≤5），每跳 `prepareDownloadHop`，拒絕非 http 與 public→private | P | download_service.dart:1832-1885 | keep |
| 20-22 | Range 續傳；收到 200 從頭開始；用 `File.open` 不用 `openWrite` | P | :1904-1915 | keep |
| 23-25 | 進度在記憶體批次處理，不逐 tick 寫 Isar | P | `_pendingProgressUpdates` | keep |
| 26-27 | 存下的失敗原因是翻譯過的句子 | P | :1384 `userMessageFor` | keep |
| 28 | 只刪確定是 FMP 的檔案 | P | `4cdf64d0` | keep |
| 29-30 | isolate 逾時的理由寫在註解 | P | :1924-1928 | keep |
| 34-35 | media byte request 只帶 `mediaHeaders` + Range | G | `media_handoff.dart:55`；簽章由 source_http_policy_test 釘住 | keep |
| 36 | `streamResolutionAuth` 會傳下去但刻意不用 | P | media_handoff.dart:16-21 | keep |
| 38-39 | 沒改 CONTEXT 並取得同意前不加憑證 | P(policy) | AGENTS / CONTEXT | keep |
| 43-45 | 憑證是 JSON DTO，放 secure storage；secureStorage 可注入 | P | 3 個 account service 都是 | keep |
| 46-48 | store 不可用 → 固定訊息、降級成未登入、不設 loaded；JSON 壞掉 → 丟棄 | P | bilibili_account_service.dart:551-575（另兩個同） | keep |
| 49 | 不 log 原始憑證 / cookie / 帶 token 的例外 | G | `account_credentials_redaction_test.dart`（sentinel 行為測試，只涵蓋帳號流程） | keep |
| 50-51 | logout 刪列；markSessionExpired 留列 | P | 3 個 service | keep |
| 52-54 | interceptor 只呼叫 `markSessionExpired()`；提示來自 watcher | P | 3 個 interceptor；`app.dart:128` | keep |
| 55-58 | Auth For Play 規則；search 不帶；沒有帳號服務的源拿 null | P | `source_auth_context.dart:133-188` | keep |
| 59 | 這裡的 API client 也用 `createApiDio` | G | source_http_policy「client」規則掃整個 lib | keep |
| 63-65 | 新增憑證路徑時擴充 redaction test | P | test 存在（流程性要求） | keep |
| 66-70 | 優先用 Memory / Unavailable store 或 `mockSecureStorageChannel`，少用 `setMockInitialValues`；「一些舊 provider 測試還在用」 | W | 不只 provider 測試在用：`account_credentials_redaction_test.dart:35`、`netease_account_service_test`、`youtube_account_service_test`、`backup_service_test`、`lyrics_source_settings_page_test` | fix 措辭 |
| 70 | 同一個檔案不要兩種混用 | P | 沒有混用的檔案 | keep |
| 71-72 | 下載 bytes 用 loopback HttpServer | P | 2 支測試 | keep |

## services/index.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 7-8 | 照 CONTEXT.md 的定義使用術語 | P(nav) | CONTEXT.md 定義了 5 個術語 | keep |
| 22 | audio 改動 → audio.md + ADR 0003；UI 不直接碰 FmpAudioService | P(policy) | AGENTS § Boundaries | keep |
| 23 | 下載 / 路徑 → ADR 0004 | P(nav) | | keep |
| 24 | 憑證流向 → 先讀 CONTEXT；改 auth 邊界要同意 | P(policy) | AGENTS | keep |
| 25 | 新 timer / host / 跨 feature import → 準備好靜態規則條目 | G | 同 data/index:31 | keep |
| 29-30 | Verification 列；on-device | P(policy) | AGENTS | keep |
| 31 | disposable service / notifier 的每個 await 後都有檢查 | W | 13 個有 await 的 notifier 檔沒有任何 `ref.mounted`（如 `theme_provider.dart:73-75`）；`ImportService` 31 個 await、沒有 disposed flag | soften |
| 32 | 人工檢查清單：provider 擁有 dispose | W | `playlistImportServiceProvider`（`playlist_import_provider.dart:334`）沒有 onDispose | 見 service-conventions:34 |
| 32 | 人工檢查清單：新 log 不含 cookie；stream URL 走 logLabel / redactStreamUrl | P | JustAudio 由 shared rules 守；其他靠行為測試 | keep |
| 32 | 人工檢查清單：`Platform.is*` 放在哪 | P | 見 service-conventions:91-97 | keep |
| 32 | 人工檢查清單：`unawaited(...)` 會失敗的要加 `.catchError` | W | 見 service-conventions:74 | 同 |

## services/service-conventions.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 5-7 | 多數 service 是建構子注入的 plain class，由 Provider 管生命週期 | P | DownloadService、ImportService、PlaylistService、QueueManager | keep |
| 7-9 | 少數是住在 lib/services 的 Notifier | P | 還有 `QueueStateNotifier` | keep |
| 9-10 | plain service 不持有 Ref（AutoRefreshService 是例外） | P | 只有 auto_refresh_service.dart | keep |
| 11 | 用具名 `required` 參數指派給 `final _fields` | W | 位置參數：`BackupService(Isar isar, …)`（backup_service.dart:43）、`DownloadPathManager(this._settingsRepo)`、`DownloadPathSyncService(this._trackRepo, this._pathManager)` | soften |
| 12-13 | 選用協作者預設為真實作 | P | import_service:152、playlist_service:72、backup_repository:78 | keep |
| 14-18 | 取最窄的介面；只有兩個檔案能提到寬的 `SourceAuthContext` | G | `audio_seam_static_rule_test.dart:58`（只守 auth context） | keep |
| 19-20 | 音源一律透過 SourceManager capability | G | source_ownership | keep |
| 21-22 | 拿到 Isar 就立刻包成 repository；不呼叫 `isar.` | G + W | `isar.` 有閘門；「立刻」有反例：`bilibili_favorites_service.dart:237` 留著 `_isar`，每次呼叫才 `TrackRepository(_isar)` | soften「立刻」 |
| 23 | provider 位置見 riverpod.md | P(nav) | | keep |
| 27-29 | `dispose()` 冪等，用 disposed flag 提早返回 | W | 沒有 flag：`ImportService.dispose`（import_service.dart:695）、`RadioRefreshService.dispose`（:298）、`PlaylistImportService.dispose`（:1203） | soften |
| 30-31 | 關閉每個 controller / timer / subscription / isolate / Dio | P | 抽查相符 | keep |
| 32-33 | 只 dispose 自己建的 | P | `_ownsStreamResolutionService`；`AudioStreamManager.dispose` 刻意為空 | keep |
| 34-35 | 由 provider 呼叫：`ref.onDispose(service.dispose)` | W | `playlistImportServiceProvider` 沒有 onDispose（controller 會洩漏）；`audioServiceProvider` / `queueManagerProvider` 改由 AudioController 釋放（audio_provider.dart:471-476） | 修程式，或寫明例外 |
| 39-44 | 私有 broadcast controller + 公開 getter | P | download_service、import_service、queue_manager | keep |
| 46-48 | 一次性結果做成 event class；service 不發 toast | W | AudioController（services 層的 Notifier）透過 `toastServiceProvider` 發 toast（audio_provider.dart:185,1958） | 限定為「plain service」 |
| 49-50 | `Stream<void>` = 有東西變了，重讀 getter | P | QueueManager、ConnectivityNotifier、RadioRefreshService | keep |
| 51-54 | 別人會等的初始化共用同一個 in-flight future，失敗時清掉 | W(1例) | 只有 `AudioController.initialize`（:339,443） | keep |
| 55-56 | 預期中的結果回傳 typed result | P | PlaybackSessionResult、DownloadResult、RemotePlaylistEditResult | keep |
| 60-61 | 每個 await 後 `if (_isDisposed) return;` | W | ImportService 沒有 flag；RadioRefreshService 改用 generation | soften |
| 62-66 | superseded 的工作用 generation / request id 丟掉；整個替換時比 identity | P | AutoRefreshService、RadioController、LyricsAutoMatchCoordinator、`identical` in MixSessionCoordinator | keep |
| 67-69 | 同時呼叫共用一個 in-flight future / Completer | P | `_ensureRefreshed`、AudioController.initialize | keep |
| 70-71 | 交給呼叫端的 waiter 每條丟棄路徑都要 complete | P | `playback_handoff_gate.dart:31,241` | keep |
| 72-73 | 每個等待都有上限 | P | PlaybackTimeoutBudget；範圍實際上是播放路徑 | 可標明範圍 |
| 74-76 | 明寫 `unawaited(...)`，可能失敗的加 `.catchError` 並 log；lint 沒開 | W | 27 處 unawaited 只有 3 處有 catchError（如 `audio_provider.dart:2807 unawaited(_audioService.pause())`）；不寫 unawaited 的 fire-and-forget：`radio_controller.dart:855 _handleStreamEnd();`。「lint 沒開」屬實 | soften，或開 `unawaited_futures` |
| 80-82 | 要能取消的一律用 Timer，不用 Future.delayed | W | 無法取消的延遲 callback：`refresh_provider.dart:313`、`audio_provider.dart:1960`（有 generation / requestId 守著） | soften |
| 82 | Future.delayed 可注入（`delay:`） | W | 只有 PlaybackRequestSession / RecoveryCoordinator 注入；寫死：`import_service.dart:608`、`auto_refresh_service.dart:106`、`download_service.dart:1307` | soften |
| 83-85 | 每個 `Timer.periodic` / `Stream.periodic` 都列在 `_timers` | G | `periodic_timer_static_rule_test.dart` | keep |
| 85-86 | 自我重排的 Future.delayed loop 會躲過規則，改用 Timer.periodic | W | `radio_controller.dart:917,939` 是 delay 加遞迴的重連 loop（有上限） | keep 或把它列為例外 |
| 87 | 不在每秒輪詢裡 log | P | `e1bf1712`（未設閘門） | keep |
| 91-94 | 音訊程式依注入的 `AudioRuntimePlatform` 分支 | P | lib/services/audio 只有 WindowsSmtcHandler 用 `Platform.is*`（原文已註明） | keep |
| 95-97 | 其他地方用 `Platform.is*` + 提早返回；需要測試時加 seam | P | WindowsDesktopService、`StoragePermissionService.debugIsAndroidOverride` | keep |
| 102 | 依型別與 SourceErrorKind 分支，不比對訊息子字串 | W | `netease_playlist_service.dart:198-200` 比對 'playlist not exist' / '歌单不存在'；`youtube_source.dart:2371` 比對函式庫錯誤文字 | fix 或寫明例外 |
| 102-104 | 未列出的例外 → warning、不重試 | P | `PlaybackErrorPresenter.isRetryable` | keep |
| 105-108 | 基礎設施失敗時降級而不是拋 | P | credential store、QueueRepository 在 closed 時 no-op（`5f3bec68`）、`readOptional` | keep |
| 109-110 | 部分失敗要回報 | P | `searchSourcesInParallel` 的 `onSourceError` | keep |
| 111-113 | 重試階梯放在常數 / 類別 static，旁邊寫理由 | P | NetworkRetryConfig、RankingCacheService、RadioRefreshService | keep |
| 114 | 重用或擴充擁有者的階梯，不要另起一份 | I | 建議，無法驗證 | keep 當建議 |
| 119-121 | 手寫 fake；測試專屬的變化寫成檔內 `_FakeX`，不在共用 fake 上加開關 | W | 共用 fake 有開關：`FakeAudioService.playUrlSettlesReady`（fake_audio_service.dart:77，audio_controller_handoff_and_errors_test.dart:1967 在用） | soften |
| 122-123 | 時間用注入的；沒有 fake clock 套件 | W | 「沒有套件」屬實；「用注入的」：42 處 Timer 只有 2 個檔案可注入；測試真的在等（queue_manager_test 11s） | soften |
| 124-125 | 必要時在 production class 開 `@visibleForTesting` hook | P | `debugKillDownloadIsolateForTesting` 等 36 處 | keep |
| 126 | 回歸測試以 `///` 開頭，寫出 issue 與觀察到的 log | W | 26 支有 issue 編號；`queue_manager_test.dart:18`「Task 1 regression」沒有；「觀察到的 log」很少寫 | soften |
| 127 | log 斷言讀 `AppLogger.logs`，用 `clearLogs()` 重設 | P | 8 / 9 支檔案 | keep |

## shared/code-style.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 5 | lib/ 只用 `package:fmp/…` import | G | `always_use_package_imports` | keep |
| 5-6 | layer rule 的 regex 依賴這點；barrel 用 package 路徑 re-export | P | layer_boundary dartdoc；lib 裡沒有相對路徑 export | keep |
| 6-7 | 測試用相對路徑 import test/support | P | 189 處 | keep |
| 8 | 檔名 snake_case | G | lints core `file_names` | keep |
| 8-10 | 一檔一個公開概念，並以它命名 | W | `audio_provider.dart` 裝 AudioController；`source_provider.dart` 裝 SourceManager；`backup_repository.dart` 有 4 個公開 class | soften |
| 11-12 | 測試 hook：`@visibleForTesting` + `…ForTesting` / `debug…` 名稱 | W | `netease_playlist_service.dart:213 normalizeTrackIds`、`youtube_playlist_service.dart:613,650` 用普通名稱 | soften |
| 16-17 | 新寫與改到的註解用繁中；只轉換正在改的行 | P(policy) | AGENTS § Conventions | keep |
| 18 | log / 例外訊息 / 測試名稱 / 識別符用英文 | W | 36 個中文測試名稱（`download_filenames_test.dart:6`）；playlist_import 的例外是翻譯過的文字（刻意） | soften |
| 19-21 | 程式碼的理由寫在 dartdoc 或守它的測試，不寫在 markdown | P | analysis_options.yaml:41-43 的說明；各 static rule 的 dartdoc | keep |
| 20-21 | dartdoc 說明為什麼：issue、commit、量測值加日期 | P | 例：audio_provider_size dartdoc | keep |
| 21-22 | `[Identifier]` 要能解析 | G | `comment_references` | keep |
| 23 | 承重的句子用粗體 | P | 很多 dartdoc | keep |
| 24 | 音訊協作者保留「刻意不擁有」段落 | P | 同 audio.md:21 | keep |
| 25 | lib/ 不留 TODO / FIXME | P | 目前 0 處（歷史上有被清掉）；未設閘門 | keep，或加閘門 |
| 29-31 | analysis_options = flutter_lints + 5 條規則，每條旁邊都有理由 | S | `prefer_const_constructors`、`prefer_const_declarations` 沒有理由註解（analysis_options.yaml:35-36） | fix 措辭，或補註解 |
| 32-33 | 每個 `// ignore:` 上一行要寫原因 | W | lib 的 2 處都有（`5259731c`）；test 有裸 ignore：`youtube_source_test.dart:1733`、`test/manual/real_db_probe.dart:84`、`pathological_stream_servers.dart:1` | 範圍限定 lib，或修 |
| 37 | 沒人呼叫的程式碼刪掉 | P | `aa0bdd28`、`19f721c7` | keep |
| 38 | 內部重構刪舊路徑，不留相容層 | P | `c09aec10`、`19f721c7` | keep |
| 38-39 | 持久化格式例外 | P | persistence.md § Migrations | keep |
| 43 | Conventional Commits、祈使句、小寫、無句號、subject ≤72 | W | 最近 300 個 commit 有 7 個 >72（`bf0fb70a`、`416d04af`、`b9007f29`、`35c0e8f4`…）；其餘都符合 | keep（owner 偏好） |
| 44-45 | scope 依範圍 | P | audio / ui / download / sources… | keep |
| 46-49 | commit type 給使用者看；沒有 CHANGELOG；release notes 由 feat/fix/perf/deps 產生 | P | `release.yml:470-490`、`docs/build-and-release.md:257` | keep |
| 50 | body 寫為什麼與取捨 | P | 例：`5f3bec68`、`4bfab27d` | keep |
| 51 | 分支 `<type>/<kebab>` | P | merge 紀錄 | keep |
| 51-52 | 一分支一 PR，merge commit | P | merge 紀錄 | keep |
| 52 | 版本號變更自成一個 PR | P | #156 chore/bump-version-1-11-0 | keep |

## shared/errors-and-logging.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 5 | `user_message.dart` 是唯一的映射 | P | 事實 | keep |
| 7-9 | `userMessageFor` 認得的型別；其他一律「未知錯誤」 | P | user_message.dart:72 | keep |
| 10-11 | `failureMessage` 用在 notifier / service 的 `state.error` | W | AudioController 7 處 `state.copyWith(error: e.toString())`（audio_provider.dart:492,530,600,854,970,1007,1905）；`ranking_cache_service.dart:290` | fix 程式或 soften |
| 12-14 | widget 裡顯示例外只有 `ToastService.failure` 或 `ErrorDisplay(userMessageFor(e))` 兩條路 | W | 第三條路：`downloaded_page.dart:507` `ToastService.error(t…deleteFailed(error: userMessageFor(e)))`（閘門允許） | soften（template + userMessageFor 也可以） |
| 15-19 | 不把 `e.toString()` 放進 template / toast / ErrorDisplay | G | `error_presentation_static_rule_test.dart`（template 掃整個 lib，toast / ErrorDisplay 掃 lib/ui） | keep |
| 15-19 | ……也不放進 `state.error`（只靠慣例） | W | 同 10-11 的反例 | keep，但把反例修掉 |
| 21-24 | 下層拋 typed exception | W | `import_service.dart:176` 等拋帶翻譯文字的 `ImportException(t…)`；`download_service.dart:1354` 拋 `Exception('Download failed: $error')`；playlist_import（刻意） | soften |
| 24 | 裸 DioException 到了 UI 仍會分類 | P | userMessageFor 處理 DioException | keep |
| 26-29 | 全域 handler 在 main.dart；StartupFailureApp；沒有 crash reporting | P | main.dart:76,102,117,125 | keep |
| 33-36 | AppLogger + Logging mixin；沒有實例時用 PascalCase tag | P | 70 處 AppLogger.x，tag 都是 PascalCase | keep |
| 36-37 | lib 裡除了 logger.dart 不用 print / debugPrint | G + P | print 由 `avoid_print`（flutter_lints）擋；debugPrint 只出現在 logger.dart（未設閘門） | keep |
| 38-41 | 各 level 的用途；release 保留 info 以上 | P | logger.dart:68 | keep |
| 42-44 | stream resolution 的 log 用 `TrackKey.formatGroup` 識別曲目 | W | `stream_resolution_service.dart:319` 手拼 `${track.sourceType}:${track.sourceId}` | 修該行 |
| 44-45 | 計時寫成 `${elapsedMilliseconds}ms` | P | 7 處 | keep |
| 46-51 | redaction 是安全網，不是許可；新的憑證形狀要加 key 與測試 | P | logger.dart:82-110；redaction_test.dart | keep |
| 52-56 | 簽章 stream URL 要 log `logLabel` / `redactStreamUrl`，不 log debugUrl | P + G | JustAudio 由 shared rules 守；MediaKit / session / controller 由行為測試守；`playback_media.dart:12-33` | keep |
| 56-59 | 哪些測試守 log 形狀 | P | media_kit_audio_service_state_test、playback_request_session_test、audio_controller_next_medium_test | keep |
| 60-61 | 輪替 log 檔；每秒一行會把有用的擠掉 | P | LogFileSink；`e1bf1712` | keep |

## shared/index.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 14 | 每個 session 讀一次 code-style.md | I | 流程指示（Trellis 模板形狀） | keep 或刪 |
| 15 | 動到錯誤路徑 → 讀 errors-and-logging | P(nav) | | keep |
| 19 | format 與 analyze 乾淨；CI 順序 | G | `ci.yml:61-77` | keep |
| 20 | 不用 `e.toString()` 組使用者可見文字；log 不含秘密 / 簽章 URL | G + W | UI / template 有閘門；state.error 有反例（見上） | keep |
| 21 | 改到的行用繁中註解，沒動的簡中行不動 | P(policy) | AGENTS | keep |

## testing/index.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 16 | 行為變更在同一個 commit 附上釘住它的測試 | I | owner 全域偏好（「行為變更同步補測試」）；無法驗證、沒有閘門 | keep 當政策，或刪 |
| 17 | 寫 fake 前先看 test/support | P(nav) | 目錄存在 | keep |
| 18 | 連網測試標 `live` | G | live_source_tag | keep |
| 18 | probe / benchmark 不取名 `*_test.dart` | P | test/manual、`test/performance/*_benchmark.dart` | keep |
| 19 | 行為測試優先於靜態規則 | P | `20a96dc9`、`175e5d2a`、`362aee58` | keep |
| 23 | 新測試在沒有改動時會失敗（修 bug 先重現） | I | owner 全域偏好；無法驗證 | keep 當政策 |
| 24 | 不用固定 pump 次數 | W | 直接呼叫 `pumpEventQueue` 有閘門；但固定圈數的 `Future.delayed(Duration.zero)` 很普遍（`home_ranking_settings_provider_test.dart:54…`、`import_playlist_provider_cancellation_test.dart:170…`、`notifier_rebuild_test.dart:93`） | soften，或擴大閘門 |
| 25 | 新靜態規則兩個方向的變異測試都要有 | P | 多數規則都有（periodic_timer:157/183、riverpod3、source_http_policy） | keep |
| 26 | `dart format` 乾淨；analyze 涵蓋 test / tool | G | ci.yml | keep |

## testing/static-rules.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 4-6 | 用 find 列出；每支的頂端 dartdoc 是理由 | P | 25 支都有 dartdoc | keep |
| 8-9 | 能觀察到就用行為測試 | P | `20a96dc9`、`175e5d2a` | keep |
| 13-16 | 讀 lib/ 的測試：命名與位置；沒有例外清單 | G | `static_rule_placement_static_rule_test.dart` | keep |
| 20-22 | 照 outbound_hosts / periodic_timer 的寫法 | P(nav) | | keep |
| 24-25 | 頂端 dartdoc 寫理由加 issue / commit，再接 `library;` | P | 兩個範本都有；舊規則沒有（原文已承認） | keep |
| 26-28 | 先用 `stripDartComments` | P | 25 支中 22 支有（settings_backup_coverage 沒有） | keep |
| 29-32 | 例外寫成 `const` map：路徑或名稱 → 理由 | W | `layer_boundary` 的 `_knownFeatureEdges` 是 Set，33 筆只有 2 筆有理由（dartdoc 自稱是「快照」） | 寫明 snapshot 例外 |
| 33-34 | 要有 stale-exception 測試 | P | isar_boundary、settings_backup、source_ownership 明寫；其他靠集合相等 | keep |
| 35-37 | 掃描自檢 `greaterThan(N)`；路徑正規化 | P | placement、isar、outbound | keep |
| 38-39 | 比集合，不比子字串 | P | `12c487ab`；outbound_hosts 用 `equals` | keep |
| 40-45 | 雙向變異測試放在**自己的 group** | W | 被引用的兩個範本都跟規則放在同一個 group（`outbound_hosts_static_rule_test.dart:90`、`periodic_timer…:125`） | 刪掉「自己的 group」 |
| 43-44 | detector 是公開的頂層函式 | P | `upwardImportOffenders`、`fixedPumpOffenders`、`hardcodedHosts` | keep |
| 46 | 失敗的 `reason:` 要說該怎麼做 | W | `isar_boundary_static_rule_test.dart:47` 的 `expect(offenders, isEmpty)` 沒有 reason | keep，修那支 |
| 50-51 | 修程式；例外合理就在同一個 commit 加條目與理由 | P | 各規則的 reason 文字 | keep |
| 51 | 條目指的東西消失了就刪條目 | P | stale 測試 | keep |
| 51-52 | 最後一個消費者消失時，規則與它守的程式碼一起刪 | P | `d1205581`、`362aee58`、`681f58a4` | keep |

## testing/test-conventions.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 5-6 | test/ 對應 lib/ 的結構，另有 support / live / workflows / manual / performance | W | 根目錄有 `test/bilibili_source_test.dart`、`test/app_content_wrapper_test.dart`；`test/providers/*.dart` 是平的，沒有 feature 子目錄 | soften，或搬檔 |
| 7-9 | 同一個 class 可依行為拆成多個檔 | P | `audio_controller_*_test.dart`、`media_kit_audio_service_*` | keep |
| 10-12 | support 以相對路徑 import | P | 189 處 | keep |
| 13-16 | 只有 `*_test.dart` 會跑；manual / benchmark / demo 刻意取別的名字 | P | 目錄內容相符 | keep |
| 17-18 | 測試名稱與 reason 用英文的行為句 | W | 36 個中文測試名稱（`download_filenames_test.dart:6,12,18`） | soften，或改名 |
| 22-23 | 唯一的 tag 是 `live`；寫法 | P | dart_test.yaml；`sources_live_test.dart:12`、`bilibili_source_test.dart:902` | keep |
| 23-25 | 用預設建構子建真 source 的測試要帶 live | G | live_source_tag | keep |
| 29-30 | 不用 mocking 套件；手寫 fake | P | pubspec 沒有 mockito / mocktail | keep |
| 31 | 沒實作的成員要拋，不回假值 | P | FakeSourceAuthContext（noSuchMethod）、`FakeIsar extends Fake` | keep |
| 32 | fake 用公開 list 記錄呼叫 | P | `FakeAudioService.seekCalls` / `playMediaCalls` | keep |
| 33-34 | 共用 fake 只涵蓋預設情況；變化寫成檔內 fake | W | `FakeAudioService.playUrlSettlesReady` 開關 | soften |
| 35-40 | 寫之前先重用這份清單 | P(nav) | 清單上的都存在 | keep |
| 44 | 沒有 fake_async / clock 套件 | P | pubspec | keep |
| 44-47 | production class 接受時間來源；加 timer 時一起加注入點 | W | 42 處 Timer 只有 BufferStarvationWatchdog / PlaybackRecoveryCoordinator 收 factory；`QueueManager._savePositionTimer`（:821）不能注入，導致 `queue_manager_test.dart:103` 真等 11s | soften（限定新程式） |
| 51-54 | 真 Isar + 只開需要的 schema；`initializeIsarForTests` 是唯一知道 native lib 位置的地方 | P | isar_test_harness.dart | keep |
| 58-59 | Dio + 檔內 `_FakeHttpClientAdapter` 或 interceptor；沒有共用 adapter | P | 6 個檔案各有自己的 adapter | keep |
| 60 | 串流 bytes 用 loopback HttpServer | P | 2 支 | keep |
| 61-62 | platform channel 用 mock handler，teardown 時重設 | P | `app_content_wrapper_test.dart:34` 等 | keep |
| 66-67 | ProviderContainer + addTearDown；widget 測試包 TranslationProvider + ProviderScope + en | W | 60 支 widget 測試檔只有 32 支用 TranslationProvider；`search_pagination_stale_test.dart:41` 用 `tearDown` | soften |
| 69 | 用 `addTearDown(...)` 清理 | P | 多數 | keep |
| 82-83 | `pumpUntil` 的條件在進入時必須為 false | P | 只是慣例（helper 進入時條件已成立會直接 return，pump_until.dart:38-54） | keep |
| 84-85 | `drainEventQueue` 只用來斷言沒發生；先 pumpUntil 更後面的里程碑 | P | helper dartdoc | keep |
| 86 | 「發生 N 次」用 `CountWaiters.waitFor(n)` | P | count_waiters.dart | keep |
| 87-89 | 直接 `pumpEventQueue` 有閘門；tester.pump 沒有 | G | `wait_convention_static_rule_test.dart` | keep |

## ui/i18n-and-routing.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 5 | 使用者看得到的字串都是 slang key | W | `log_viewer_page.dart:209,212` 的 `'Info+'`、`'Warning+'` | keep（輕微） |
| 5-7 | 檔案配置；zh-CN 是 base locale | P | slang.yaml | keep |
| 7 | 新 key 三個語系都要加 | G | slang 產生的語系 class 是 `implements` base（strings_en.g.dart:14,82），缺 key 會讓 `flutter analyze` 失敗；三語 key 目前完全一致 | keep |
| 8-9 | namespace 與 key 用 camelCase；可巢狀 | P | 0 個不合規的 key | keep |
| 9-10 | 死 key 三個語系一起刪 | I | 沒有閘門；沒量過是否有死 key | keep 當建議 |
| 11-12 | 參數寫 `$name` | P | 49 個 `$n`、35 個 `$count`…（`audio.i18n.json:4` 有一處 `${count}`） | keep |
| 12-13 | 沒有用到複數形 | P | 事實 | keep |
| 13-14 | 不把原始例外文字傳進 template（有閘門） | G | error_presentation | keep |
| 15-16 | UI / provider / service 都用全域 `t` | P | 事實 | keep |
| 16-17 | 語言在第一幀之後才到的子樹用 `context.t` | P | responsive_scaffold.dart:162-164 | keep |
| 18-19 | 先 `setLocaleSync` 再 `state =` | P | locale_provider.dart:25-29,39-43 | keep |
| 20-21 | 用獨立的 `dart run slang`，不用 slang_build_runner | P | pubspec 註解 | keep |
| 21-23 | `slang analyze` 的輸出檔用完要刪 | P | 工具行為屬實 | keep |
| 24-25 | 三種翻譯都要寫，不要把一種複製到其他 | I | 無法驗證；建議 | keep 當建議 |
| 29-31 | RoutePaths（+ builder）+ RouteNames；每個 GoRoute 都設 path 與 name | P | 25 個 GoRoute 全都設了 | keep |
| 32-34 | tab 用 NoTransitionPage；子頁用 builder；全螢幕 player 放 shell 外 | P | router.dart:129-296 | keep |
| 35-36 | 用常數導航，不用字串字面值 | P | 沒有字面值路由（`downloaded_page.dart:297` 拼接 `RoutePaths.downloaded` + segment，沒有 builder） | keep |
| 37-38 | index ↔ path 只在 `destinations` | P | responsive_scaffold；app_shell.dart:38 | keep |
| 39-40 | 新增 route 的步驟 | P | | keep |

## ui/index.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 6 | riverpod 3 手寫，沒有 codegen / freezed / hooks | P | pubspec | keep |
| 19 | 播放控制呼叫 AudioController | P(policy) | AGENTS；lib/ui 沒有 FmpAudioService | keep |
| 20 | 搜尋頁的 chip 是唯一的來源選擇器 | P(policy) | AGENTS | keep |
| 21 | 先查共用 widget 表；重用優先 | P(nav) | | keep |
| 22 | 可見變更要 on-device 驗證 | P(policy) | AGENTS | keep |
| 26-27 | Verification；on-device 必做 | P(policy) | AGENTS | keep |
| 28 | 常觸發的靜態規則清單 | G | test/ui/static_rules 與 test/providers/static_rules 相符 | keep |
| 29 | 「未設閘門」：ref.mounted、**context.mounted**、tooltip、token | S | await 之後用 context 其實有 lint 擋：flutter_lints 6.0.0 含 `use_build_context_synchronously`；其餘三項屬實 | 把 context.mounted 移出這份清單 |

## ui/riverpod.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 7-13 | provider 種類對照表 | P | 11 個例子都核對過 | keep |
| 15-16 | 不用 StateNotifier / StateProvider / ChangeNotifierProvider / AsyncNotifier / StreamNotifier | P | 程式碼 0 處 | keep |
| 16-17 | legacy barrel 有閘門 | G | `riverpod3_static_rule_test.dart:48` | keep |
| 18-19 | loading / error 是 state class 上的欄位 | P | 多數 state class | keep |
| 20-21 | 預設 keep-alive；autoDispose 只給頁面範圍 | P | selection / lyrics search / play history | keep |
| 25 | `xxxProvider` / `XxxNotifier` / `XxxState` | P | | keep |
| 26 | 檔案放 `lib/providers/<feature>/<name>_provider.dart` | W | `download_providers.dart`、`audio_player_selectors.dart`、`library_invalidation_coordinator.dart`、`file_exists_cache.dart` | soften |
| 26-28 | 新的 feature→feature 邊要登記並附理由 | G + W | 登記有閘門（`_knownFeatureEdges` 快照）；「附理由」只有 33 筆中的 2 筆做到 | keep，理由部分 soften |
| 29-36 | 刻意放在擁有者旁邊的例外 | P | 核對屬實 | keep |
| 37-38 | provider 檔可以 re-export 型別 | P | playlist_provider、download_providers `show DownloadResult` | keep |
| 42-49 | 接 service 的範例片段 | W | 範例用位置參數 `XService(repo, …)`，與 service-conventions:11 的具名參數規則衝突 | 改範例 |
| 51-52 | 擁有可釋放資源的 provider 都要 `ref.onDispose` | W | `playlistImportServiceProvider`（playlist_import_provider.dart:334） | 修程式 |
| 52-53 | DB 用 `.requireValue`，或 `.value` + StateError | P | repository_providers.dart、audio_controller_provider.dart | keep |
| 57-58 | 依賴在 `build()` 裡 `ref.watch`，不從建構子拿（family id 除外） | W | `UpdateNotifier({UpdateService? service, bool? isAndroidOverride})`（update_provider.dart:60） | soften，或修 |
| 59-61 | 同步初始 state + 不 await 的載入 | P | LayoutSettingsNotifier | keep |
| 61-63 | build 裡不能同步寫 state；用 `Future.microtask` | P | PlaylistDetailNotifier.build:326（Riverpod 本身禁止） | keep |
| 64-66 | build 裡開的訂閱由同一次 build 的 onDispose 關掉 | P | PlaylistListNotifier:84-92、playlist_import_provider:122-130 | keep |
| 66-67 | 改寫過的 notifier 要有「rebuild 保持正確」的測試 | W | notifier_rebuild_test 只涵蓋 layout / theme / import 三個 | soften |
| 68-70 | await 之後、碰 ref / state 之前檢查 `ref.mounted` | W | 13 個 notifier 檔有 await 卻沒有 ref.mounted（`theme_provider.dart:73-75`、`desktop_settings_provider.dart`、`track_detail_provider.dart:104-116`） | soften（keep-alive 的 notifier 可豁免？） |
| 71-72 | onDispose 裡不碰別的 provider；用 scheduleMicrotask 延後 | P | download_providers.dart:113（Riverpod 本身擋） | keep |
| 73-76 | 過期的 async 結果用 request id / generation 丟掉；補 stale 測試 | P | SearchNotifier、RefreshManagerNotifier、search_pagination_stale_test | keep |
| 77-79 | state 裡存的錯誤已經是給使用者的句子；絕不存 `e.toString()` | W | `audio_provider.dart:492`（共 7 處）、`ranking_cache_service.dart:290` | 修程式 |
| 83-85 | state class 手寫、不可變、const、copyWith、clearX | P | 29 個 `bool clear…` 旗標 | keep |
| 86-89 | 相等性：Equatable 且 props 列齊（有閘門），或 `@immutable` 手寫 `==` | W | 只有 5 個 state class extends Equatable；多數（ThemeState、AudioSettingsState、LayoutSettingsState、TrackDetailState…）兩者都沒有。閘門只檢查 extends Equatable 的 class | soften（描述實況） |
| 90 | 替換 collection，不原地改 | P | download_providers.dart:142、refresh_provider 的 newMap；沒找到原地修改 | keep |
| 94-95 | build 用 watch；callback 用 `read(x.notifier)` | P | | keep |
| 96-99 | 寬而熱的 provider 不整包 watch；`_narrowOnly` | G | `watch_scope_static_rule_test.dart` | keep |
| 100-102 | build 裡 `ref.listen`；Stateful 在 initState `listenManual`、dispose 時關 | P | lyrics_display.dart:75、import_playlist_dialog.dart:114（`account_playlists_sheet.dart:262` 在 handler 裡開，會先關舊的） | keep |
| 103-107 | 背景 provider 要在 `FMPApp.build` watch，集合 = `_anchoredProviders` | G | riverpod3_static_rule_test:30 | keep |
| 107 | Windows 專屬的放在 `if (Platform.isWindows)` 下 | P | app.dart:95 | keep |
| 108-110 | 歌單改動經 coordinator 失效 provider | G | `call_site_ownership_static_rule_test.dart`「playlist invalidation」 | keep |
| 111-112 | 全 app 關閉自動 retry | P | main.dart:268 | keep |
| 112 | 斷言錯誤分支的 widget 測試要傳同一個 `retry:` | W(1例) | 只有 `download_manager_error_state_test.dart` | keep |
| 116 | ProviderContainer + addTearDown | P | 30 支中 27 支 | keep |
| 117-119 | 用覆寫 build 的子類別 `overrideWith`；值用 `overrideWithValue` | P | `_FixedLayoutSettings`（nav_rail_semantics_test.dart:100） | keep |
| 120-121 | AudioController harness | P | | keep |

## ui/widgets.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 5-6 | 只讀 provider 用 ConsumerWidget；有 controller / listenManual / async 用 Stateful | P | | keep |
| 7-8 | 頁面拆成獨立的 ConsumerWidget 區塊 | P | HomePage 各區塊、track_detail_panel | keep |
| 9-11 | 私有 `_Xxx`；長大了搬 `pages/<feature>/widgets/`；跨頁放 `widgets/<category>/` | P | 目錄結構 | keep |
| 12 | const 建構子 + `super.key` | G | lints recommended 的 `use_super_parameters`、`prefer_const_constructors` | keep |
| 13-14 | await 之後 `if (!mounted)` / `if (!context.mounted)` | G + P | context 部分由 `use_build_context_synchronously` 擋；setState 部分沒找到反例 | keep |
| 15-17 | 值得測的版面決策寫成純頂層函式 | P | `resolvePlayerLayout`、`buildHomeRankingLayoutPlan` | keep |
| 23 | 破壞性確認用 `showConfirmDestructiveDialog` | P | 12 個檔案 | keep |
| 24 | 行內錯誤 / 空狀態用 ErrorDisplay / LoadingPlaceholder | P | | keep |
| 25 | toast；例外**只能**用 `ToastService.failure`；背景 service 用 toastServiceProvider | W | `downloaded_page.dart:507` 用 `ToastService.error(t…(error: userMessageFor(e)))` | soften |
| 26 | 成功 / 警告色用 ToastService 的常數 | P | settings_backup、lyrics_search_sheet | keep |
| 27 | ContextMenuRegion + MenuAction 的 builder | P | 10 個檔案 | keep |
| 28 | 曲目動作走 handlers | P | | keep |
| 29 | 有 trailing icon 的 popup item 用 PopupMenuRow，不用 ListTile | P | 沒找到帶 trailing 的 ListTile popup item（只有 leading 的：track_action_menu.dart:130） | keep |
| 30 | bottom sheet 用 CappedDraggableSheet、SheetDragHandle | W | 4 個檔案直接用 `DraggableScrollableSheet(`（account_playlists_sheet、account_radio_import_sheet、add_to_playlist_dialog、remote_playlist_dialog_widgets）；只有 3 個用 Capped | soften，或遷移 |
| 31 | 用 ScopedSlider，不用原生 Slider | G | slider_overlay_static_rule | keep |
| 32 | 圖片一律走語意 widget；不直接用 Image.network（有閘門） | G | `ui_consistency_static_rule_test.dart` `_imageApiOwners` | keep |
| 32 | 「也不用裸尺寸」（有閘門） | S | 頁面直接傳裸尺寸：`TrackThumbnail(size: 48)`（queue_page.dart:542、playlist_detail_page.dart:1407）、`AvatarImage(size: 48)`（account_management_page.dart:249）。閘門只管 loader 的 size tier / `ImageTargetSizes`，不管顯示尺寸 | fix 措辭（AGENTS.md 也同樣寫錯） |
| 33 | 時長文字用 DurationFormatter | P | 16 個檔案；沒找到手寫格式 | keep |
| 35-37 | 閘門清單 | G | 屬實 | keep |
| 38 | CustomTitleBar 只在 app.dart 建一次 | G | call_site_ownership「custom title bar」（原文沒寫出這個閘門） | 補上閘門出處 |
| 40-42 | dialog 入口兩種寫法都可以；用 `Navigator.pop` 關 | P | 98 處 Navigator.pop、0 處 context.pop | keep |
| 46 | 用 `.when(data:, loading:, error:)` | W | `download_manager_page.dart:351` 用 maybeWhen；`lyrics_display.dart:178` 用 hasError；`add_to_playlist_dialog.dart:132` 用 whenData | soften |
| 47-49 | 錯誤分支一定要渲染東西；`SizedBox.shrink()` 有閘門 | G | error_presentation「an async error branch never renders as nothing」 | keep |
| 49 | 載入分支可以是空的 | P | | keep |
| 50-52 | 餵 placeholder 的 FutureProvider 自己 log 再 `Error.throwWithStackTrace` | P | playlist_provider.dart:639,654 | keep |
| 56-59 | 顏色取自 colorScheme；固定色相只有列出的幾個一次性例外 | W | 還有沒列出的：品牌色 `account_management_page.dart:16-18`、`lyrics_title_bar.dart:73 Colors.amber`、`startup_failure_app.dart:37,54` | 補清單 |
| 60-61 | 圓角用 AppRadius、時長用 AnimationDurations、尺寸用 AppSizes / AppLayout | W | AppRadius 110 處，字面值 2 處（`color_palette_button.dart:426,487 BorderRadius.circular(8)`）；Duration 字面值 `queue_page.dart:133` | keep（輕微） |
| 62-64 | 間距寫字面值；AppSpacing 已刪，不要沒遷移就加回來 | P | `aa0bdd28`；187 處字面值 EdgeInsets | keep |
| 65 | 亮色 / 暗色主題出自同一份描述 | P | app_theme.dart | keep |
| 69-73 | 視窗骨架用 WindowClass.of，pane 內用 LayoutBuilder / columnsFor | P | responsive_scaffold、player_page；`9557e03f` | keep |
| 78-79 | 每個 IconButton 都有 `tooltip:` | P | lib/ui 裡的 IconButton 都有（lyrics window 的例外用 Semantics 補） | keep |
| 79 | 不要把 IconButton 包在 `Tooltip(...)` 裡 | W | `lyrics_title_bar.dart:225` 把 IconButton 包進 `Tooltip(excludeFromSemantics: true)`（在另一個 engine） | 寫明安全寫法 / 例外 |
| 80 | 48dp 觸控目標；text scale 2.0 不溢出 | W | `lyrics_title_bar.dart:219` 28dp；2 處 `tapTargetSize: shrinkWrap`；只有 6 支 widget 測試測 text scale | soften / 當作目標寫 |
| 81 | 巢狀 navigator 加 `Semantics(container: true)` | P | responsive_scaffold.dart:123、mini_player.dart:198 | keep |
| 85-86 | `Platform.is*` 判平台功能；`isDesktopPlatform` 判「桌面」 | P | | keep |
| 87-88 | 托盤 / 快捷鍵 / SMTC 不寫在 widget 裡 | P | windows_desktop_service、windows_smtc_handler | keep |
| 89-91 | 歌詞視窗在另一個 engine；要讀的字串必須推過去 | G | lyrics_window_strings_static_rule | keep |
| 95-97 | widget 測試的包法 + 在 setUp 設 en；斷言用 `t.xxx` 不用字面值 | W | 60 支中只有 32 支用 TranslationProvider；`track_detail_panel_test.dart:41,93-94` 斷言 zh-CN 字面值 '加载失败'、'重试'、'选择一首歌曲播放' | soften，或修測試 |
| 98-99 | ResponsiveScaffold 用 `tester.view.physicalSize` 驅動 | P | nav_labels_locale_test.dart:40-42,85 | keep |
| 100-101 | semantics 斷言：`ensureSemantics()` + `dispose()` | P | 7 支 | keep |
| 102 | 沒有 golden 測試 | P | 事實（0 個） | keep |

## guides/index.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 13 | 動到 3 層以上 → 讀 cross-layer guide | P(nav) | 門檻是模板式啟發法 | keep |
| 14 | 寫 source id 清單 / header / retry 等 → code-reuse guide | P(nav) | | keep |
| 15 | 改值之前先 `rg` | I | 通用建議 | keep 或刪 |
| 19 | cross-layer 的 Before-you-finish 清單要成立 | I | 繼承下面那份清單（多為 I） | 隨下面一起決定 |
| 23-27 | 審 AI finding 的四條提示（追來源、邊界已驗證、讀 dartdoc、在腦中刪掉 feature） | I | 通用審查建議；只有指向 SourceUrlPolicy / dartdoc 的部分是 FMP 專屬 | keep 當建議，或刪 |

## guides/code-reuse-thinking-guide.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 3-9 | 一個 concern 一個 owner；先搜尋 | P + I | 「owner 由靜態規則守」屬實；「先 rg」是通用建議 | keep |
| 13-28 | owner 對照表 | P | 表上每個 owner 都存在並在用 | keep |
| 32-33 | 三份以上相同形狀 → 抽到 owner | I | 通用的「三次法則」，沒有專案實例 | keep 當建議 |
| 34-35 | 跨後端必須一致的兩份 → 共用純函式 + 兩邊都跑的測試 | P | `backend_contract_test.dart` + 共用 rule 檔 | keep |
| 36-37 | 不為單一或想像中的呼叫者加抽象 | P | `aa0bdd28`、`19f721c7` | keep |
| 41-42 | 改常數：rg；更新 dartdoc 理由與釘住它的測試 | P | app_constants.dart 50 個 const、83 行 dartdoc | keep |

## guides/cross-layer-thinking-guide.md

| line | sentence (short) | class | evidence / counterexample | suggestion |
|---|---|---|---|---|
| 12-14 | 說出每個箭頭上跨過去的型別與誰轉換；錯誤在邊緣只翻譯一次 | I + W | 前半是通用建議；「只翻譯一次」有反例：service 層 `ImportException(t…)`（import_service.dart:176）；data 層 playlist_import 拋翻譯過的 Exception | soften |
| 20-21 | 新設定：有預設值；決定型別預設是否需要 migration | P | persistence § Migrations | keep |
| 22 | build_runner | P | | keep |
| 23-24 | backup 匯出匯入，或排除清單 | G | settings_backup_coverage | keep |
| 25 | 透過 `SettingsRepository.update` | P | | keep |
| 26-27 | provider；背景用途要在 FMPApp.build anchor | G | riverpod3 anchored | keep |
| 28 | UI + 三語字串 | G | slang implements → analyze | keep |
| 29-30 | 音訊會讀的話：兩個後端都遵守，或寫進 dartdoc | P | | keep |
| 34-37 | 新 source 的清單 | P + G | hosts / live guard / SourceManager 有閘門；`_bySource` 列與預設表是 P | keep |
| 37-38 | ADR 0001 規定未知 id 在各分支點的行為 | P | ADR 0001:113-118 | keep |
| 41-42 | 新字串：三語、slang、可能影響版面就上機；歌詞視窗要推 | G + P | slang / lyrics_window_strings 有閘門 | keep |
| 46-47 | 只用 TrackKey；ADR 0005 | P | | keep |
| 51-53 | 憑證：先點名是哪個 CONTEXT 術語；改動要同意 | P(policy) | CONTEXT.md、AGENTS | keep |
| 57 | 每個動到的箭頭，在擁有轉換的那一側有測試 | I | 建議（owner 偏好） | keep 當清單項 |
| 58 | 錯誤在邊緣前都是型別，在邊緣翻譯一次 | W | 同 12-14 | soften |
| 59 | 下游不重新 cast / 解析上游已建模的 payload | I | 通用建議 | keep 或刪 |
| 60 | 改到的契約，文件同一個 change 更新 | I | owner 全域偏好（「同輪更新 README…」） | keep 當政策 |

---

## 統計

| class | count |
|---|---|
| G | 60 |
| P | 271 |
| W | 71 |
| I | 15 |
| S | 4 |
| **合計** | 421 |

（一句兼有兩類時，如「G + W」，以需要 owner 決定的那一類計入。P 含 P(nav) 與 P(policy)。）
