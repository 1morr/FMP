# Research: coding conventions in `lib/core/` and `lib/data/`

- **Query**: Actual patterns a contributor must follow when adding code to `lib/core/` and `lib/data/` (sources, repositories, models, database, errors, logging, tests).
- **Scope**: internal
- **Date**: 2026-09-25

Already documented elsewhere. Specs should link to these and not restate them: `AGENTS.md` (boundaries and static-rule list), `CONTEXT.md` (Source Auth Context vocabulary), `docs/development.md` (data model classification, VM Service/Isar debugging), ADR 0001 (string source ids, `@embedded` per-source settings), ADR 0002 (Isar only in repositories, `InTxn` suffix), ADR 0005 (TrackKey includes cid), ADR 0007 (isar_community v3).

Historical note: until `e0e6c0c7` (chore: keep a single root AGENTS.md), the repo had scoped `lib/data/AGENTS.md` and `lib/data/sources/AGENTS.md`. They are readable at `git show e0e6c0c7^:lib/data/sources/AGENTS.md`. Most of their content now lives in dartdoc. Some claims in them are stale: for example, they say Bilibili `useAuthForPlay` defaults to false, but it is now true (`b9e243f9`). Treat them as rationale only. They are not a source of truth.

---

## 1. Source adapters (`lib/data/sources/`)

### 1.1 Shape: narrow capability interfaces, no base class
- **Rule**: an adapter is a plain class `with Logging implements DisposableSource, <capabilities…>`. Each capability is an `abstract interface class … implements SourceCapability` in `source_capabilities.dart`. There is deliberately no `BaseSource` base class.
  - `lib/data/sources/base_source.dart:4-5` has this comment: "刻意沒有「什麼都會」的 BaseSource 基底類別：音源只透過窄能力介面被取用". The file now holds only value types: `AudioStreamConfig`, `AudioStreamRequest`, `AudioStreamResult`, `SearchResult`, `PlaylistParseResult`, `SearchOrder`.
  - Capabilities: `TrackInfoSource`, `AudioStreamSource`, `TrackDetailSource`, `PagedVideoSource`, `DynamicPlaylistSource`, `RankingSource`, `LiveSource`, `SearchSource`, `PlaylistParsingSource`, plus the lifecycle interface `DisposableSource`, which is not a capability.
  - Examples: `NeteaseSource` (`netease_source.dart:25-33`) implements 7. `BilibiliSource` (`bilibili_source.dart:40-50`) implements 9. `YouTubeSource` (`youtube_source.dart:~26`).
  - `String get sourceType => SourceIds.<id>;` is the only member every capability requires.
- **Anti-pattern (commit history)**: broad facades get deleted. `19f721c7` removed the zero-caller `SourceManager` facade (`parseUrl`, `parsePlaylist`, `refreshAudioUrl`, `sources` getter). `cde4769e` removed dead `TrackInfoSource` methods (`isValidId`, `getTrackInfo`, `refreshAudioUrl`). `cd3aa568` removed an unused `AvailabilitySource` capability. A capability that nothing consumes gets removed. Nobody keeps one around "for later".

### 1.2 Registration and access via `SourceManager`
- **Rule**: concrete adapters are constructed only in `SourceManager` (`lib/data/sources/source_provider.dart`). Runtime code asks for a capability by source id or URL: `audioStreamSource(type)`, `searchSource(type)`, `trackInfoSourceForUrl(url)`, and so on. It gets a nullable interface back and never the concrete class.
  - `SourceManager({List<SourceCapability>? sources})` defaults to `[BilibiliSource(), YouTubeSource(), NeteaseSource()]`. Tests inject their own list.
  - `dispose()` works through `whereType<DisposableSource>()`, so a new adapter is disposed as long as it `implements DisposableSource`.
  - UI source lists come from `registeredSourceTypesProvider`, `searchSourceTypesProvider` and `rankingSourceTypesProvider`. The comment there says "不要自己寫一份清單".
- **Gate**: `test/data/static_rules/source_ownership_static_rule_test.dart`. It catches concrete adapter imports outside `source_provider.dart`, `*SourceProvider` / `.bilibiliSource`-style getters, and re-exports. The concrete-class set is derived from the top level of `lib/data/sources/` (classes named `*Source`/`*Client`). Recorded exceptions: `radio_source.dart` and `bilibili_account_service.dart` both use `BilibiliLiveClient`.
- **Gate**: `test/support/call_site_ownership_static_rule_test.dart`. `sourceManagerProvider` in `lib/ui/` is allowed only in `import_playlist_dialog.dart`. Bilibili live endpoints (`/room/v1/`, `/xlive/`, `bilibiliLiveHeaders(`) are allowed only in `bilibili_live_client.dart` and `source_http_policy.dart`.
- **Gate**: `test/support/source_branch_points_static_rule_test.dart`. Outside `lib/data/sources/`, `==`/`case`/switch-arm comparisons on source ids have a per-file budget, and the check uses equality. Maps keyed by `SourceIds.x` do not count. In-scope budget entries: `lib/core/errors/user_message.dart` (1) and `lib/core/utils/icon_helpers.dart` (3).
- **Unknown source id behaviour**: each branch point decides explicitly what happens for an unknown id instead of falling through a `default:` (ADR 0001 table). `SourceHttpPolicy` returns empty maps for unknown ids, and `source_ids.dart` has a dartdoc on this.

