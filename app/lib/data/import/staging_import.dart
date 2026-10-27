import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/import/import_bundle.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/data/import/legacy_imports_repository.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/data/repositories/database_inspector.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/data/repositories/search_history_repository.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/domain/player_mode.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';

/// 把 [ImportBundle] 寫進全新的暫存庫並驗證（M5 design §6.1、§6.2）。換上暫存庫是呼叫端的事。
///
/// 暫存庫放 `<資料目錄>/legacy-import/staging-<UTC>.db`，**不放 `backups/`**：
/// `DatabaseBackups` 一開始會刪掉 `backups/` 裡所有 `staged-` 開頭的檔。
///
/// 不經 repository 寫入：要保留 `created_at`、`updated_at`、`played_at`、`added_at`、
/// `last_refreshed_at` 的原值、批次寫歷史、寫 `playlist_entries.unavailable`，repository
/// 都沒有這些入口。驗證則一律以 repository 讀回，走和 App 一樣的讀取路徑。
///
/// [write] 與 [verify] 任何一步失敗都會關庫、刪掉暫存檔（含 `-wal`、`-shm`），拋
/// [LegacyImportFailed]。
final class StagingImport {
  /// [random] 決定驗證抽哪幾筆；測試給固定種子。[log] 只記清理暫存檔時的失敗。
  StagingImport(this._log, {Random? random}) : _random = random ?? Random();

  static const _tag = 'legacy-import';

  /// 曲目、歌單、歷史、電台各抽幾筆比對；不到就全部。
  static const sampleSize = 50;

  final Log _log;
  final Random _random;

  /// 在 [file] 建全新的資料庫，同一個 transaction 寫完整個 [bundle]、一列 `legacy_imports`
  /// 與 `legacy_playlist_ids`。[importedAt] 是匯入時間（`legacy_imports.imported_at`，也是
  /// 曲目、佇列狀態的 `updated_at`）。[file] 已存在會先刪掉；寫完關庫。
  Future<void> write(
    ImportBundle bundle,
    File file, {
    required DateTime importedAt,
  }) async {
    AppDatabase? database;
    try {
      await _deleteDatabaseFiles(file);
      await file.parent.create(recursive: true);
      database = AppDatabase(NativeDatabase.createInBackground(file));
      final opened = database;
      await opened.transaction(() => _writeAll(opened, bundle, importedAt));
      await opened.close();
    } on Object catch (error) {
      await _discard(file, database);
      throw LegacyImportFailed(
        LegacyImportStep.write,
        'Writing the staging database failed',
        cause: error,
      );
    }
  }

  /// 設定頁的取代（M5 design §6.1 第 2 點、§6.3）：把 [current]（這台目前的資料庫）
  /// `VACUUM INTO` 成 [file]，在副本上換掉音樂庫、合併設定與帳號，同一個 transaction 寫完
  /// [bundle]。[file] 已存在會先刪掉；寫完關庫。
  ///
  /// - 清空 [replacedTables]（音樂庫），再寫 bundle 的曲目、歌單、佇列、歷史、電台；
  /// - 設定組（外觀、網路、播放）只覆寫 bundle 有值的欄位，其餘欄位保留這台的值；
  ///   `source_settings.browse_as_logged_in` 以 bundle 為準，同一列的其他欄位保留；
  ///   `layout_state` 不動（版面只在首次啟動匯入）；
  /// - 帳號：這台有「可用的登入」（有列且 `status` 是 `active`）的插件保留這台的列；其餘寫 bundle 的列
  ///   （`invalidated` 的列被 bundle 的帳號取代，bundle 沒有該插件的帳號就保留原列）；
  /// - 其他的表（插件、插件設定、排行設定、開發者設定、排程）不動，`legacy_imports` 新增一列。
  ///
  /// 回傳的 [ReplacedStaging] 帶 [verify] 要比對的列數，與保留了這台帳號的插件 id。
  Future<ReplacedStaging> writeReplacing(
    ImportBundle bundle,
    File file, {
    required DateTime importedAt,
    required AppDatabase current,
  }) async {
    AppDatabase? database;
    try {
      await _deleteDatabaseFiles(file);
      await file.parent.create(recursive: true);
      await current.customStatement('VACUUM INTO ?', [file.path]);
      database = AppDatabase(NativeDatabase.createInBackground(file));
      final opened = database;
      final result = await opened.transaction(
        () => _replaceAll(opened, bundle, importedAt),
      );
      await opened.close();
      return result;
    } on Object catch (error) {
      await _discard(file, database);
      throw LegacyImportFailed(
        LegacyImportStep.write,
        'Writing the staging database failed',
        cause: error,
      );
    }
  }

