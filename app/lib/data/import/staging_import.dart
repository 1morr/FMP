import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/import/import_bundle.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/data/import/legacy_imports_repository.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/data/repositories/database_inspector.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
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

  /// 重新開啟 [file]，確認它就是 [bundle] 的內容（design §6.2）：筆數、抽樣、完整性、
  /// 孤兒曲目。通過關庫並保留 [file]；不通過刪掉它。
  Future<void> verify(ImportBundle bundle, File file) async {
    AppDatabase? database;
    try {
      database = AppDatabase(NativeDatabase.createInBackground(file));
      final opened = database;
      await _verify(opened, bundle);
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
    final record = bundle.record;
    final importId = await db
        .into(db.legacyImportsTable)
        .insert(
          LegacyImportsTableCompanion.insert(
            source: record.source,
            importedAt: importedAt,
            legacySchemaVersion: Value(record.legacySchemaVersion),
            backupVersion: Value(record.backupVersion),
            summaryJson: record.summary.encode(),
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
      batch.insertAll(db.accountsTable, [
        for (final account in bundle.accounts)
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
      ]);
      batch.insertAll(db.sourceSettingsTable, [
        for (final MapEntry(:key, :value) in bundle.browseAsLoggedIn.entries)
          SourceSettingsTableCompanion.insert(
            pluginId: key,
            browseAsLoggedIn: Value(value),
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
              playerTab: Value(layout.playerTab),
              panelExpanded: Value(layout.panelExpanded),
              panelWidth: Value(layout.panelWidth),
            ),
          );
    }
  }

  // ---- 驗證 ----

  Future<void> _verify(AppDatabase db, ImportBundle bundle) async {
    final inspector = DatabaseInspector(db, Redactor());
    await _verifyCounts(inspector, bundle);

    final trackByKey = {
      for (final track in bundle.tracks) '${track.key}': track,
    };
    await _verifyTracks(db, bundle);
    await _verifyPlaylists(db, bundle, trackByKey);
    await _verifyHistory(db, bundle, trackByKey);
    await _verifyRadio(db, bundle);
    await _verifyQueue(db, bundle, trackByKey);
    await _verifyRecord(db, bundle);

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

  /// 每張表的列數等於 bundle 的筆數；bundle 不會寫的表必須是空的。
  Future<void> _verifyCounts(
    DatabaseInspector inspector,
    ImportBundle bundle,
  ) async {
    final expected = <String, int>{
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
      'radio_stations': bundle.radioStations.length,
      'track_origins': bundle.trackOrigins.length,
      'accounts': bundle.accounts.length,
      'source_settings': bundle.browseAsLoggedIn.length,
      'legacy_imports': 1,
      'appearance_settings': bundle.appearance == AppearanceSettings.empty
          ? 0
          : 1,
      'network_settings': bundle.network == NetworkSettings.empty ? 0 : 1,
      'playback_settings': bundle.playback == PlaybackSettings.empty ? 0 : 1,
      'layout_state': bundle.layout == LayoutState.empty ? 0 : 1,
    };
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

  Future<void> _verifyRecord(AppDatabase db, ImportBundle bundle) async {
    final stored = await LegacyImportsRepository(db).latestUnacknowledged();
    final expected = bundle.record;
    if (stored == null ||
        stored.source != expected.source ||
        stored.legacySchemaVersion != expected.legacySchemaVersion ||
        stored.backupVersion != expected.backupVersion ||
        stored.summary != expected.summary) {
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

/// 驗證沒過；[reason] 是給 [LegacyImportFailed] 的一句話，不含使用者的資料。
final class _Mismatch implements Exception {
  const _Mismatch(this.reason);

  final String reason;
}