### 1.3 HTTP: always through `SourceHttpPolicy`
- **Rule**: adapters get their Dio from `SourceHttpPolicy.createApiDio(SourceIds.<id>, extraHeaders:…, userAgent:…, contentType:…)`. They accept an optional injected `Dio? dio` for tests.
  - `NeteaseSource({Dio? dio})` uses `_dio = dio ?? SourceHttpPolicy.createApiDio(SourceIds.netease)` (`netease_source.dart:45-47`).
  - `BilibiliSource({Dio? dio, Dio? liveDio, BilibiliLiveClient? liveClient, String apiBase…})` (`bilibili_source.dart:66-118`) uses `createApiDio(SourceIds.bilibili, extraHeaders: {'Cookie': _browserCookie})` and `createBilibiliLiveDio()`.
  - `YouTubeSource({yt.YoutubeExplode? youtube, Dio? dio})`.
  - `SourceHttpPolicy` (`source_http_policy.dart`) keeps one `_bySource` table with one record per source (`cdn`, `api`, `apiUserAgent`, `imageHosts`), introduced in `f6e33298`. The comment says "加音源時只改這裡". Every header set is derived from it: `mediaHeaders`, `imageHeaders`, `imageHeadersForUrl`, `apiHeaders`, `bilibiliSearchApiHeaders`, `bilibiliLiveHeaders`.
  - `HttpClientFactory.create` (`lib/core/utils/http_client_factory.dart`) supplies the default UA and the timeouts (`AppConstants.networkConnectTimeout` / `networkReceiveTimeout`). Only the policy and non-source clients call it directly.
- **Per-request auth**: adapters never read accounts. Auth arrives as `Map<String,String>? authHeaders` on the request (`AudioStreamRequest.authHeaders`, `getVideoDetail(…, {authHeaders})`, `parsePlaylist(…, {authHeaders})`, `SourceRankingRequest.authHeaders`). The adapter merges only what it needs. NeteaseSource `_withAuth` takes only `Cookie` (`netease_source.dart:778-783`). BilibiliSource `_withAuth(authHeaders)` builds `Options` (`bilibili_source.dart:167`).
  - The caller side is `SourceAuthContext` (`lib/services/account/source_auth_context.dart`). It exposes narrow purpose interfaces: `SourcePlaybackAuthContext.authForPlay`, `PlaylistAuthContext.playlistImportAuth/playlistRefreshAuth`, `DownloadSourceAuthContext`, and `PlaybackMediaRequestContext`. Vocabulary is in `CONTEXT.md`.
  - **Media bytes never carry credentials**: `SourceHttpPolicy.mediaHeaders(String sourceType)` takes only the id. The boundary lives in the signature. `c09aec10` removed the Netease media-cookie path. `test/data/sources/source_http_policy_test.dart` has the tests "no source can put credentials on a media byte request" and "mediaHeaders takes nothing but the source type", and pins exact header output in the `exact output` group.
- **Gate**: `test/support/source_http_policy_static_rule_test.dart`.
  - (a) A file that builds `Dio(`/`HttpClientFactory.create(` and names a `SourceIds.x` must use `SourceHttpPolicy.`.
  - (b) A `createApiDio(` call must name a source id that matches the path token.
  - (c) `Referer`/`Origin`/`User-Agent` literals may appear only in files on the `_headerLiteralOwners` list. The in-scope entries are `source_http_policy.dart`, `http_client_factory.dart`, `playlist_import/qq_music_playlist_source.dart` and `playlist_import/spotify_playlist_source.dart`, each with a reason.
- **Gate**: `test/support/outbound_hosts_static_rule_test.dart`. Every hard-coded `http(s)://` host in `lib/` must be on the list with a purpose.
- **URL trust**: URL parsing and redirects go through `SourceUrlPolicy` (`source_url_policy.dart`).
  - `parseTrustedHttpUrl(url, allowedHosts:)` normalizes the host, allows only http/https, uses exact host allowlists (`neteaseHosts`, `spotifyHosts`, …) and rejects private/loopback/CGNAT hosts.
  - `resolveRedirects(dio, url, initialAllowedHosts:, redirectAllowedHosts:)` validates every hop and allows at most 5.
  - Used by `NeteaseSource.parseId` (`netease_source.dart:55`), `SpotifyPlaylistSource.canHandle` and `QQMusicPlaylistSource`.
  - The old AGENTS.md said: "Do not detect platforms with substring checks against the raw input URL". Tests: `test/data/sources/source_url_policy_test.dart`.

### 1.4 Errors: `SourceApiException` subtypes
- **Rule**: every adapter throws its own `<Source>ApiException extends SourceApiException` from `<source>_exception.dart`. The subclass maps its native code to `SourceErrorKind`, and callers read only `kind`/semantic getters.
  - Base class: `lib/data/sources/source_exception.dart`. It has `code`, `message`, `sourceType`, `kind`, and the getters `isUnavailable`/`isRateLimited`/`requiresLogin`/`isPermissionDenied`/`isVipRequired`/…. `SourceErrorKind` has policy getters `isRetryable`, `shouldSkipTrack` and `canFallbackToLowerAudioQuality`.
  - `BilibiliApiException({numericCode, message})` (`bilibili_exception.dart`). `riskControlCodes = {-352,-412,-509,-799}` is the single list, pinned by `source_exception_test.dart` (`5d1dc5e4`).
  - `NeteaseApiException({numericCode, message})` (`netease_exception.dart`) uses synthetic codes -997 (timeout), -998 (network), -999 (unexpected).
  - `YouTubeApiException({code, message})` (`youtube_exception.dart`) uses a String code with a `switch` expression.