  /// 重新開啟 [file]，確認它就是 [bundle] 的內容（design §6.2）：筆數、抽樣、完整性、
  /// 孤兒曲目。通過關庫並保留 [file]；不通過刪掉它。
  ///
  /// 首次啟動的庫是全新的，各表的列數就是 bundle 的筆數；設定頁的取代給 [replaced]
  /// （[writeReplacing] 的結果：列數是 bundle 的筆數加上保留下來的列數）。
  Future<void> verify(
    ImportBundle bundle,
    File file, {
    ReplacedStaging? replaced,
  }) async {
    AppDatabase? database;
    try {
      database = AppDatabase(NativeDatabase.createInBackground(file));
      final opened = database;
      await _verify(
        opened,
        bundle,
        replaced?.expectedCounts ?? _freshCounts(bundle),
        replaced?.summary ?? bundle.record.summary,
      );
      await opened.close();
    } on _Mismatch catch (mismatch) {
      await _discard(file, database);
      throw LegacyImportFailed(LegacyImportStep.verify, mismatch.reason);
    } on Object catch (error) {
      await _discard(file, database);
      throw LegacyImportFailed(
        LegacyImportStep.verify,
        'Reading back the staging database failed',
        cause: error,
      );
    }
  }

  // ---- 寫入 ----

  Future<void> _writeAll(
    AppDatabase db,
    ImportBundle bundle,
    DateTime importedAt,
  ) async {
    await _writeLibrary(db, bundle, importedAt);
    await _writeSettingsFresh(db, bundle);
  }

