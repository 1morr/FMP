// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;
import 'generated/schema_v6.dart' as v6;
import 'generated/schema_v7.dart' as v7;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // v2 只加 network_settings：既有表的資料與使用者設定過的值一個都不能變
  // （ADR 0010 §決定 3），新表升級後是空的（沒設定過＝套用平台預設）。
  test('migration from v1 to v2 keeps existing data', () async {
    const appearance = v1.AppearanceSettingsData(
      id: 1,
      themeMode: 'dark',
      locale: 'zh-CN',
    );
    const plugin = v1.InstalledPluginsData(
      id: 'p',
      version: '1.0.0',
      manifestJson: '{}',
      script: 'script',
      installedAt: 1790000000000,
    );
    const storage = v1.PluginStorageData(pluginId: 'p', key: 'k', value: 'v');

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(oldDb.appearanceSettings, appearance);
        batch.insert(oldDb.installedPlugins, plugin);
        batch.insert(oldDb.pluginStorage, storage);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.appearanceSettings).get(), [
          const v2.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        ], reason: 'the user value is untouched');
        expect(await newDb.select(newDb.installedPlugins).get(), [
          const v2.InstalledPluginsData(
            id: 'p',
            version: '1.0.0',
            manifestJson: '{}',
            script: 'script',
            installedAt: 1790000000000,
          ),
        ]);
        expect(await newDb.select(newDb.pluginStorage).get(), [
          const v2.PluginStorageData(pluginId: 'p', key: 'k', value: 'v'),
        ]);
        expect(await newDb.select(newDb.networkSettings).get(), isEmpty);
      },
    );
  });

  // v3 只加 playback_settings（design §3.3）：既有表的資料原樣保留，新表升級後是
  // 空的（每個欄位都是沒設定過，讀取時才套用預設）。
  test('migration from v2 to v3 keeps existing data', () async {
    const plugin = v2.InstalledPluginsData(
      id: 'p',
      version: '1.0.0',
      manifestJson: '{}',
      script: 'script',
      installedAt: 1790000000000,
    );
    const storage = v2.PluginStorageData(pluginId: 'p', key: 'k', value: 'v');

    await verifier.testWithDataIntegrity(
      oldVersion: 2,
      newVersion: 3,
      createOld: v2.DatabaseAtV2.new,
      createNew: v3.DatabaseAtV3.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(oldDb.installedPlugins, plugin);
        batch.insert(oldDb.pluginStorage, storage);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.installedPlugins).get(), [
          const v3.InstalledPluginsData(
            id: 'p',
            version: '1.0.0',
            manifestJson: '{}',
            script: 'script',
            installedAt: 1790000000000,
          ),
        ]);
        expect(await newDb.select(newDb.pluginStorage).get(), [
          const v3.PluginStorageData(pluginId: 'p', key: 'k', value: 'v'),
        ]);
        expect(await newDb.select(newDb.playbackSettings).get(), isEmpty);
      },
    );
  });

  // ADR 0010 §決定 3：migration 不改使用者設定過的值。新表沒有舊資料，所以以
  // 升級前就有的設定組（外觀、網路）的使用者值代表。
  test('migration from v2 to v3 keeps the values the user set', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 2,
      newVersion: 3,
      createOld: v2.DatabaseAtV2.new,
      createNew: v3.DatabaseAtV3.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.appearanceSettings,
          const v2.AppearanceSettingsData(
            id: 1,
            themeMode: 'light',
            locale: 'en',
          ),
        );
        batch.insert(
          oldDb.networkSettings,
          const v2.NetworkSettingsData(id: 1, cacheLimitMb: 1024),
        );
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.appearanceSettings).get(), [
          const v3.AppearanceSettingsData(
            id: 1,
            themeMode: 'light',
            locale: 'en',
          ),
        ]);
        expect(await newDb.select(newDb.networkSettings).get(), [
          const v3.NetworkSettingsData(id: 1, cacheLimitMb: 1024),
        ]);
      },
    );
  });

  // v4 加 tracks、queue_entries、player_state（design §3.1、§3.2）：既有表的資料原樣
  // 保留，新表升級後是空的（沒存過佇列就是空佇列）。
  test('migration from v3 to v4 keeps existing data', () async {
    const plugin = v3.InstalledPluginsData(
      id: 'p',
      version: '1.0.0',
      manifestJson: '{}',
      script: 'script',
      installedAt: 1790000000000,
    );
    const storage = v3.PluginStorageData(pluginId: 'p', key: 'k', value: 'v');

    await verifier.testWithDataIntegrity(
      oldVersion: 3,
      newVersion: 4,
      createOld: v3.DatabaseAtV3.new,
      createNew: v4.DatabaseAtV4.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(oldDb.installedPlugins, plugin);
        batch.insert(oldDb.pluginStorage, storage);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.installedPlugins).get(), [
          const v4.InstalledPluginsData(
            id: 'p',
            version: '1.0.0',
            manifestJson: '{}',
            script: 'script',
            installedAt: 1790000000000,
          ),
        ]);
        expect(await newDb.select(newDb.pluginStorage).get(), [
          const v4.PluginStorageData(pluginId: 'p', key: 'k', value: 'v'),
        ]);
        expect(await newDb.select(newDb.tracks).get(), isEmpty);
        expect(await newDb.select(newDb.queueEntries).get(), isEmpty);
        expect(await newDb.select(newDb.playerState).get(), isEmpty);
      },
    );
  });

  // ADR 0010 §決定 3：migration 不改使用者設定過的值。新表沒有舊資料，所以以升級前
  // 就有的設定組（外觀、網路、播放）的使用者值代表。
  test('migration from v3 to v4 keeps the values the user set', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 3,
      newVersion: 4,
      createOld: v3.DatabaseAtV3.new,
      createNew: v4.DatabaseAtV4.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.appearanceSettings,
          const v3.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        );
        batch.insert(
          oldDb.networkSettings,
          const v3.NetworkSettingsData(id: 1, cacheLimitMb: 512),
        );
        batch.insert(
          oldDb.playbackSettings,
          const v3.PlaybackSettingsData(
            id: 1,
            audioQuality: 'low',
            rememberPosition: 0,
            restartRewindSeconds: 15,
          ),
        );
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.appearanceSettings).get(), [
          const v4.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        ]);
        expect(await newDb.select(newDb.networkSettings).get(), [
          const v4.NetworkSettingsData(id: 1, cacheLimitMb: 512),
        ]);
        expect(await newDb.select(newDb.playbackSettings).get(), [
          const v4.PlaybackSettingsData(
            id: 1,
            audioQuality: 'low',
            rememberPosition: 0,
            restartRewindSeconds: 15,
          ),
        ]);
      },
    );
  });

  // 新表的外鍵在升級後就生效：被佇列參照的曲目刪不掉（design §3.5）。
  test('migration from v3 to v4 creates a queue that restricts track '
      'deletion', () async {
    final schema = await verifier.schemaAt(3);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 4);
    await db.customStatement(
      "INSERT INTO tracks (track_key, source_type_id, source_id, title, "
      "updated_at) VALUES ('p:1', 'p', '1', 'T', 0)",
    );
    await db.customStatement(
      "INSERT INTO queue_entries (position, track_key) VALUES (0, 'p:1')",
    );

    await expectLater(
      db.customStatement("DELETE FROM tracks WHERE track_key = 'p:1'"),
      throwsA(anything),
    );
    await db.close();
  });

  // 刪曲目時 RESTRICT 的檢查要靠 queue_entries.track_key 的索引，否則每刪一列都掃一次
  // 佇列（孤兒清理：一萬首佇列加一萬個孤兒實測約 9 秒）。升級來的與全新建的都要有。
  Future<List<String>> queueEntryIndexes(AppDatabase db) async => [
    for (final row
        in await db.customSelect("PRAGMA index_list('queue_entries')").get())
      row.read<String>('name'),
  ];

  test('migration from v3 to v4 indexes queue_entries.track_key', () async {
    final schema = await verifier.schemaAt(3);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 4);

    expect(await queueEntryIndexes(db), contains('queue_entries_track_key'));
    await db.close();
  });

  test('a new database indexes queue_entries.track_key', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await queueEntryIndexes(db), contains('queue_entries_track_key'));
  });

  // v5 加 play_history（design §3.2）：既有表的資料與使用者值原樣保留，新表升級後是空的。
  test('migration from v4 to v5 keeps existing data', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 4,
      newVersion: 5,
      createOld: v4.DatabaseAtV4.new,
      createNew: v5.DatabaseAtV5.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.appearanceSettings,
          const v4.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        );
        batch.insert(
          oldDb.playbackSettings,
          const v4.PlaybackSettingsData(
            id: 1,
            audioQuality: 'low',
            playHistoryLimit: 1000,
          ),
        );
        batch.insert(
          oldDb.tracks,
          v4.TracksData(
            trackKey: 'p:1',
            sourceTypeId: 'p',
            sourceId: '1',
            title: 'T',
            updatedAt: 1790000000000,
          ),
        );
        batch.insert(
          oldDb.queueEntries,
          const v4.QueueEntriesData(position: 0, trackKey: 'p:1'),
        );
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.appearanceSettings).get(), [
          const v5.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        ], reason: 'the user value is untouched');
        expect(await newDb.select(newDb.playbackSettings).get(), [
          const v5.PlaybackSettingsData(
            id: 1,
            audioQuality: 'low',
            playHistoryLimit: 1000,
          ),
        ]);
        expect(await newDb.select(newDb.tracks).get(), hasLength(1));
        expect(await newDb.select(newDb.queueEntries).get(), hasLength(1));
        expect(await newDb.select(newDb.playHistory).get(), isEmpty);
      },
    );
  });

  Future<List<String>> playHistoryIndexes(AppDatabase db) async => [
    for (final row
        in await db.customSelect("PRAGMA index_list('play_history')").get())
      row.read<String>('name'),
  ];

  // 刪曲目時 RESTRICT 的檢查要靠 play_history.track_key 的索引（同 queue_entries）；
  // played_at 的索引給倒序分頁。從每個舊版升上來的與全新建的都要有。
  for (final from in [1, 2, 3, 4]) {
    test('migration from v$from to v5 creates play_history with its two '
        'indexes and restricts track deletion', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 5);

      expect(
        await playHistoryIndexes(db),
        containsAll(['play_history_played_at', 'play_history_track_key']),
      );
      await db.customStatement('PRAGMA foreign_keys = ON');
      await db.customStatement(
        "INSERT INTO tracks (track_key, source_type_id, source_id, title, "
        "updated_at) VALUES ('p:1', 'p', '1', 'T', 0)",
      );
      await db.customStatement(
        "INSERT INTO play_history (track_key, played_at) VALUES ('p:1', 1)",
      );
      await expectLater(
        db.customStatement("DELETE FROM tracks WHERE track_key = 'p:1'"),
        throwsA(anything),
      );
      await db.close();
    });
  }

  test('a new database has play_history and its two indexes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(
      await playHistoryIndexes(db),
      containsAll(['play_history_played_at', 'play_history_track_key']),
    );
  });

  // v6 只加 layout_state：既有表的資料與使用者設定過的值一個都不能變，新表升級後是空的。
  test('migration from v5 to v6 keeps existing data', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 5,
      newVersion: 6,
      createOld: v5.DatabaseAtV5.new,
      createNew: v6.DatabaseAtV6.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.appearanceSettings,
          const v5.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        );
        batch.insert(
          oldDb.networkSettings,
          const v5.NetworkSettingsData(id: 1, cacheLimitMb: 512),
        );
        batch.insert(
          oldDb.playbackSettings,
          const v5.PlaybackSettingsData(
            id: 1,
            audioQuality: 'low',
            playHistoryLimit: 1000,
          ),
        );
        batch.insert(
          oldDb.tracks,
          v5.TracksData(
            trackKey: 'p:1',
            sourceTypeId: 'p',
            sourceId: '1',
            title: 'T',
            updatedAt: 1790000000000,
          ),
        );
        batch.insert(
          oldDb.queueEntries,
          const v5.QueueEntriesData(position: 0, trackKey: 'p:1'),
        );
        batch.insert(
          oldDb.playHistory,
          v5.PlayHistoryData(id: 1, trackKey: 'p:1', playedAt: 1790000000001),
        );
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.appearanceSettings).get(), [
          const v6.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        ], reason: 'the user value is untouched');
        expect(await newDb.select(newDb.networkSettings).get(), [
          const v6.NetworkSettingsData(id: 1, cacheLimitMb: 512),
        ]);
        expect(await newDb.select(newDb.playbackSettings).get(), [
          const v6.PlaybackSettingsData(
            id: 1,
            audioQuality: 'low',
            playHistoryLimit: 1000,
          ),
        ]);
        expect(await newDb.select(newDb.tracks).get(), hasLength(1));
        expect(await newDb.select(newDb.queueEntries).get(), hasLength(1));
        expect(await newDb.select(newDb.playHistory).get(), hasLength(1));
        expect(await newDb.select(newDb.layoutState).get(), isEmpty);
      },
    );
  });

  Future<void> expectLayoutStateRules(AppDatabase db) async {
    expect(await db.select(db.layoutStateTable).get(), isEmpty);
    await db.customStatement(
      "INSERT INTO layout_state (id, player_tab, panel_expanded, panel_width) "
      "VALUES (1, 'queue', 1, 412.0)",
    );
    // 單列：第二列插不進去。
    await expectLater(
      db.customStatement('INSERT INTO layout_state (id) VALUES (2)'),
      throwsA(anything),
    );
    // 只擋明顯的壞值：寬度超過 1600 寫不進去。
    await expectLater(
      db.customStatement('UPDATE layout_state SET panel_width = 1601.0'),
      throwsA(anything),
    );
    await db.customStatement('UPDATE layout_state SET panel_width = 1600.0');
  }

  // 從每個舊版升上來的與全新建的都要有 layout_state 和它的檢查。
  for (final from in [1, 2, 3, 4, 5]) {
    test('migration from v$from to v6 creates layout_state with its '
        'checks', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 6);

      await expectLayoutStateRules(db);
      await db.close();
    });
  }

  test('a new database has layout_state with its checks', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await expectLayoutStateRules(db);
  });

  // v7 給 installed_plugins 加三欄、新增 plugin_indexes（ADR 0030）：升級前裝好的插件仍啟用、
  // 內容與 storage 不變，使用者設定過的值原樣保留，新表升級後是空的。
  test('migration from v6 to v7 keeps existing data', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 6,
      newVersion: 7,
      createOld: v6.DatabaseAtV6.new,
      createNew: v7.DatabaseAtV7.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.appearanceSettings,
          const v6.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        );
        batch.insert(
          oldDb.networkSettings,
          const v6.NetworkSettingsData(id: 1, cacheLimitMb: 512),
        );
        batch.insert(
          oldDb.installedPlugins,
          const v6.InstalledPluginsData(
            id: 'bilibili',
            version: '1.0.0',
            manifestJson: '{"id":"bilibili"}',
            script: 'export const a = 1;',
            installedAt: 1790000000000,
          ),
        );
        batch.insert(
          oldDb.pluginStorage,
          const v6.PluginStorageData(
            pluginId: 'bilibili',
            key: 'buvid3',
            value: 'v',
          ),
        );
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.appearanceSettings).get(), [
          const v7.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        ]);
        expect(await newDb.select(newDb.networkSettings).get(), [
          const v7.NetworkSettingsData(id: 1, cacheLimitMb: 512),
        ]);
        // 升級前裝好的插件仍啟用，內容不變，沒有來源 index、沒有檢查案例。
        expect(await newDb.select(newDb.installedPlugins).get(), [
          const v7.InstalledPluginsData(
            id: 'bilibili',
            version: '1.0.0',
            manifestJson: '{"id":"bilibili"}',
            script: 'export const a = 1;',
            installedAt: 1790000000000,
            enabled: 1,
          ),
        ]);
        expect(await newDb.select(newDb.pluginStorage).get(), hasLength(1));
        expect(await newDb.select(newDb.pluginIndexes).get(), isEmpty);
      },
    );
  });

  Future<void> expectPluginLifecycleSchema(AppDatabase db) async {
    // 新裝的列預設啟用；plugin_indexes 的主鍵是網址。
    await db.customStatement(
      "INSERT INTO installed_plugins (id, version, manifest_json, script, "
      "installed_at) VALUES ('p', '1.0.0', '{}', 's', 1)",
    );
    final enabled = await db
        .customSelect('SELECT enabled FROM installed_plugins')
        .getSingle();
    expect(enabled.read<int>('enabled'), 1);
    await db.customStatement(
      "INSERT INTO plugin_indexes (url, added_at) VALUES ('https://a.test/i', 1)",
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO plugin_indexes (url, added_at) "
        "VALUES ('https://a.test/i', 2)",
      ),
      throwsA(anything),
    );
  }

  for (final from in [1, 2, 3, 4, 5, 6]) {
    test(
      'migration from v$from to v7 adds the plugin lifecycle schema',
      () async {
        final schema = await verifier.schemaAt(from);
        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, 7);

        await expectPluginLifecycleSchema(db);
        await db.close();
      },
    );
  }

  test('a new database has the plugin lifecycle schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await expectPluginLifecycleSchema(db);
  });
}