- **Try/catch shape inside adapter methods**, repeated in Netease (`netease_source.dart:164-170`, 245-251, 318-323) and Bilibili (`bilibili_source.dart:630-635`, 665-670):
  ```dart
  } on DioException catch (e) {
    throw _handleDioError(e);
  } catch (e) {
    if (e is NeteaseApiException) rethrow;
    logError('Unexpected error in getAudioStream: $e');
    throw NeteaseApiException(numericCode: -999, message: e.toString());
  }
  ```
  - Each adapter has a private `_handleDioError(DioException)` that calls `SourceApiException.classifyDioError(e)` (the shared HTTP-status/type → kind table) and then wraps the result in its own subtype. Example: `netease_source.dart:977-1007`.
  - Each adapter has a `_checkResponse(data)` that turns a non-success body code into the subtype, after a `logWarning` (`netease_source.dart:827-839`).
- **Pitfall (`ca54669c`)**: always `return await …` inside `try`. A returned un-awaited future escapes the catch blocks, so `_handleDioError` never ran and YouTube's rate-limit detection was skipped.
- **Pitfall (`e2321e38`, `5e06389d`, #87)**: classification order matters. Netease "login required" (`code==301`, or `code==404 && fee==0`) is checked before VIP, and `flag & 4` is not a VIP signal. This is documented in the dartdoc at `netease_source.dart:926-936` and in the comments of `_classifyStreamUnavailable`.
- **Quality fallback**: `audio_stream_quality_fallback.dart` is the shared high→medium→low ladder (`130127e7`). It runs only when `SourceErrorKind.canFallbackToLowerAudioQuality` is true (unavailable or vipRequired).
- **Expiry**: return the TTL that the source reports in `AudioStreamResult.expiry` and do not hard-code it (`b1fa0fc5`; see the Netease `_fallbackAudioUrlExpiry` comment).
- **Playlist import sources are different** (`lib/data/sources/playlist_import/`). They implement `abstract class PlaylistImportSource` (`source`, `canHandle`, `extractPlaylistId`, `fetchPlaylist`), are registered in `lib/services/import/playlist_import_service.dart:137` (not in SourceManager), use `HttpClientFactory.create()` directly, and throw plain `Exception(t.importSource.…)` with slang-translated messages (for example `spotify_playlist_source.dart:53,76`). They are a separate registration path and the ownership rule excludes the subdirectory.

### 1.5 Constructor side effects and tests
- A test that builds a real adapter with its default constructor (`BilibiliSource()`, `NeteaseSource()`, `SpotifyPlaylistSource()`, …) must be tagged `live`. Enforced by `test/support/live_source_tag_static_rule_test.dart`, which has a `_guardedClasses` list and a `_exceptions` list with reasons. Its dartdoc says: "新增音源時加在這裡".

---

## 2. Repositories (`lib/data/repositories/`)

- **Rule**: a repository is a concrete class that takes `Isar` in its constructor. It is not an interface, and there is not one repository per collection (ADR 0002).
  - Positional constructor `XxxRepository(this._isar)` with `final Isar _isar;`: `SettingsRepository`, `PlaylistRepository`, `SearchHistoryRepository`, `AccountRepository`, `TrackRepository`.
  - `PlaylistMutationRepository({required Isar isar})` uses a named constructor (one-off).
  - `with Logging` where the class logs: `TrackRepository`, `QueueRepository`, `PlaylistMutationRepository`, `DownloadRepository`.
  - Barrel: `repositories.dart` uses `export 'package:fmp/...'` (`9357812b`: "use package exports in the barrel files").
- **Riverpod wiring**: repository providers live in `lib/data/database/repository_providers.dart`, not in `lib/providers/`. Each has the same shape:
  ```dart
  final xRepositoryProvider = Provider<XRepository>((ref) {
    final db = ref.watch(databaseProvider).value;
    if (db == null) throw StateError('Database not initialized');
    return XRepository(db);
  });
  ```
  `sourceManagerProvider` likewise lives in `lib/data/sources/source_provider.dart`.
- **Method naming** (repeated across files):
  - Reads: `getById`, `getAll`, `getByName`, `getBySourceId`, `getByPlatform`, `getRecent({limit})`, `count()`, `getOrNull()`, `getOrCreate` / `getOrCreateAll` (dedupe upsert, `track_repository.dart:369,424`).
  - Writes: `save`, `saveAll`, `delete`, `deleteAll`, `deleteById`, `clear`, `upsert`, `update(mutate)`, `updateXxx`.
  - Streams: `watch()`, `watchAll()`, `watchById(id)`, `watchByPlatform`, `watchByTrackKey`, `watchDownloaded`, `watchAllTasks`, `watchHistory`.
  - `Sync` suffix for sync variants: `AccountRepository.getByPlatformSync`.
- **Returns**: Isar model objects directly, with no mapping layer. `save` returns the saved model with `id` filled in (`TrackRepository.save`, `track_repository.dart:149-154`). `PlaylistRepository.save` returns `int` id, `delete` returns `bool`, and `deleteAll` returns `int`. Mutation-heavy repositories return result records such as `PlaylistMutationResult` (`playlist_mutation_repository.dart:9-43`).
- **Transactions**:
  - Every write is wrapped in `_isar.writeTxn(() => …)`, and single-row writes are a one-liner: `return _isar.writeTxn(() => _isar.playlists.put(playlist));`.
  - Bulk updates mutate the loaded objects and call `putAll` in one txn (`PlaylistRepository.updateSortOrders`, `DownloadRepository` lines 224-301).
  - Read-modify-write is done in one txn to avoid lost updates: `SettingsRepository.update(void Function(Settings) mutate)` (`settings_repository.dart:36-46`). The comment explains that multiple Notifiers each hold a Settings copy and `save()` overwrote them.
  - Timestamps are set by the repository before `put`: `updatedAt = DateTime.now()` in `TrackRepository.save/saveAll` and `PlaylistRepository.save`.
  - **`InTxn` suffix**: a method with this suffix assumes the caller is already inside `writeTxn`. It is not passed a txn handle, because Isar's `_requireNotInTxn` is Zone-level and a nested `writeTxn` throws. Examples: `addTracksInTxn` (`playlist_mutation_repository.dart:292-305`, with its wrapper `addTracks => _isar.writeTxn(() => addTracksInTxn(...))`), `mergeDuplicateTrackMembershipsInTxn`, `remapPlaylistTrackReferencesInTxn`, the top-level function `relinkLyricsMatchToCidKeyInTxn(Isar isar, …)` (`lyrics_repository.dart:72`), and the private `_trimInTxn` (`play_history_repository.dart:41`). Introduced in `4bfab27d`.
  - Cross-collection atomic writes belong in a repository (`BackupRepository.writeImport`, `8a43d914`: "import everything or nothing"). They do not belong in a service.
- **Watch streams**: `…where()…watch(fireImmediately: true)` for lists (`PlaylistRepository.watchAll`, `RadioRepository.watchAll`), `watchObject(id, fireImmediately: true)` for singletons (`RadioRepository.watchById`; `SettingsRepository.watch` omits fireImmediately), `watchLazy()` for change pings (`PlayHistoryRepository.watchHistory` → `Stream<void>`), and a `.map(...)` to a single nullable (`AccountRepository.watchByPlatform`).
- **Closed-instance tolerance (`5f3bec68`)**: `QueueRepository._isUsable` checks `_isar.isOpen` and no-ops fire-and-forget writes after close (`queue_repository.dart:11-21`). This is a one-off, justified because the queue is rebuildable state.
- **Upward dependencies**: repositories take policy numbers from callers and do not read higher layers. `PlayHistoryRepository.addHistory(keepAtMost:)` receives the number from `PlayHistoryRecorder` (documented at `settings.dart` `playHistoryLimit`).
- **Repository-local exceptions**: `playlist_exceptions.dart` has `PlaylistNameExistsException` and `PlaylistNotFoundException` `implements Exception`, and their `toString()` returns a slang string. They are thrown inside txns (`addTracksInTxn`).
- **Gate**: `test/data/static_rules/isar_boundary_static_rule_test.dart`. The regex `(?<![A-Za-z0-9_])_?isar\s*\.\s*[a-z]` allows `lib/data/repositories/` plus `database_catalog.dart` and `database_migration.dart`. It includes meta-tests for dart-format line splits, import lines, `Isar.minLong`, and comments.

---

## 3. Isar models and the database (`lib/data/models/`, `lib/data/database/`)

### 3.1 Model conventions
- File header: `import 'package:isar_community/isar.dart';` plus `part 'x.g.dart';`. Generated `*.g.dart` files are gitignored, so run `dart run build_runner build`.
- `@collection class X { Id id = Isar.autoIncrement; … }`. Singleton exception: `Settings` uses `Id id = 0;`, and `SettingsRepository` forces `settings.id = 0` on save.
- Models are **mutable classes with field initialisers**: `late String sourceId;` for required fields, `String? artist;` for optional ones, and defaults like `bool isAvailable = true; DateTime createdAt = DateTime.now();`. Instances are built with cascades, for example `PlayHistory()..sourceId = …` (`play_history.dart:51-61`). Isar models do not use `const` constructors, `copyWith`, or `==`.
- Copies use a hand-written `copy()`: `Track.copy()` (`track.dart:~297`), `PlaylistDownloadInfo.copy()`, `SourceSettingsEntry.copy()`.
- Conversions are static or instance methods on the model: `PlayHistory.fromTrack(track)` / `toTrack()`, `VideoPage.toTrack(parent)`.
- `@Index()` goes on lookup and sort fields: `sourceId`, `sourceType`, `cid`, `updatedAt`, `playedAt`, `timestamp`. Other index forms:
  - Unique indexes: `@Index(unique: true)` on `Playlist.name` and `RadioStation`; `@Index(unique: true, replace: true)` on `LyricsMatch.trackUniqueKey` and `LyricsTitleParseCache.trackUniqueKey`.
  - Getter indexes: `@Index(composite: [CompositeIndex('cid')]) String get sourcePageKey` (`track.dart:277`), `@Index() String get trackKey` (`play_history.dart:46`). Isar persists getters and recomputes them only on `put`. Changing a getter's output needs a rewrite migration (dartdoc at `play_history.dart:40-45`, ADR 0005).
- `@ignore` marks derived getters and non-persisted fields: `Track.viewCount`, `allPlaylistIds`, and Settings enum getters.
- `@embedded` for structured sub-records in a `List<…>` (`PlaylistDownloadInfo`, `SourceSettingsEntry`). **Pitfall**: to change an embedded value you must build a new object and a new list, because Isar will not detect an in-place mutation. This is repeated in comments at `track.dart:110,192,206`, `settings.dart:125,698` and in `Settings._putEntry`.
- Enums are persisted two ways:
  - `@Enumerated(EnumType.name)`: `DownloadTask.status`, `PlayQueue.loopMode`.
  - An `int xxxIndex` field plus an `@ignore` getter/setter pair with a `switch`: `Settings.themeModeIndex`/`themeMode`, `audioQualityLevelIndex`, `downloadImageOptionIndex`. Settings uses this style throughout.
  - Source ids are **never** enums. They are `String` with `SourceIds.*` constants (`source_ids.dart`, ADR 0001, `0b93e61d`).
- Comma-separated strings are used for ordered preferences, with parse/normalize helpers next to the model: `audioFormatPriority`, `lyricsSourcePriority`, `homeRankingSourcePriority`, `parseStreamPriority`, `normalizeHomeRankingSourcePriority` (`settings.dart:94-200`). `hotkeyConfig` is a one-off JSON string.
- Default tables are **data, not schema**: `kDefaultStreamPriorityBySource` and `kDefaultUseAuthForPlayBySource` (`settings.dart:58-80`), keyed by `SourceIds`.
- Removed fields: `@Deprecated('read only by the v1 to v2 migration; removed in a later schema version')`, combined with the `deprecated_member_use_from_same_package` lint in `analysis_options.yaml`. `database_migration.dart` is the only file with `// ignore_for_file: deprecated_member_use_from_same_package`, and it gives the reason in a comment.
- Dead persisted fields are deleted outright once nothing reads them (`6de4dfca`, `5654a4d5`). A deleted migration step stays as a no-op so the version list has no gap (`_migrateV2ToV3`).
- Sensitive data: `Account` stores only non-sensitive fields. Cookies and tokens live in `flutter_secure_storage` behind `SecureKeyValueStore` (`lib/core/secure_key_value_store.dart`; the dartdoc at `account.dart:5-8` says so).
- Barrel: `models.dart` exports only persisted collections. `track.dart` re-exports `source_ids.dart`, which is why many files import `SourceIds` from `models/track.dart`.

### 3.2 Registering a collection
- `lib/data/database/database_catalog.dart`: add a `_collection<T>(name:, schema:, query: (isar) => …, title:, subtitle:, sections:)` entry to `fmpDatabaseCollections`. `fmpDatabaseSchemas` is derived from that list and passed to `Isar.open`, so the catalog is both the schema list and the debug-viewer definition. `docs/development.md` calls it the "權威清單".
- Open only via `openFmpDatabase()` (`database_provider.dart:86-108`), which uses `maxSizeMiB: 2048` (the comment explains why it is not 64, `4b9fa383`) and `compactOnLaunch`. `databaseProvider` then runs `runDatabaseMigration`.
- Test hooks: `@visibleForTesting runDatabaseMigrationForTesting`, `resolveFmpDatabaseDirectoryPathForTesting`, `ensureFmpDatabaseDirectoryForTesting`. This is the `…ForTesting` wrapper pattern around private functions.

### 3.3 Migration procedure
The source of truth is the dartdoc on `kFmpSchemaVersion` in `lib/data/database/database_migration.dart:21-32`. Current value: 4. Summary:
1. Change the model. Decide whether Isar's type default for old rows matches the business default. Old rows read non-null `int` as `Isar.minLong`, `double` as NaN, `bool` as false, `String` as `''`, `List` as `[]`, and nullable fields as null. If the defaults differ, add a `NamedMigrationStep(from:, to:, name:, run:)` to `fmpMigrationSteps` and bump `kFmpSchemaVersion`.
2. Version-independent guards go in `repairSettingsInvariants`, `hasUnwrittenQueueSignature`, or the startup relink (`_relinkLyricsMatchesToCidKeys`). These are explicitly "不是遷移，不掛版本號" and run every launch.
3. Always read the version through `effectiveSchemaVersion()` and never the raw field, because negative values mean v0.
4. Everything runs in **one** `writeTxn` (`runDatabaseMigration`).
5. Run `dart run build_runner build` and `flutter test test/providers/database_migration_test.dart`. Update `database_catalog.dart` in the same commit if visibility changed. For risky schema work, run `test/manual/real_db_probe.dart` (ADR 0007).
6. Backups too: settings/schema commits also touch `lib/services/backup/backup_data.dart` / `backup_service.dart` (`b9e243f9`, `5654a4d5`). `test/services/static_rules/settings_backup_coverage_static_rule_test.dart` requires every generated `Settings` `PropertySchema` field to be backed up or listed in `_deliberatelyExcludedSettingsFields` with a reason.
- Copy-without-clear migrations keep downgrades lossless (v1→v2, ADR 0001).

### 3.4 Identity keys
- Use only `TrackKey.format(sourceType, sourceId, cid:)` or `TrackKey.formatGroup` (`track_key.dart`, `adeef972`). Do not inline `'$type:$id'`. The literal output is pinned by `test/data/models/track_key_test.dart` (ADR 0005). When cid is backfilled, the lyrics match must be relinked in the same txn (`TrackRepository.backfillCid`, `abe05716`). Orphan track cleanup must not delete `LyricsMatch` (`f88effec`, dartdoc at `track_repository.dart:629-632`).

---

## 4. Non-persisted models (DTOs / value objects)

- Located in `lib/data/models/` (`video_detail.dart`, `live_room.dart`, `hotkey_config.dart`, `track_key.dart`, `dynamic_playlist_types.dart` in sources) and in `base_source.dart`. No migration is needed unless the model is registered in the catalog (`docs/development.md`).
- **Immutable style**: `final` fields, `const` constructor with named `required`/defaulted params, empty collections default to `const []`, plus `factory X.empty()` (`SearchResult.empty()`). The lints `prefer_const_constructors` and `prefer_const_declarations` are on.
- **copyWith**: the null-coalescing form `x: x ?? this.x`, in `AudioStreamConfig`, `MatchedTrack`, `LiveRoom`, `HotkeyBinding`. When a nullable field must be clearable, add `bool clearX = false` flags, as in `AudioStreamRequest.copyWith(clearCid:, clearAuthHeaders:, clearFailedUrl:)` (`base_source.dart:71-92`).
- **Equality**: hand-written `operator ==` plus `hashCode => Object.hash(...)`, only where the type is used as a key or compared: `TrackKeyParts` (`track_key.dart:62-70`), `TrackSourceIdentity` (`track_repository.dart:31-39`), `LiveRoom` (roomId only). `equatable` is a dependency but is used only in `lib/providers/…`, never in core/data.
- **JSON parsing**: no code generation (no json_serializable/freezed). Parsing uses hand-written factories named after the API shape, such as `LiveRoom.fromLiveRoomSearch` / `fromBiliUserSearch` / `fromRoomInfo`, `VideoDetail.fromNetease` / `fromYouTube` / `fromMetadata`, and `HotkeyBinding.fromJson` + `toJson`.
  - Style: `json['k'] as int? ?? 0`, `json['k'] as String? ?? ''`, and `(json['list'] as List<dynamic>?) ?? []`.
  - Defensive helpers inside adapters: `_asInt(Object?)`, `_ensureMap(dynamic)`, `_streamErrorMessage` (`netease_source.dart:814-925`).
  - Unknown enum strings fall back to a default (`HotkeyAction.values.firstWhere(..., orElse:)`). A corrupt stored JSON string returns defaults (`HotkeyConfig.fromJsonString`, try/catch).
- `toString()` overrides exist for logs and deliberately leave out secrets and URLs: `AudioStreamResult.toString` prints bitrate/codec but not `url` (`base_source.dart:132`), and `Account.toString` does not print userId.

---

## 5. Error types in `lib/core/errors`

- `lib/core/errors/user_message.dart` is the single mapping from exception to user text:
  - `userMessageFor(Object)` is an exhaustive `switch` over `SourceApiException`, `DioException` (reusing `classifyDioError`), `SocketException`/`HttpException`/`TlsException`, `TimeoutException`, `FormatException` and `PathAccessException`, with `_ => t.error.unknownError`. Its dartdoc says: "沒列到的型別一律回「發生錯誤」" (issue #41).
  - `sourceErrorReason(SourceApiException)` prefers the adapter's diagnostic message unless it is low-signal or on the `_syntheticDiagnostics` list, and otherwise uses the kind's translation.
  - `failureMessage(error, stackTrace, what, {tag})` logs the original with `AppLogger.error` and returns the translated sentence for `state.error` (`5e9d2929`: nine providers had stored `e.toString()`).
  - The UI counterpart is `ToastService.failure(context, error, {stackTrace, tag})` in `lib/core/services/toast_service.dart:180-197`, guarded by `test/ui/static_rules/error_presentation_static_rule_test.dart` (out of scope).
- **Rule for data code**: throw a typed exception (a `SourceApiException` subtype, a repository exception, or `SecureStorageUnavailable`). Do not build user strings from `e.toString()`. User-visible messages inside data code come from slang `t.…` (`classifyDioError`, `playlist_exceptions.dart`, the playlist import sources).
- `SecureStorageUnavailable(operation, code)` (`secure_key_value_store.dart:12-27`) carries only the platform code and never the message, because the message may contain a key alias or path. "Unreadable" is kept separate from "absent" (`38837a9e`, #72).
- `b1913e86` and `2421f73d` show the rule that a bare `DioException` is expected at the UI and must be classified, not reported as "unknown".

---

## 6. Logging

- **Logger**: `lib/core/logger.dart`.
  - Classes use the `mixin Logging` (`logDebug/logInfo/logWarning/logError(message, [error, stackTrace])`, where the tag is `runtimeType`).
  - Top-level functions and non-mixin code call `AppLogger.info(msg, 'Tag')` / `AppLogger.error(msg, error, stack, tag)` directly (`database_migration.dart:50-53`, `user_message.dart`, `toast_service.dart`).
  - `print`/`debugPrint` do not appear in core/data outside `logger.dart` (grep confirmed).
- Levels: debug for request tracing (`'Getting audio stream for netease song: $sourceId…'`); warning for API error bodies (`_checkResponse`); error for Dio failures and unexpected catches (`_handleDioError` logs `type` and `statusCode` only, not the URL or body); info for one-time events such as an applied migration step.
- **Redaction**: `AppLogger._log` runs `redactSensitive` on both message and error before buffering, streaming, or writing to file.
  - Covered patterns: `Authorization`, `Bearer`, `SAPISIDHASH`, `Cookie:`, and the `_sensitiveKeys` list (`MUSIC_U`, `__csrf`, `csrf`, `eparams`, `SESSDATA`, `bili_jct`, `DedeUserID`, Google SID family, `refresh_token`, `access_token`, `apiKey`, `password`, `token`, …).
  - When a new credential shape appears, add the key and a case in `test/core/logger/redaction_test.dart`. That test was written test-first in `1cf2989c`.
  - Don't rely on redaction: log ids and codes, not header maps, cookies, signed stream URLs, or raw platform messages.
- Logs are persisted to `<documents>/FMP/logs/fmp.log` by `LogFileSink` (rotation at 2 MB, 3 files, I/O failures swallowed; `43491b6d`). The in-memory buffer holds 500 entries.
- `docs/development.md` says VM Service tokens, signed stream URLs and cookies must not be pasted into issues, PRs or logs.

---

## 7. Naming, layout, imports, comments

- Files are `snake_case.dart`. Class-to-file naming:
  - `<Source>Source` → `<source>_source.dart`
  - `<Source>ApiException` → `<source>_exception.dart`
  - `<Entity>Repository` → `<entity>_repository.dart`
  - Policies: `Source<Thing>Policy` → `source_<thing>_policy.dart`
- `lib/core/` holds `constants/` (`AppConstants` holds timeouts and limits such as `maxSearchHistoryCount` and `networkConnectTimeout`), `errors/`, `extensions/`, `services/` (image loading, toast), `utils/` (`http_client_factory`, `netease_crypto`, `innertube_utils`, formatters), and top-level `logger.dart`, `log_file_sink.dart` and `secure_key_value_store.dart`.
- **Imports**: always `package:fmp/…`, enforced by the `always_use_package_imports` lint with its reason given in `analysis_options.yaml` (`88627251`). Barrels use package exports. In tests, `test/support/*` helpers are imported relatively (`'../../support/isar_test_harness.dart'`), because they are not under `lib/`.
- **Layering gate**: `test/support/layer_boundary_static_rule_test.dart`. `lib/core/` and `lib/data/` must not import `lib/services/` or `lib/providers/`. The single named exception is `lib/core/extensions/track_extensions.dart` → `providers/download/file_exists_cache.dart`. Imports from core to data do happen and are allowed, for example `core/errors/user_message.dart` imports `data/sources/source_exception.dart`. `SourceIds.values` lives in models rather than being derived from SourceManager so that models do not depend on sources (dartdoc at `source_ids.dart:22-25`).
- **Comments**: the tree is mixed. Older code is Simplified Chinese (for example `/// 获取所有歌单` in `playlist_repository.dart`, `/// Bilibili API 错误`), and newer code is Traditional Chinese. Many files mix both line by line, for example `settings_repository.dart` and `track_repository.dart:48-50`, where a stale Simplified line "获取所有歌曲" sits above a Traditional line. The AGENTS.md convention is to write new or edited lines in Traditional and not convert untouched lines. Log messages, exception messages, test names and commit messages are English.
- **Dartdoc**: the reasoning for rules lives in `///` on the symbol and explains why, often with dates, measurements, commit hashes or issue numbers (for example `bilibili_source.dart:75-82`, `netease_source.dart:926-936`, `track.dart:283-287`). `[Identifier]` references are checked by the `comment_references` lint, and the lint's reason is in `analysis_options.yaml`. Emphasis is written as `**…**`.
- Section dividers `// ========== X ==========` are used in adapters (`netease_source.dart:52,90`), models (`track.dart:82,220,244`, `settings.dart`) and `source_exception.dart`.
- The `ForTesting` suffix plus `@visibleForTesting` is used for test hooks into private functions (`database_provider.dart`).

---

## 8. Static-rule gates relevant to core/data (rule → test)

| Rule | Test |
|---|---|
| `isar.`/`_isar.` only in `lib/data/repositories/` (+ catalog, migration) | `test/data/static_rules/isar_boundary_static_rule_test.dart` |
| Concrete adapters only via `SourceManager`; no concrete getters/providers/re-exports | `test/data/static_rules/source_ownership_static_rule_test.dart` |
| core/data don't import services/providers; new feature→feature edges recorded | `test/support/layer_boundary_static_rule_test.dart` |
| Source HTTP clients via `SourceHttpPolicy`; header literals only in listed files | `test/support/source_http_policy_static_rule_test.dart` |
| Per-source-id branches outside adapters have a fixed per-file budget | `test/support/source_branch_points_static_rule_test.dart` |
| Hard-coded hosts listed with purpose | `test/support/outbound_hosts_static_rule_test.dart` |
| `Timer.periodic`/`Stream.periodic` listed with owner | `test/support/periodic_timer_static_rule_test.dart` |
| Bilibili live endpoints only in live client; `sourceManagerProvider` in UI only in import dialog | `test/support/call_site_ownership_static_rule_test.dart` |
| Tests building real sources with default ctor are tagged `live` | `test/support/live_source_tag_static_rule_test.dart` |
| Every `Settings` persisted field is backed up or excluded with reason | `test/services/static_rules/settings_backup_coverage_static_rule_test.dart` |
| Tests reading `lib/` source are named `*_static_rule_test.dart` in `test/support/` or `test/<layer>/static_rules/` | `test/support/static_rule_placement_static_rule_test.dart` |
| `main` registers licences before `runApp` | `test/core/static_rules/core_source_static_rule_test.dart` |
| No fixed `pumpEventQueue` outside `pump_until.dart` | `test/support/wait_convention_static_rule_test.dart` |

- Compiler-enforced (lint, not test): `always_use_package_imports`, `deprecated_member_use_from_same_package` (only the migration reads deprecated Settings columns), `comment_references`.
- Pinned by behaviour tests (not static rules): `TrackKey` literal output (`test/data/models/track_key_test.dart`); exact header output and the no-credential media headers (`test/data/sources/source_http_policy_test.dart`); the Bilibili risk-control code set (`test/data/sources/source_exception_test.dart`); unknown source ids surviving an Isar round-trip (`test/data/models/unknown_source_id_roundtrip_test.dart`); logger redaction (`test/core/logger/redaction_test.dart`).
- Shared plumbing for static rules: `test/support/dart_source.dart` `stripDartComments()` removes comments while keeping string literals, and every source-scanning rule calls it. Every static rule includes meta-tests with synthetic violations (should fail) and look-alikes, comments or reformatting (should pass). Examples: the `guard detects…` / `guard ignores…` tests in `isar_boundary_static_rule_test.dart:67-121`. Allowlists are const maps whose values give the reason, and there is an "every allowlist entry still exists" test.

---

## 9. Tests in this scope

- **No mocking library.** `pubspec.yaml` has no mockito or mocktail. Tests use hand-written fakes:
  - `test/support/fakes/`: `fake_isar.dart` (`class FakeIsar extends Fake implements Isar {}` as a constructor placeholder that throws on use), `fake_settings_repository.dart` (`extends SettingsRepository` with `super(FakeIsar())`, overriding `get`/`update`), `fake_secure_key_value_store.dart`, `fake_source_auth_context.dart`, `fake_audio_service.dart`.
  - File-private fakes: `_RecordingSource implements AudioStreamSource` and `_FakeSourceException extends SourceApiException` in `test/data/sources/audio_stream_quality_fallback_test.dart:99,139`; `_FakeYoutubeExplode extends yt.YoutubeExplode` in `youtube_source_test.dart:1721`.
- **Real Isar, not fakes, for repositories** (ADR 0002: "測試用真的 Isar，跑在 temp 目錄"). The pattern, repeated in 11 files under `test/data/`, for example `test/data/repositories/search_history_repository_test.dart:15-40`:
  ```dart
  setUpAll(() async => initializeIsarForTests());          // test/support/isar_test_harness.dart
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('search_history_');
    isar = await Isar.open([SearchHistorySchema], directory: tempDir.path, name: 'search_history_test');
    repo = SearchHistoryRepository(isar);
  });
  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });
  ```
  - Open only the schemas the test needs. `initializeIsarForTests()` is the only place in `test/` that knows the native library package and file names (`isar_test_harness.dart:7-19`).
  - Migration tests call `runDatabaseMigrationForTesting(isar)` (`test/providers/database_migration_test.dart`).
- **HTTP stubbing** always injects a `Dio` into the adapter constructor. Two styles are used:
  - `InterceptorsWrapper(onRequest: … handler.resolve(Response(...)))`, via the helpers `_dioReturning` and `_dioRecordingRequests` (`test/data/sources/netease_source_test.dart:442-487`).
  - A custom `HttpClientAdapter` (`_FakeHttpClientAdapter` with a handler `(RequestOptions, Object? body) → ResponseBody.fromString(jsonEncode(...))`) in `test/data/sources/youtube_source_test.dart:1699-1719`, `test/bilibili_source_test.dart`, `bilibili_live_client_test.dart:1312` (`_FakeDioAdapter`) and `source_url_policy_test.dart:142` (`_RedirectAdapter`).
  - Fixture JSON is built inline with Dart map literals and small builder functions (`_innerTubePlayerResponse(...)`, `_innerTubeAudioFormat(...)`). There is no fixture-file directory.
- **Error assertions**: `throwsA(isA<XApiException>().having((e) => e.kind, 'kind', SourceErrorKind.loginRequired).having((e) => e.code, 'code', 'login_required'))` (`youtube_source_test.dart:~35-45`).
- **Live tests**: `@Tags(['live'])` + `library;` at file top (`test/live/sources_live_test.dart:12`), or per-test `tags: 'live'` (`test/bilibili_source_test.dart:902`). The tag is declared in `dart_test.yaml` and CI runs `flutter test --exclude-tags live`.
- Test comments state what the test pins and why, often with the defect's history (for example `unknown_source_id_roundtrip_test.dart:11-16`). Test names are English sentences.
- Oddity: `test/bilibili_source_test.dart` sits at the `test/` root, not under `test/data/sources/`. This is a one-off.

---

## Caveats / Not found

- Not found: any `abstract Repository` interface, freezed or json_serializable, a mocking library, or a fixtures directory. Their absence is itself the convention (ADR 0002 rejects the interface layer).
- The enum persistence style is split between `@Enumerated(EnumType.name)` and int-index fields with `@ignore` accessors. I found no documented rule choosing one. New `Settings` fields follow the int-index style.
- Constructor style differs: `PlaylistMutationRepository({required Isar isar})` is the only named-param repository constructor.
- `lib/core/services/` (image loading, toast, network image cache) were only skimmed for logging and error behaviour. Their UI-facing conventions belong to the frontend research.
- `youtube_source.dart` (2425 lines) was only sampled. It has extra helpers (`_classifySourceError`, `_shouldAbortStreamFallback`) beyond the Netease/Bilibili `_handleDioError`/`_checkResponse` pair.
- The historical scoped AGENTS.md files (`git show e0e6c0c7^:lib/data/AGENTS.md`, `…/sources/AGENTS.md`) contain useful rationale (YouTube auth-per-stream-type order, Bilibili wbi/view) but also stale defaults. Verify any claim against the current code.