  /// 音樂庫與這次匯入的紀錄：曲目、歌單、佇列、歷史、電台、`track_origins`、播放狀態、
  /// `legacy_imports`、`legacy_playlist_ids`。首次啟動與設定頁的取代共用。
  Future<void> _writeLibrary(
    AppDatabase db,
    ImportBundle bundle,
    DateTime importedAt, {
    ImportSummary? summary,
  }) async {
    final record = bundle.record;
    final importId = await db
        .into(db.legacyImportsTable)
        .insert(
          LegacyImportsTableCompanion.insert(
            source: record.source,
            importedAt: importedAt,
            legacySchemaVersion: Value(record.legacySchemaVersion),
            backupVersion: Value(record.backupVersion),
            summaryJson: (summary ?? record.summary).encode(),
          ),
        );

    await db.batch(
      (batch) => batch.insertAll(db.tracksTable, [
        for (final track in bundle.tracks)
          TracksTableCompanion.insert(
            trackKey: '${track.key}',
            sourceTypeId: track.sourceTypeId,
            sourceId: track.sourceId,
            cid: Value(track.cid),
            title: track.title,
            uploader: Value(track.uploader),
            durationMs: Value(track.duration?.inMilliseconds),
            partIndex: Value(track.partIndex),
            parentTitle: Value(track.parentTitle),
            artworkJson: Value(TracksRepository.encodeArtwork(track.artwork)),
            updatedAt: importedAt,
          ),
      ]),
    );

    for (final (index, playlist) in bundle.playlists.indexed) {
      final playlistId = await db
          .into(db.playlistsTable)
          .insert(
            PlaylistsTableCompanion.insert(
              kind: playlist.kind,
              name: playlist.name,
              description: Value(playlist.description),
              artworkJson: Value(
                TracksRepository.encodeArtwork(playlist.artwork),
              ),
              sortOrder: index,
              createdAt: playlist.createdAt,
              updatedAt: playlist.updatedAt,
              mixPluginId: Value(playlist.mixPluginId),
              mixSeedSourceId: Value(playlist.mixSeedSourceId),
              mixSeedCid: Value(playlist.mixSeedCid),
            ),
          );
      if (playlist.remote case final remote?) {
        await db
            .into(db.playlistRemoteTable)
            .insert(
              PlaylistRemoteTableCompanion.insert(
                playlistId: Value(playlistId),
                pluginId: remote.pluginId,
                remoteId: remote.remoteId,
                ownerName: Value(remote.ownerName),
                writable: Value(remote.writable),
                artworkOverridden: Value(remote.artworkOverridden),
                refreshIntervalHours: Value(remote.refreshIntervalHours),
                lastRefreshedAt: Value(remote.lastRefreshedAt),
              ),
            );
      }
      if (playlist.entries.isNotEmpty) {
        await db.batch(
          (batch) => batch.insertAll(db.playlistEntriesTable, [
            for (final (position, entry) in playlist.entries.indexed)
              PlaylistEntriesTableCompanion.insert(
                playlistId: playlistId,
                position: position,
                trackKey: '${entry.track}',
                unavailable: Value(entry.unavailable),
              ),
          ]),
        );
      }
      if (playlist.legacyPlaylistId case final legacyId?) {
        await db
            .into(db.legacyPlaylistIdsTable)
            .insert(
              LegacyPlaylistIdsTableCompanion.insert(
                legacyImportId: importId,
                legacyPlaylistId: legacyId,
                playlistId: playlistId,
              ),
            );
      }
    }

    await db.batch((batch) {
      batch.insertAll(db.queueEntriesTable, [
        for (final (position, entry) in bundle.queue.indexed)
          QueueEntriesTableCompanion.insert(
            position: Value(position),
            trackKey: '${entry.track}',
            shuffleRank: Value(entry.shuffleRank),
          ),
      ]);
      // 歷史依清單順序寫入：id 遞增，同一毫秒的以後寫的為新。
      batch.insertAll(db.playHistoryTable, [
        for (final entry in bundle.history)
          PlayHistoryTableCompanion.insert(
            trackKey: '${entry.track}',
            playedAt: entry.playedAt,
          ),
      ]);
      batch.insertAll(db.searchHistoryTable, [
        for (final entry in bundle.searchHistory)
          SearchHistoryTableCompanion.insert(
            query: entry.query,
            searchedAt: entry.searchedAt,
          ),
      ]);
      batch.insertAll(db.radioStationsTable, [
        for (final (index, station) in bundle.radioStations.indexed)
          RadioStationsTableCompanion.insert(
            pluginId: station.pluginId,
            roomId: station.roomId,
            title: station.title,
            hostName: Value(station.hostName),
            artworkJson: Value(TracksRepository.encodeArtwork(station.artwork)),
            sortOrder: index,
            addedAt: station.addedAt,
          ),
      ]);
      batch.insertAll(db.trackOriginsTable, [
        for (final origin in bundle.trackOrigins)
          TrackOriginsTableCompanion.insert(
            trackKey: '${origin.track}',
            originPluginId: origin.originPluginId,
            originId: origin.originId,
          ),
      ]);
    });

    if (bundle.playerState case final player?) {
      await db
          .into(db.playerStateTable)
          .insert(
            PlayerStateTableCompanion.insert(
              id: const Value(1),
              currentPosition: Value(player.currentPosition),
              positionMs: player.position.inMilliseconds,
              loopMode: player.loopMode,
              shuffleEnabled: player.shuffleEnabled,
              volume: player.volume,
              muted: player.muted,
              mode: Value(
                player.mix == null ? PlayerMode.queue : PlayerMode.mix,
              ),
              mixPluginId: Value(player.mix?.pluginId),
              mixId: Value(player.mix?.mixId),
              mixTitle: Value(player.mix?.title),
              mixCursor: Value(player.mix?.cursor),
              updatedAt: importedAt,
            ),
          );
    }
  }

  /// 帳號、設定組與版面（全新的庫）。
  Future<void> _writeSettingsFresh(AppDatabase db, ImportBundle bundle) async {
    await _insertAccounts(db, bundle.accounts);
    await db.batch(
      (batch) => batch.insertAll(db.sourceSettingsTable, [
        for (final MapEntry(:key, :value) in bundle.browseAsLoggedIn.entries)
          SourceSettingsTableCompanion.insert(
            pluginId: key,
            browseAsLoggedIn: Value(value),
          ),
      ]),
    );

    // 設定組：整組都是空的就不建那一列（沒設定過）。
    final appearance = bundle.appearance;
    if (appearance != AppearanceSettings.empty) {
      await db
          .into(db.appearanceSettingsTable)
          .insert(
            AppearanceSettingsTableCompanion.insert(
              id: const Value(1),
              themeMode: Value(appearance.themeMode),
              locale: Value(appearance.locale),
              seedColor: Value(
                appearance.seedColor == null
                    ? null
                    : storedSeedColor(appearance.seedColor!),
              ),
              fontFamily: Value(appearance.fontFamily),
            ),
          );
    }
    final network = bundle.network;
    if (network != NetworkSettings.empty) {
      await db
          .into(db.networkSettingsTable)
          .insert(
            NetworkSettingsTableCompanion.insert(
              id: const Value(1),
              cacheLimitMb: Value(network.cacheLimitMebibytes),
              radioStatusIntervalMinutes: Value(
                network.radioStatusIntervalMinutes,
              ),
              chartRefreshIntervalMinutes: Value(
                network.chartRefreshIntervalMinutes,
              ),
            ),
          );
    }
    final playback = bundle.playback;
    if (playback != PlaybackSettings.empty) {
      await db
          .into(db.playbackSettingsTable)
          .insert(
            PlaybackSettingsTableCompanion.insert(
              id: const Value(1),
              audioQuality: Value(playback.audioQuality),
              audioFormatPriority: Value(playback.audioFormatPriority),
              rememberPosition: Value(playback.rememberPosition),
              tempPlayRewindSeconds: Value(playback.tempPlayRewindSeconds),
              skipPreviewClips: Value(playback.skipPreviewClips),
              outputDeviceId: Value(playback.outputDeviceId),
              outputDeviceName: Value(playback.outputDeviceName),
              restartRewindSeconds: Value(playback.restartRewindSeconds),
              playHistoryLimit: Value(playback.playHistoryLimit),
              autoScrollToCurrent: Value(playback.autoScrollToCurrent),
            ),
          );
    }
    final layout = bundle.layout;
    if (layout != LayoutState.empty) {
      await db
          .into(db.layoutStateTable)
          .insert(
            LayoutStateTableCompanion.insert(
              id: const Value(1),
              panelExpanded: Value(layout.panelExpanded),
              panelWidth: Value(layout.panelWidth),
              railExpanded: Value(layout.railExpanded),
            ),
          );
    }
  }

