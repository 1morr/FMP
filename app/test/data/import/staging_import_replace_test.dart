import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/import/import_bundle.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/data/import/legacy_imports_repository.dart';
import 'package:fmp/data/import/staging_import.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/search_history_repository.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/legacy_import/legacy_converter.dart';
import 'package:path/path.dart' as p;

import '../../support/memory_database.dart';
import 'import_fixtures.dart';

// 設定頁的取代（M5 design §6.1 第 2 點、§6.3、§9「設定頁的取代」）：`writeReplacing` 在目前資料庫的
// 副本上換掉音樂庫、合併設定與帳號，保留插件、插件設定、排行設定；`verify` 把保留下來的列數算進去。

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;
  late File staging;
  late AppDatabase current;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('fmp_staging_replace_');
    staging = File(p.join(directory.path, 'legacy-import', 'staging-test.db'));
    current = memoryDatabase();
    addTearDown(() => directory.deleteSync(recursive: true));
  });

  StagingImport stager() => StagingImport(
    Log(redactor: Redactor(), minimumLevel: LogLevel.warning),
    random: Random(1),
  );

  Future<AppDatabase> openStaging() async {
    final database = AppDatabase(NativeDatabase(staging));
    addTearDown(database.close);
    return database;
  }

  Future<int> count(AppDatabase database, String table) async =>
      (await database
              .customSelect('SELECT COUNT(*) AS n FROM $table')
              .getSingle())
          .read<int>('n');

  /// 這台目前的資料：舊的音樂庫、兩個插件相關的列、各種設定與兩個帳號。
  Future<void> seedCurrent() async {
    // 這台原有的音樂庫：全部會被取代。
    final old = track('OLD1');
    final playlists = PlaylistRepository(current);
    final playlistId = await playlists.create(name: 'Old list');
    await playlists.addTracks(playlistId, [old]);
    await QueueRepository(current).write(
      edit: QueueRangeEdit(from: 0, removed: 0, inserted: [old]),
      player: const PlayerState(
        currentPosition: 0,
        position: Duration.zero,
        loopMode: LoopMode.off,
        shuffleEnabled: false,
        volume: 1,
        muted: false,
      ),
    );
    await PlayHistoryRepository(current)
        .record(old, playedAt: at(1), limit: 100);
    await SearchHistoryRepository(current).record('old query');
    await RadioRepository(current).add(
      pluginId: 'bilibili',
      roomId: 'old-room',
      title: 'Old room',
      addedAt: at(1),
    );

    // 保留的：插件、插件設定、排行設定、開發者設定、排程、版面、匹配設定。
    for (final sql in [
      "INSERT INTO installed_plugins (id, version, manifest_json, script, "
          "installed_at) VALUES ('keep-plugin', '1.0.0', '{}', '//', 1000)",
      "INSERT INTO plugin_storage (plugin_id, key, value) "
          "VALUES ('keep-plugin', 'k', 'v')",
      "INSERT INTO plugin_indexes (url, added_at) "
          "VALUES ('https://index.example.test/', 1000)",
      "INSERT INTO chart_settings (plugin_id, chart_id, enabled, sort_order) "
          "VALUES ('keep-plugin', 'c1', 0, 4)",
      "INSERT INTO developer_settings (id, developer_mode) VALUES (1, 1)",
      "INSERT INTO scheduler_runs (job_id, last_success_at) "
          "VALUES ('job', 2000)",
      // 同一列有匯入要覆寫的 browse_as_logged_in，與要保留的匹配設定。
      "INSERT INTO source_settings (plugin_id, browse_as_logged_in, "
          "match_target, match_rank) VALUES ('bilibili', 0, 1, 2)",
      "INSERT INTO source_settings (plugin_id, match_target) "
          "VALUES ('netease', 0)",
      // 之前匯入過一次的紀錄：保留，另外新增一列。
      "INSERT INTO legacy_imports (source, imported_at, summary_json, "
          "acknowledged) VALUES ('database', 1000, '${const ImportSummary().encode()}', 1)",
    ]) {
      await current.customStatement(sql);
    }
    await LayoutStateRepository(current)
        .write(panelExpanded: true, panelWidth: 300);
    await AppearanceSettingsRepository(current)
        .write(themeMode: ThemeModeSetting.light, locale: LocaleSetting.en);
    await NetworkSettingsRepository(current)
        .write(radioStatusIntervalMinutes: 3, chartRefreshIntervalMinutes: 7);
    await PlaybackSettingsRepository(current).write(
      outputDeviceId: 'device-1',
      outputDeviceName: 'Speakers',
      playHistoryLimit: 100,
      rememberPosition: true,
    );
    final accounts = AccountRepository(current);
    for (final (plugin, user) in [
      ('bilibili', 'mine-b'),
      ('netease', 'mine-n'),
    ]) {
      await accounts.upsert(
        Account(
          pluginId: plugin,
          userId: user,
          displayName: 'This device $plugin',
          status: AccountStatus.active,
          loggedInAt: at(40),
        ),
      );
    }
  }

  /// [fullBundle] 的帳號換成 bilibili 與 youtube 兩個，摘要記著兩個都寫。
  ImportBundle bundleWithAccounts() {
    final base = fullBundle();
    Account imported(String plugin, String user) => Account(
      pluginId: plugin,
      userId: user,
      displayName: 'Imported $plugin',
      status: AccountStatus.active,
      loggedInAt: at(30),
    );
    return ImportBundle(
      record: ImportRecord(
        source: base.record.source,
        legacySchemaVersion: base.record.legacySchemaVersion,
        summary: const ImportSummary(
          collections: {'accounts': CollectionSummary(read: 2, written: 2)},
          reloginPlatforms: ['bilibili', 'youtube'],
        ),
      ),
      tracks: base.tracks,
      playlists: base.playlists,
      queue: base.queue,
      playerState: base.playerState,
      history: base.history,
      searchHistory: base.searchHistory,
      radioStations: base.radioStations,
      trackOrigins: base.trackOrigins,
      accounts: [imported('bilibili', 'imported-b'), imported('youtube', 'y')],
      appearance: base.appearance,
      network: base.network,
      playback: base.playback,
      browseAsLoggedIn: base.browseAsLoggedIn,
      layout: base.layout,
    );
  }

  Future<ReplacedStaging> replace(ImportBundle bundle) async {
    final replaced = await stager().writeReplacing(
      bundle,
      staging,
      importedAt: importedAt,
      current: current,
    );
    await stager().verify(bundle, staging, replaced: replaced);
    return replaced;
  }

  // 加表時要決定：隨匯入取代（`StagingImport.replacedTables`），還是保留這台的（這裡的清單）。
  // 沒歸類的新表在取代時預設被保留：參照 `tracks` 的會讓清空失敗（RESTRICT），不參照的會把這台的
  // 舊資料留在換上的庫裡。
  test('table classification gate: every table is replaced or kept', () {
    const kept = {
      // 合併：只覆寫匯入有值的欄位，或只補這台沒有的列。
      'accounts',
      'source_settings',
      'appearance_settings',
      'network_settings',
      'playback_settings',
      // 不動（`legacy_imports` 另新增一列）。
      'layout_state',
      'installed_plugins',
      'plugin_storage',
      'plugin_indexes',
      'chart_settings',
      'developer_settings',
      'scheduler_runs',
      'legacy_imports',
    };
    final replaced = StagingImport.replacedTables.toSet();
    expect(replaced.intersection(kept), isEmpty);
    expect(replaced, hasLength(StagingImport.replacedTables.length));
    expect(
      {...replaced, ...kept},
      {for (final table in current.allTables) table.actualTableName},
    );
  });

  test('replaces the library and keeps plugins, plugin settings and '
      'chart settings', () async {
    await seedCurrent();
    final bundle = bundleWithAccounts();
    await replace(bundle);

    final database = await openStaging();
    // 音樂庫是匯入包的，這台原有的不見了。
    final overviews = await PlaylistRepository(database).overviews();
    expect(
      [for (final o in overviews) o.playlist.name],
      ['Local list', 'Imported list', 'Mix list'],
    );
    final tracks = await database
        .customSelect('SELECT track_key FROM tracks')
        .get();
    expect([
      for (final row in tracks) row.read<String>('track_key'),
    ], isNot(contains(contains('OLD1'))));
    expect(await count(database, 'tracks'), bundle.tracks.length);
    final queue = await QueueRepository(database).readQueue();
    expect(
      [for (final t in queue.entries) t.sourceId],
      ['dQw4w9WgXcQ', 'BV1a'],
    );
    expect(
      await QueueRepository(database).readPlayerState(),
      bundle.playerState,
    );
    expect(await count(database, 'play_history'), bundle.history.length);
    expect(
      [for (final e in await SearchHistoryRepository(database).list()) e.query],
      ['jazz', 'lofi'],
    );
    expect(
      [for (final s in await RadioRepository(database).list()) s.roomId],
      ['99', 'live1'],
    );

    // 保留的表一列都沒少。
    expect(await count(database, 'installed_plugins'), 1);
    expect(await count(database, 'plugin_storage'), 1);
    expect(await count(database, 'plugin_indexes'), 1);
    expect(await count(database, 'chart_settings'), 1);
    expect(await count(database, 'scheduler_runs'), 1);
    final chart = await database
        .customSelect('SELECT enabled, sort_order FROM chart_settings')
        .getSingle();
    expect(chart.read<int>('enabled'), 0);
    expect(chart.read<int>('sort_order'), 4);
    final developer = await database
        .customSelect('SELECT developer_mode FROM developer_settings')
        .getSingle();
    expect(developer.read<int>('developer_mode'), 1);
  });

  test('settings: only the imported fields overwrite; layout stays; '
      'browse_as_logged_in follows the import', () async {
    await seedCurrent();
    await replace(bundleWithAccounts());

    final database = await openStaging();
    // 匯入有值的欄位覆寫，其餘保留這台的。
    expect(
      await AppearanceSettingsRepository(database).read(),
      fullBundle().appearance,
    );
    final network = await NetworkSettingsRepository(database).read();
    expect(network.radioStatusIntervalMinutes, 10); // 匯入的
    expect(network.chartRefreshIntervalMinutes, 7); // 這台的
    final playback = await PlaybackSettingsRepository(database).read();
    expect(playback.audioQuality, AudioQuality.medium); // 匯入的
    expect(playback.playHistoryLimit, 5000); // 匯入的
    expect(playback.rememberPosition, isFalse); // 匯入的
    expect(playback.outputDeviceId, 'device-1'); // 這台的
    expect(playback.outputDeviceName, 'Speakers');
    // 版面只在首次啟動匯入。
    expect(
      await LayoutStateRepository(database).read(),
      const LayoutState(panelExpanded: true, panelWidth: 300),
    );
    // 每音源設定：browse_as_logged_in 以匯入為準，同一列其他欄位保留；匯入沒有的音源不動。
    final rows = await database
        .customSelect(
          'SELECT plugin_id, browse_as_logged_in AS b, match_target AS t, '
          'match_rank AS r FROM source_settings ORDER BY plugin_id',
        )
        .get();
    expect(
      [
        for (final row in rows)
          (
            row.read<String>('plugin_id'),
            row.readNullable<int>('b'),
            row.readNullable<int>('t'),
            row.readNullable<int>('r'),
          ),
      ],
      [
        ('bilibili', 1, 1, 2),
        ('netease', null, 0, null),
        ('youtube', 0, null, null),
      ],
    );
  });

  test(
    'accounts: this device keeps its rows; the import fills the rest',
    () async {
      await seedCurrent();
      final replaced = await replace(bundleWithAccounts());

      // 這台有 bilibili 與 netease，匯入有 bilibili 與 youtube：
      // 只有這台（netease）、只有匯入（youtube）、兩邊都有（bilibili，留這台的）。
      expect(replaced.keptAccountPluginIds, {'bilibili', 'netease'});
      // 資料層不能 import 轉換器，摘要的鍵是同一個字面值。
      expect(SummaryCollection.accounts, 'accounts');
      final database = await openStaging();
      final rows = await database
          .customSelect(
            'SELECT plugin_id, user_id FROM accounts ORDER BY plugin_id',
          )
          .get();
      expect(
        [
          for (final row in rows)
            (row.read<String>('plugin_id'), row.read<String>('user_id')),
        ],
        [('bilibili', 'mine-b'), ('netease', 'mine-n'), ('youtube', 'y')],
      );

      // 摘要：沒寫的帳號計成略過，這台還登入的平台不說要重新登入。
      expect(
        replaced.summary.collections['accounts'],
        const CollectionSummary(
          read: 2,
          written: 1,
          skipped: {'keptOnThisDevice': 1},
        ),
      );
      expect(replaced.summary.reloginPlatforms, ['youtube']);
    },
  );

  test('accounts: an invalidated row does not count as signed in; it is replaced '
      'when the import has the platform and kept when it does not', () async {
    await seedCurrent();
    final accounts = AccountRepository(current);
    for (final (plugin, user) in [('youtube', 'old-y'), ('qqmusic', 'old-q')]) {
      await accounts.upsert(
        Account(
          pluginId: plugin,
          userId: user,
          displayName: 'Invalidated $plugin',
          status: AccountStatus.invalidated,
          loggedInAt: at(40),
        ),
      );
    }
    // 匯入有 bilibili（這台 active，不取代）與 youtube（這台 invalidated，取代）。
    final replaced = await replace(bundleWithAccounts());

    // 只有 active 的算保留；憑證由匯入的覆寫 youtube 的。
    expect(replaced.keptAccountPluginIds, {'bilibili', 'netease'});
    final database = await openStaging();
    final rows = await database
        .customSelect(
          'SELECT plugin_id, user_id, status FROM accounts ORDER BY plugin_id',
        )
        .get();
    expect(
      [
        for (final row in rows)
          (
            row.read<String>('plugin_id'),
            row.read<String>('user_id'),
            row.read<String>('status'),
          ),
      ],
      [
        ('bilibili', 'mine-b', 'active'),
        ('netease', 'mine-n', 'active'),
        // 匯入沒有 qqmusic：保留這台的 invalidated 列。
        ('qqmusic', 'old-q', 'invalidated'),
        ('youtube', 'y', 'active'),
      ],
    );
    // `keptOnThisDevice` 只算 active 的（bilibili）。
    expect(
      replaced.summary.collections['accounts'],
      const CollectionSummary(
        read: 2,
        written: 1,
        skipped: {'keptOnThisDevice': 1},
      ),
    );
  });

  test('the import record is added next to the old one', () async {
    await seedCurrent();
    final replaced = await replace(bundleWithAccounts());

    final database = await openStaging();
    expect(await count(database, 'legacy_imports'), 2);
    final latest = (await LegacyImportsRepository(database)
        .latestUnacknowledged())!;
    expect(latest.importedAt, importedAt);
    expect(latest.summary, replaced.summary);
    // 舊歌單 id 對照只有這次的。
    expect(await count(database, 'legacy_playlist_ids'), 3);
  });

  test('writing leaves the current database untouched', () async {
    await seedCurrent();
    final before = {
      for (final table in ['tracks', 'playlists', 'accounts', 'legacy_imports'])
        table: await count(current, table),
    };
    await replace(bundleWithAccounts());

    expect({
      for (final table in before.keys) table: await count(current, table),
    }, before);
    expect(
      [
        for (final o in await PlaylistRepository(current).overviews())
          o.playlist.name,
      ],
      ['Old list'],
    );
  });

  test('verify counts the kept rows: a lost plugin row fails and removes '
      'the staging file', () async {
    await seedCurrent();
    final bundle = bundleWithAccounts();
    final replaced = await stager().writeReplacing(
      bundle,
      staging,
      importedAt: importedAt,
      current: current,
    );
    final tampered = await openStaging();
    await tampered.customStatement('DELETE FROM installed_plugins');
    await tampered.close();

    await expectLater(
      stager().verify(bundle, staging, replaced: replaced),
      throwsA(
        isA<LegacyImportFailed>()
            .having((e) => e.step, 'step', LegacyImportStep.verify)
            .having((e) => e.reason, 'reason', contains('installed_plugins')),
      ),
    );
    expect(staging.existsSync(), isFalse);
  });

  test('a bundle that cannot be written fails, removes the staging file and '
      'leaves the current database as it was', () async {
    await seedCurrent();
    final base = bundleWithAccounts();
    // 歌單項目指到不在匯入包裡的曲目：外鍵擋下。
    final broken = ImportBundle(
      record: base.record,
      tracks: const [],
      playlists: base.playlists,
    );

    await expectLater(
      stager().writeReplacing(
        broken,
        staging,
        importedAt: importedAt,
        current: current,
      ),
      throwsA(
        isA<LegacyImportFailed>().having(
          (e) => e.step,
          'step',
          LegacyImportStep.write,
        ),
      ),
    );
    expect(staging.existsSync(), isFalse);
    expect(await count(current, 'playlists'), 1);
    expect(await count(current, 'accounts'), 2);
  });

  test('an empty bundle clears the library and keeps every setting', () async {
    await seedCurrent();
    final empty = ImportBundle(
      record: ImportRecord(
        source: fullBundle().record.source,
        summary: const ImportSummary(),
      ),
    );
    await replace(empty);

    final database = await openStaging();
    for (final table in StagingImport.replacedTables) {
      expect(await count(database, table), 0, reason: table);
    }
    expect(
      (await PlaybackSettingsRepository(database).read()).outputDeviceId,
      'device-1',
    );
    expect(await count(database, 'accounts'), 2);
    expect(await count(database, 'source_settings'), 2);
  });
}