  Future<void> _insertAccounts(AppDatabase db, List<Account> accounts) =>
      db.batch(
        (batch) => batch.insertAll(db.accountsTable, [
          for (final account in accounts)
            AccountsTableCompanion.insert(
              pluginId: account.pluginId,
              userId: account.userId,
              displayName: account.displayName,
              avatarJson: Value(account.avatarJson),
              status: account.status,
              loggedInAt: account.loggedInAt,
              lastRefreshAt: Value(account.lastRefreshAt),
              lastRefreshResult: Value(account.lastRefreshResult),
            ),
        ]),
      );

  // ---- 設定頁的取代 ----

  /// 設定頁的取代要清空的表（音樂庫），依外鍵的順序：參照別張表的先清。
  static const replacedTables = [
    'playlist_entries',
    'playlist_remote',
    'legacy_playlist_ids',
    'match_results',
    'track_origins',
    'play_history',
    'search_history',
    'queue_entries',
    'player_state',
    'radio_stations',
    'playlists',
    'tracks',
  ];

  Future<ReplacedStaging> _replaceAll(
    AppDatabase db,
    ImportBundle bundle,
    DateTime importedAt,
  ) async {
    final before = {
      for (final (:name, :count) in await DatabaseInspector(
        db,
        Redactor(),
      ).tables())
        name: count,
    };
    for (final table in replacedTables) {
      await db.customStatement('DELETE FROM "$table"');
    }

    // 帳號：這台有可用登入（列在、`status` 是 `active`）的插件保留這台的列（憑證也是這台的）；
    // 其餘寫匯入的列，`invalidated` 的列先刪掉被取代，匯入沒有該插件的帳號就留著原列。
    final existingAccounts = {
      for (final row in await db.select(db.accountsTable).get())
        row.pluginId: row.status,
    };
    final keptAccounts = {
      for (final MapEntry(:key, :value) in existingAccounts.entries)
        if (value == AccountStatus.active) key,
    };
    final newAccounts = [
      for (final account in bundle.accounts)
        if (!keptAccounts.contains(account.pluginId)) account,
    ];
    final replacedAccounts = newAccounts
        .where((account) => existingAccounts.containsKey(account.pluginId))
        .map((account) => account.pluginId)
        .toList();
    await (db.delete(
      db.accountsTable,
    )..where((t) => t.pluginId.isIn(replacedAccounts))).go();
    final summary = _withoutKeptAccounts(
      bundle.record.summary,
      keptAccounts,
      bundle.accounts.length - newAccounts.length,
    );
    await _writeLibrary(db, bundle, importedAt, summary: summary);
    await _insertAccounts(db, newAccounts);

    // `browse_as_logged_in` 以匯入值為準；同一列的匹配設定等欄位保留。
    final knownSources = {
      for (final row in await db.select(db.sourceSettingsTable).get())
        row.pluginId,
    };
    for (final MapEntry(:key, :value) in bundle.browseAsLoggedIn.entries) {
      await db
          .into(db.sourceSettingsTable)
          .insertOnConflictUpdate(
            SourceSettingsTableCompanion(
              pluginId: Value(key),
              browseAsLoggedIn: Value(value),
            ),
          );
    }

    // 設定組：只覆寫匯入有值的欄位。
    final appearance = bundle.appearance;
    if (appearance != AppearanceSettings.empty) {
      await db
          .into(db.appearanceSettingsTable)
          .insertOnConflictUpdate(
            AppearanceSettingsTableCompanion(
              id: const Value(1),
              themeMode: Value.absentIfNull(appearance.themeMode),
              locale: Value.absentIfNull(appearance.locale),
              seedColor: Value.absentIfNull(
                appearance.seedColor == null
                    ? null
                    : storedSeedColor(appearance.seedColor!),
              ),
              fontFamily: Value.absentIfNull(appearance.fontFamily),
            ),
          );
    }
    final network = bundle.network;
    if (network != NetworkSettings.empty) {
      await db
          .into(db.networkSettingsTable)
          .insertOnConflictUpdate(
            NetworkSettingsTableCompanion(
              id: const Value(1),
              cacheLimitMb: Value.absentIfNull(network.cacheLimitMebibytes),
              radioStatusIntervalMinutes: Value.absentIfNull(
                network.radioStatusIntervalMinutes,
              ),
              chartRefreshIntervalMinutes: Value.absentIfNull(
                network.chartRefreshIntervalMinutes,
              ),
            ),
          );
    }
    final playback = bundle.playback;
    if (playback != PlaybackSettings.empty) {
      await db
          .into(db.playbackSettingsTable)
          .insertOnConflictUpdate(
            PlaybackSettingsTableCompanion(
              id: const Value(1),
              audioQuality: Value.absentIfNull(playback.audioQuality),
              audioFormatPriority: Value.absentIfNull(
                playback.audioFormatPriority,
              ),
              rememberPosition: Value.absentIfNull(playback.rememberPosition),
              tempPlayRewindSeconds: Value.absentIfNull(
                playback.tempPlayRewindSeconds,
              ),
              skipPreviewClips: Value.absentIfNull(playback.skipPreviewClips),
              outputDeviceId: Value.absentIfNull(playback.outputDeviceId),
              outputDeviceName: Value.absentIfNull(playback.outputDeviceName),
              restartRewindSeconds: Value.absentIfNull(
                playback.restartRewindSeconds,
              ),
              playHistoryLimit: Value.absentIfNull(playback.playHistoryLimit),
              autoScrollToCurrent: Value.absentIfNull(
                playback.autoScrollToCurrent,
              ),
            ),
          );
    }

    // 驗證要比對的列數：被取代的表是 bundle 的筆數，其餘是原有的列數加上這次新增的。
    final expected = _libraryCounts(bundle);
    for (final MapEntry(:key, :value) in before.entries) {
      if (replacedTables.contains(key)) continue;
      expected[key] = (expected[key] ?? 0) + value;
    }
    expected['accounts'] =
        before['accounts']! + newAccounts.length - replacedAccounts.length;
    expected['source_settings'] =
        before['source_settings']! +
        bundle.browseAsLoggedIn.keys
            .where((id) => !knownSources.contains(id))
            .length;
    for (final (table, isEmpty) in [
      ('appearance_settings', appearance == AppearanceSettings.empty),
      ('network_settings', network == NetworkSettings.empty),
      ('playback_settings', playback == PlaybackSettings.empty),
    ]) {
      // 單列表：原本沒有列、而匯入有值時新增一列。
      if (!isEmpty && before[table] == 0) expected[table] = 1;
    }
    return ReplacedStaging(
      expectedCounts: expected,
      keptAccountPluginIds: keptAccounts,
      summary: summary,
    );
  }

  /// `ImportSummary.collections` 裡帳號的鍵（轉換器的 `SummaryCollection.accounts`；資料層不能
  /// import 封住的 `lib/legacy_import/`，字面值由 `staging_import_test.dart` 的取代案例對照）。
  static const _accountsCollection = 'accounts';

  /// 這台有可用登入（`active`）的平台沒有寫匯入的列：摘要的帳號筆數扣掉 [skipped] 筆（計成略過，理由
  /// `keptOnThisDevice`），也不說要重新登入（這台的登入還在）。
  static ImportSummary _withoutKeptAccounts(
    ImportSummary summary,
    Set<String> kept,
    int skipped,
  ) {
    final accounts = summary.collections[_accountsCollection];
    return ImportSummary(
      collections: {
        ...summary.collections,
        if (accounts != null && skipped > 0)
          _accountsCollection: CollectionSummary(
            read: accounts.read,
            written: accounts.written - skipped,
            skipped: {...accounts.skipped, 'keptOnThisDevice': skipped},
            notes: accounts.notes,
          ),
      },
      unimportedSettings: summary.unimportedSettings,
      reloginPlatforms: [
        for (final id in summary.reloginPlatforms)
          if (!kept.contains(id)) id,
      ],
    );
  }

  // ---- 驗證 ----

  Future<void> _verify(
    AppDatabase db,
    ImportBundle bundle,
    Map<String, int> expectedCounts,
    ImportSummary expectedSummary,
  ) async {
    final inspector = DatabaseInspector(db, Redactor());
    await _verifyCounts(inspector, expectedCounts);

    final trackByKey = {
      for (final track in bundle.tracks) '${track.key}': track,
    };
    await _verifyTracks(db, bundle);
    await _verifyPlaylists(db, bundle, trackByKey);
    await _verifyHistory(db, bundle, trackByKey);
    await _verifySearchHistory(db, bundle);
    await _verifyRadio(db, bundle);
    await _verifyQueue(db, bundle, trackByKey);
    await _verifyRecord(db, bundle, expectedSummary);

    final report = await inspector.check();
    if (report.integrityMessages.isNotEmpty) {
      throw const _Mismatch('The integrity check failed');
    }
    if (report.foreignKeyViolations.isNotEmpty) {
      throw const _Mismatch('The foreign key check failed');
    }
    if (report.orphanTracks != 0) {
      throw const _Mismatch('The staging database has orphan tracks');
    }
  }

  /// 全新的庫：各表的列數就是 bundle 的筆數；bundle 不會寫的表必須是空的。
  static Map<String, int> _freshCounts(ImportBundle bundle) => {
    ..._libraryCounts(bundle),
    'accounts': bundle.accounts.length,
    'source_settings': bundle.browseAsLoggedIn.length,
    'appearance_settings': bundle.appearance == AppearanceSettings.empty
        ? 0
        : 1,
    'network_settings': bundle.network == NetworkSettings.empty ? 0 : 1,
    'playback_settings': bundle.playback == PlaybackSettings.empty ? 0 : 1,
    'layout_state': bundle.layout == LayoutState.empty ? 0 : 1,
  };

  /// [_writeLibrary] 寫的表的列數。
  static Map<String, int> _libraryCounts(ImportBundle bundle) => {
    'tracks': bundle.tracks.length,
    'playlists': bundle.playlists.length,
    'playlist_remote': bundle.playlists.where((p) => p.remote != null).length,
    'playlist_entries': bundle.playlists.fold(
      0,
      (sum, playlist) => sum + playlist.entries.length,
    ),
    'legacy_playlist_ids': bundle.playlists
        .where((p) => p.legacyPlaylistId != null)
        .length,
    'queue_entries': bundle.queue.length,
    'player_state': bundle.playerState == null ? 0 : 1,
    'play_history': bundle.history.length,
    'search_history': bundle.searchHistory.length,
    'radio_stations': bundle.radioStations.length,
    'track_origins': bundle.trackOrigins.length,
    'legacy_imports': 1,
  };

  /// 每張表的列數等於 [expected]；沒列在裡面的表必須是空的。
  Future<void> _verifyCounts(
    DatabaseInspector inspector,
    Map<String, int> expected,
  ) async {
    for (final (:name, :count) in await inspector.tables()) {
      if (count != (expected[name] ?? 0)) {
        throw _Mismatch('Row count mismatch in table $name');
      }
    }
  }

  Future<void> _verifyTracks(AppDatabase db, ImportBundle bundle) async {
    final sample = [
      for (final index in _sample(bundle.tracks.length)) bundle.tracks[index],
    ];
    final found = await TracksRepository(db)
        .find([for (final track in sample) '${track.key}']);
    for (final track in sample) {
      if (found['${track.key}'] != track) {
        throw const _Mismatch('A sampled track does not match the bundle');
      }
    }
  }

  Future<void> _verifyPlaylists(
    AppDatabase db,
    ImportBundle bundle,
    Map<String, TrackInfo> trackByKey,
  ) async {
    final repository = PlaylistRepository(db);
    // 依（sort_order, id）＝bundle 的順序。
    final overviews = await repository.overviews();
    if (overviews.length != bundle.playlists.length) {
      throw const _Mismatch('Playlist count mismatch');
    }
    for (final index in _sample(bundle.playlists.length)) {
      final expected = bundle.playlists[index];
      final overview = overviews[index];
      final actual = overview.playlist;
      if (actual.kind != expected.kind ||
          actual.name != expected.name ||
          actual.description != expected.description ||
          !_sameArtwork(actual.artwork, expected.artwork) ||
          actual.sortOrder != index ||
          _ms(actual.createdAt) != _ms(expected.createdAt) ||
          _ms(actual.updatedAt) != _ms(expected.updatedAt) ||
          actual.mixPluginId != expected.mixPluginId ||
          actual.mixSeedSourceId != expected.mixSeedSourceId ||
          actual.mixSeedCid != expected.mixSeedCid ||
          overview.trackCount != expected.entries.length) {
        throw const _Mismatch('A sampled playlist does not match the bundle');
      }

      final remote = await repository.remote(actual.id);
      final expectedRemote = expected.remote;
      if (expectedRemote == null) {
        if (remote != null) {
          throw const _Mismatch(
            'A sampled playlist has unexpected remote data',
          );
        }
      } else if (remote == null ||
          remote.pluginId != expectedRemote.pluginId ||
          remote.remoteId != expectedRemote.remoteId ||
          remote.ownerName != expectedRemote.ownerName ||
          remote.writable != expectedRemote.writable ||
          remote.artworkOverridden != expectedRemote.artworkOverridden ||
          remote.nameOverridden ||
          remote.descriptionOverridden ||
          remote.refreshIntervalHours != expectedRemote.refreshIntervalHours ||
          _ms(remote.lastRefreshedAt) != _ms(expectedRemote.lastRefreshedAt) ||
          remote.lastResult != null ||
          remote.status != PlaylistRemoteStatus.active ||
          remote.refreshGeneration != 0) {
        throw const _Mismatch(
          'A sampled playlist remote does not match the bundle',
        );
      }

      final entries = await repository.entries(actual.id);
      if (entries.length != expected.entries.length) {
        throw const _Mismatch('A sampled playlist has the wrong entry count');
      }
      for (final (position, entry) in entries.indexed) {
        final expectedEntry = expected.entries[position];
        if (entry.position != position ||
            entry.track != trackByKey['${expectedEntry.track}'] ||
            entry.unavailable != expectedEntry.unavailable ||
            entry.remoteItemId != null) {
          throw const _Mismatch(
            'A sampled playlist entry does not match the bundle',
          );
        }
      }
    }
  }

  Future<void> _verifyHistory(
    AppDatabase db,
    ImportBundle bundle,
    Map<String, TrackInfo> trackByKey,
  ) async {
    // `page` 的順序是 played_at 由新到舊、同時間 id 由大到小；id 是寫入順序。
    final newestFirst = List<int>.generate(bundle.history.length, (i) => i)
      ..sort((a, b) {
        final byTime = bundle.history[b].playedAt.millisecondsSinceEpoch
            .compareTo(bundle.history[a].playedAt.millisecondsSinceEpoch);
        return byTime != 0 ? byTime : b.compareTo(a);
      });
    final repository = PlayHistoryRepository(db);
    for (final offset in _sample(bundle.history.length)) {
      final expected = bundle.history[newestFirst[offset]];
      final page = await repository.page(limit: 1, offset: offset);
      if (page.length != 1 ||
          page.single.track != trackByKey['${expected.track}'] ||
          _ms(page.single.playedAt) != _ms(expected.playedAt)) {
        throw const _Mismatch(
          'A sampled history entry does not match the bundle',
        );
      }
    }
  }

  Future<void> _verifyRadio(AppDatabase db, ImportBundle bundle) async {
    // 依（sort_order, id）＝bundle 的順序。
    final stations = await RadioRepository(db).list();
    if (stations.length != bundle.radioStations.length) {
      throw const _Mismatch('Radio station count mismatch');
    }
    for (final index in _sample(bundle.radioStations.length)) {
      final expected = bundle.radioStations[index];
      final actual = stations[index];
      if (actual.pluginId != expected.pluginId ||
          actual.roomId != expected.roomId ||
          actual.title != expected.title ||
          actual.hostName != expected.hostName ||
          !_sameArtwork(actual.artwork, expected.artwork) ||
          actual.sortOrder != index ||
          _ms(actual.addedAt) != _ms(expected.addedAt) ||
          actual.liveStatus != null ||
          actual.liveTitle != null ||
          actual.statusCheckedAt != null) {
        throw const _Mismatch(
          'A sampled radio station does not match the bundle',
        );
      }
    }
  }

  /// 搜尋歷史最多 50 筆，整份比對（讀回是最新的在前）。
  Future<void> _verifySearchHistory(AppDatabase db, ImportBundle bundle) async {
    final stored = await SearchHistoryRepository(db).list();
    final expected = [...bundle.searchHistory]
      ..sort((a, b) {
        final byTime = b.searchedAt.millisecondsSinceEpoch.compareTo(
          a.searchedAt.millisecondsSinceEpoch,
        );
        return byTime != 0 ? byTime : a.query.compareTo(b.query);
      });
    if (stored.length != expected.length) {
      throw const _Mismatch('Search history length mismatch');
    }
    for (final (index, entry) in expected.indexed) {
      if (stored[index].query != entry.query ||
          _ms(stored[index].searchedAt) != _ms(entry.searchedAt)) {
        throw const _Mismatch('The search history does not match the bundle');
      }
    }
  }

  /// 佇列和播放狀態整份比對（一萬首的佇列是一次 join 讀回，很快）。
  Future<void> _verifyQueue(
    AppDatabase db,
    ImportBundle bundle,
    Map<String, TrackInfo> trackByKey,
  ) async {
    final repository = QueueRepository(db);
    final stored = await repository.readQueue();
    if (stored.entries.length != bundle.queue.length) {
      throw const _Mismatch('Queue length mismatch');
    }
    for (final (position, entry) in bundle.queue.indexed) {
      if (stored.entries[position] != trackByKey['${entry.track}'] ||
          stored.shuffleRanks[position] != entry.shuffleRank) {
        throw const _Mismatch('The queue does not match the bundle');
      }
    }
    if (await repository.readPlayerState() != bundle.playerState) {
      throw const _Mismatch('The player state does not match the bundle');
    }
  }

  Future<void> _verifyRecord(
    AppDatabase db,
    ImportBundle bundle,
    ImportSummary expectedSummary,
  ) async {
    final stored = await LegacyImportsRepository(db).latestUnacknowledged();
    final expected = bundle.record;
    if (stored == null ||
        stored.source != expected.source ||
        stored.legacySchemaVersion != expected.legacySchemaVersion ||
        stored.backupVersion != expected.backupVersion ||
        stored.summary != expectedSummary) {
      throw const _Mismatch('The import record does not match the bundle');
    }
  }

  /// 隨機抽 [sampleSize] 個 [0, length) 的位置（不到就全部），由小到大。
  List<int> _sample(int length) {
    final indexes = List<int>.generate(length, (i) => i);
    if (length > sampleSize) {
      indexes.shuffle(_random);
      return indexes.sublist(0, sampleSize)..sort();
    }
    return indexes;
  }

  static int? _ms(DateTime? time) => time?.millisecondsSinceEpoch;

  static bool _sameArtwork(List<TrackArtwork> a, List<TrackArtwork> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---- 清理 ----

  /// 關庫（關不掉也無妨）並刪暫存檔。
  Future<void> _discard(File file, AppDatabase? database) async {
    try {
      await database?.close();
    } on Object catch (error, stackTrace) {
      // 已經在失敗的路上：關不掉不改變結果，檔案照刪；原本的錯誤比較重要，這裡只記下來。
      _log.warning(
        'Failed to close the staging database',
        tag: _tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
    await _deleteDatabaseFiles(file);
  }

  Future<void> _deleteDatabaseFiles(File file) async {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final target = File('${file.path}$suffix');
      try {
        if (target.existsSync()) await target.delete();
      } on FileSystemException catch (error, stackTrace) {
        // 刪不掉（被占用）就留著：呼叫端啟動時會清 `legacy-import/`。
        _log.warning(
          'Failed to delete a staging database file',
          tag: _tag,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }
}

/// [StagingImport.writeReplacing] 的結果。
@immutable
final class ReplacedStaging {
  const ReplacedStaging({
    required this.expectedCounts,
    required this.keptAccountPluginIds,
    required this.summary,
  });

  /// 每張表應有的列數，給 [StagingImport.verify]：被取代的表是匯入包的筆數，其餘是這台
  /// 原有的列數加上這次新增的。
  final Map<String, int> expectedCounts;

  /// 這台有可用登入（帳號列的 `status` 是 `active`）、所以保留這台的列的插件 id：匯入的這些平台的
  /// 帳號與憑證都不寫。`invalidated` 的列不算：匯入有該平台的帳號就取代它（憑證也由匯入的覆寫）。
  final Set<String> keptAccountPluginIds;

  /// 寫進 `legacy_imports` 的摘要：匯入包的摘要扣掉沒寫的帳號。
  final ImportSummary summary;
}

/// 驗證沒過；[reason] 是給 [LegacyImportFailed] 的一句話，不含使用者的資料。
final class _Mismatch implements Exception {
  const _Mismatch(this.reason);

  final String reason;
}
