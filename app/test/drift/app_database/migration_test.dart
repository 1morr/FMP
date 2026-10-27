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
import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;
import 'generated/schema_v10.dart' as v10;
import 'generated/schema_v11.dart' as v11;
import 'generated/schema_v12.dart' as v12;
import 'generated/schema_v13.dart' as v13;
import 'generated/schema_v14.dart' as v14;
import 'generated/schema_v15.dart' as v15;
import 'generated/schema_v16.dart' as v16;
import 'generated/schema_v17.dart' as v17;
import 'generated/schema_v18.dart' as v18;
import 'generated/schema_v19.dart' as v19;
import 'generated/schema_v20.dart' as v20;
import 'generated/schema_v21.dart' as v21;
import 'generated/schema_v22.dart' as v22;
import 'generated/schema_v23.dart' as v23;

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
      'INSERT INTO layout_state (id, panel_expanded, panel_width) '
      'VALUES (1, 1, 412.0)',
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

  // v8 新增 accounts 與 source_settings（ADR 0029 §決定 6）：既有的資料原樣保留，新表升級後是空的
  // （帳號資料來自登入，不是 migration；使用者設定過的值不被動）。
  test('migration from v7 to v8 keeps existing data', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 7,
      newVersion: 8,
      createOld: v7.DatabaseAtV7.new,
      createNew: v8.DatabaseAtV8.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.appearanceSettings,
          const v7.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        );
        batch.insert(
          oldDb.installedPlugins,
          const v7.InstalledPluginsData(
            id: 'bilibili',
            version: '1.0.0',
            manifestJson: '{"id":"bilibili"}',
            script: 'export const a = 1;',
            installedAt: 1790000000000,
            enabled: 0,
          ),
        );
        batch.insert(
          oldDb.pluginStorage,
          const v7.PluginStorageData(
            pluginId: 'bilibili',
            key: 'buvid3',
            value: 'v',
          ),
        );
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.appearanceSettings).get(), [
          const v8.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        ]);
        // 使用者停用的插件仍是停用，內容不變。
        expect(await newDb.select(newDb.installedPlugins).get(), [
          const v8.InstalledPluginsData(
            id: 'bilibili',
            version: '1.0.0',
            manifestJson: '{"id":"bilibili"}',
            script: 'export const a = 1;',
            installedAt: 1790000000000,
            enabled: 0,
          ),
        ]);
        expect(await newDb.select(newDb.pluginStorage).get(), hasLength(1));
        expect(await newDb.select(newDb.accounts).get(), isEmpty);
        expect(await newDb.select(newDb.sourceSettings).get(), isEmpty);
      },
    );
  });

  Future<void> expectAccountSchema(AppDatabase db) async {
    // 主鍵是插件 id；沒有外鍵到 installed_plugins（插件移除後的清理由程式碼做）。
    await db.customStatement(
      "INSERT INTO accounts (plugin_id, user_id, display_name, status, "
      "logged_in_at) VALUES ('p', 'u', 'n', 'active', 1)",
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO accounts (plugin_id, user_id, display_name, status, "
        "logged_in_at) VALUES ('p', 'u2', 'n2', 'active', 2)",
      ),
      throwsA(anything),
    );
    await db.customStatement(
      "INSERT INTO source_settings (plugin_id) VALUES ('p')",
    );
    final setting = await db
        .customSelect('SELECT browse_as_logged_in FROM source_settings')
        .getSingle();
    expect(setting.data['browse_as_logged_in'], equals(null));
    await expectLater(
      db.customStatement(
        "INSERT INTO source_settings (plugin_id) VALUES ('p')",
      ),
      throwsA(anything),
    );
  }

  for (final from in [1, 2, 3, 4, 5, 6, 7]) {
    test('migration from v$from to v8 adds the account schema', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 8);

      await expectAccountSchema(db);
      await db.close();
    });
  }

  test('a new database has the account schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await expectAccountSchema(db);
  });

  // v9 新增 developer_settings（ADR 0025 §決定 1、M3 design §3.3）：既有的資料與使用者設定過的
  // 值原樣保留，新表升級後是空的（沒設定過＝dev 開、prod 關的預設）。
  test('migration from v8 to v9 keeps existing data', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 8,
      newVersion: 9,
      createOld: v8.DatabaseAtV8.new,
      createNew: v9.DatabaseAtV9.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.appearanceSettings,
          const v8.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        );
        batch.insert(
          oldDb.networkSettings,
          const v8.NetworkSettingsData(id: 1, cacheLimitMb: 512),
        );
        batch.insert(
          oldDb.installedPlugins,
          const v8.InstalledPluginsData(
            id: 'bilibili',
            version: '1.0.0',
            manifestJson: '{"id":"bilibili"}',
            script: 'export const a = 1;',
            installedAt: 1790000000000,
            enabled: 0,
          ),
        );
        batch.insert(
          oldDb.accounts,
          const v8.AccountsData(
            pluginId: 'bilibili',
            userId: 'u',
            displayName: 'n',
            status: 'invalidated',
            loggedInAt: 1790000000000,
          ),
        );
        batch.insert(
          oldDb.sourceSettings,
          const v8.SourceSettingsData(
            pluginId: 'bilibili',
            browseAsLoggedIn: 0,
          ),
        );
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.appearanceSettings).get(), [
          const v9.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        ]);
        expect(await newDb.select(newDb.networkSettings).get(), [
          const v9.NetworkSettingsData(id: 1, cacheLimitMb: 512),
        ]);
        expect(await newDb.select(newDb.installedPlugins).get(), [
          const v9.InstalledPluginsData(
            id: 'bilibili',
            version: '1.0.0',
            manifestJson: '{"id":"bilibili"}',
            script: 'export const a = 1;',
            installedAt: 1790000000000,
            enabled: 0,
          ),
        ]);
        expect(await newDb.select(newDb.accounts).get(), [
          const v9.AccountsData(
            pluginId: 'bilibili',
            userId: 'u',
            displayName: 'n',
            status: 'invalidated',
            loggedInAt: 1790000000000,
          ),
        ]);
        // 使用者關掉的「以登入身分瀏覽與播放」仍是關。
        expect(await newDb.select(newDb.sourceSettings).get(), [
          const v9.SourceSettingsData(
            pluginId: 'bilibili',
            browseAsLoggedIn: 0,
          ),
        ]);
        expect(await newDb.select(newDb.developerSettings).get(), isEmpty);
      },
    );
  });

  Future<void> expectDeveloperSettingsSchema(AppDatabase db) async {
    // 單列，四個欄位都可空（空＝沒設定過，ADR 0011 §決定 7）。
    await db.customStatement('INSERT INTO developer_settings (id) VALUES (1)');
    final row = await db
        .customSelect(
          'SELECT developer_mode, log_level, plugin_dev_folder, '
          'report_reminder_dismissed FROM developer_settings',
        )
        .getSingle();
    expect(row.data, {
      'developer_mode': null,
      'log_level': null,
      'plugin_dev_folder': null,
      'report_reminder_dismissed': null,
    });
    await expectLater(
      db.customStatement('INSERT INTO developer_settings (id) VALUES (2)'),
      throwsA(anything),
    );
  }

  for (final from in [1, 2, 3, 4, 5, 6, 7, 8]) {
    test('migration from v$from to v9 adds the developer settings', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 9);

      await expectDeveloperSettingsSchema(db);
      await db.close();
    });
  }

  test('a new database has the developer settings', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await expectDeveloperSettingsSchema(db);
  });

  // v10 在 installed_plugins 加 from_dev_folder（M3 PR 16b）：升級前的列都是使用者裝的，
  // 取預設的假；其他欄位與它的 storage 原樣保留。
  test(
    'migration from v9 to v10 marks existing plugins as installed',
    () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 9,
        newVersion: 10,
        createOld: v9.DatabaseAtV9.new,
        createNew: v10.DatabaseAtV10.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch.insert(
            oldDb.installedPlugins,
            const v9.InstalledPluginsData(
              id: 'bilibili',
              version: '1.0.0',
              manifestJson: '{"id":"bilibili"}',
              script: 'export const a = 1;',
              installedAt: 1790000000000,
              enabled: 0,
              checksJson: '{"search":{}}',
            ),
          );
          batch.insert(
            oldDb.pluginStorage,
            const v9.PluginStorageData(
              pluginId: 'bilibili',
              key: 'wbiKeys',
              value: 'v',
            ),
          );
        },
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.installedPlugins).get(), [
            const v10.InstalledPluginsData(
              id: 'bilibili',
              version: '1.0.0',
              manifestJson: '{"id":"bilibili"}',
              script: 'export const a = 1;',
              installedAt: 1790000000000,
              enabled: 0,
              checksJson: '{"search":{}}',
              fromDevFolder: 0,
            ),
          ]);
          expect(await newDb.select(newDb.pluginStorage).get(), [
            const v10.PluginStorageData(
              pluginId: 'bilibili',
              key: 'wbiKeys',
              value: 'v',
            ),
          ]);
        },
      );
    },
  );

  test('a new database defaults from_dev_folder to false', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.customStatement(
      "INSERT INTO installed_plugins (id, version, manifest_json, script, "
      "installed_at) VALUES ('p', '1', '{}', '', 0)",
    );
    final row = await db
        .customSelect('SELECT from_dev_folder FROM installed_plugins')
        .getSingle();
    expect(row.data['from_dev_folder'], 0);
  });

  // v11 新增 scheduler_runs（ADR 0017 §決定 2、M3 design §3.1）：既有的資料與使用者設定過的值
  // 原樣保留，新表升級後是空的（所有工作都視為從沒成功過）。
  test('migration from v10 to v11 keeps existing data', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 10,
      newVersion: 11,
      createOld: v10.DatabaseAtV10.new,
      createNew: v11.DatabaseAtV11.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.networkSettings,
          const v10.NetworkSettingsData(id: 1, cacheLimitMb: 512),
        );
        batch.insert(
          oldDb.installedPlugins,
          const v10.InstalledPluginsData(
            id: 'bilibili',
            version: '1.0.0',
            manifestJson: '{"id":"bilibili"}',
            script: 'export const a = 1;',
            installedAt: 1790000000000,
            enabled: 0,
            fromDevFolder: 0,
          ),
        );
        batch.insert(
          oldDb.developerSettings,
          const v10.DeveloperSettingsData(
            id: 1,
            developerMode: 1,
            logLevel: 'debug',
          ),
        );
      },
      validateItems: (newDb) async {
        // 使用者設定過的值不變。
        expect(await newDb.select(newDb.networkSettings).get(), [
          const v11.NetworkSettingsData(id: 1, cacheLimitMb: 512),
        ]);
        expect(await newDb.select(newDb.installedPlugins).get(), [
          const v11.InstalledPluginsData(
            id: 'bilibili',
            version: '1.0.0',
            manifestJson: '{"id":"bilibili"}',
            script: 'export const a = 1;',
            installedAt: 1790000000000,
            enabled: 0,
            fromDevFolder: 0,
          ),
        ]);
        expect(await newDb.select(newDb.developerSettings).get(), [
          const v11.DeveloperSettingsData(
            id: 1,
            developerMode: 1,
            logLevel: 'debug',
          ),
        ]);
        expect(await newDb.select(newDb.schedulerRuns).get(), isEmpty);
      },
    );
  });

  Future<void> expectSchedulerRunsSchema(AppDatabase db) async {
    // 以工作 id 為主鍵；時間存 UTC epoch 毫秒（持久化格式）。
    await db.customStatement(
      "INSERT INTO scheduler_runs (job_id, last_success_at) "
      "VALUES ('radio-status:bilibili', 1790000000000)",
    );
    final row = await db
        .customSelect('SELECT job_id, last_success_at FROM scheduler_runs')
        .getSingle();
    expect(row.data, {
      'job_id': 'radio-status:bilibili',
      'last_success_at': 1790000000000,
    });
    await expectLater(
      db.customStatement(
        "INSERT INTO scheduler_runs (job_id, last_success_at) "
        "VALUES ('radio-status:bilibili', 1)",
      ),
      throwsA(anything),
    );
  }

  for (final from in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
    test('migration from v$from to v11 adds scheduler_runs', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 11);

      await expectSchedulerRunsSchema(db);
      await db.close();
    });
  }

  test('a new database has scheduler_runs', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await expectSchedulerRunsSchema(db);
  });

  // v12 新增 radio_stations 並在 network_settings 加電台狀態間隔（ADR 0031 §決定 1、
  // M3 design §3.1）：既有的資料與使用者設定過的值原樣保留；新表是空的，新欄位在舊列上
  // 是 NULL（＝沒設定過，預設只在 Notifier 套用）。
  test('migration from v11 to v12 keeps existing data', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 11,
      newVersion: 12,
      createOld: v11.DatabaseAtV11.new,
      createNew: v12.DatabaseAtV12.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.networkSettings,
          const v11.NetworkSettingsData(id: 1, cacheLimitMb: 512),
        );
        batch.insert(
          oldDb.schedulerRuns,
          const v11.SchedulerRunsData(
            jobId: 'radio-status:bilibili',
            lastSuccessAt: 1790000000000,
          ),
        );
      },
      validateItems: (newDb) async {
        // 使用者設定過的快取上限不變，新欄位是空的。
        expect(await newDb.select(newDb.networkSettings).get(), [
          const v12.NetworkSettingsData(id: 1, cacheLimitMb: 512),
        ]);
        expect(await newDb.select(newDb.schedulerRuns).get(), [
          const v12.SchedulerRunsData(
            jobId: 'radio-status:bilibili',
            lastSuccessAt: 1790000000000,
          ),
        ]);
        expect(await newDb.select(newDb.radioStations).get(), isEmpty);
      },
    );
  });

  Future<void> expectRadioStationsSchema(AppDatabase db) async {
    // 持久化格式：狀態字串寫死、時間存 UTC epoch 毫秒、（插件, 房間）唯一。
    await db.customStatement(
      "INSERT INTO radio_stations (plugin_id, room_id, title, sort_order, "
      "added_at, live_status, live_title, status_checked_at) VALUES "
      "('bilibili', '5440', 'T', 0, 1790000000000, 'live', 'Now', 1790000060000)",
    );
    final row = await db
        .customSelect(
          'SELECT plugin_id, room_id, host_name, artwork_json, sort_order, '
          'added_at, live_status, live_title, status_checked_at '
          'FROM radio_stations',
        )
        .getSingle();
    expect(row.data, {
      'plugin_id': 'bilibili',
      'room_id': '5440',
      'host_name': null,
      'artwork_json': null,
      'sort_order': 0,
      'added_at': 1790000000000,
      'live_status': 'live',
      'live_title': 'Now',
      'status_checked_at': 1790000060000,
    });
    await expectLater(
      db.customStatement(
        "INSERT INTO radio_stations (plugin_id, room_id, title, sort_order, "
        "added_at) VALUES ('bilibili', '5440', 'Dup', 1, 1)",
      ),
      throwsA(anything),
    );
    // 另一個插件的同一個房間 id 是另一個電台。
    await db.customStatement(
      "INSERT INTO radio_stations (plugin_id, room_id, title, sort_order, "
      "added_at) VALUES ('other', '5440', 'Other', 1, 1)",
    );
  }

  for (final from in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]) {
    test('migration from v$from to v12 adds radio_stations and the '
        'status interval column', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 12);

      await expectRadioStationsSchema(db);
      // 沒有設定過：新欄位是 NULL。
      if (from >= 2) {
        await db.customStatement(
          'INSERT OR IGNORE INTO network_settings (id) VALUES (1)',
        );
        final interval = await db
            .customSelect(
              'SELECT radio_status_interval_minutes AS v FROM network_settings',
            )
            .getSingle();
        expect(interval.data['v'], equals(null));
      }
      await db.close();
    });
  }

  test('a new database has radio_stations', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await expectRadioStationsSchema(db);
  });

  // v13 在 player_state 加 Mix 的五欄（ADR 0031 §決定 11、M3 design §3.1）：既有的列
  // 原樣保留，新欄位都是 NULL（`mode` 空＝一般佇列），M2 的恢復行為不變。
  test('migration from v12 to v13 keeps the stored queue state', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 12,
      newVersion: 13,
      createOld: v12.DatabaseAtV12.new,
      createNew: v13.DatabaseAtV13.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.playerState,
          const v12.PlayerStateData(
            id: 1,
            currentPosition: 3,
            positionMs: 83000,
            loopMode: 'all',
            shuffleEnabled: 1,
            volume: 0.4,
            muted: 1,
            updatedAt: 1790000000000,
          ),
        );
      },
      validateItems: (newDb) async {
        // 使用者的值不變，Mix 的欄位是空的。
        expect(await newDb.select(newDb.playerState).get(), [
          const v13.PlayerStateData(
            id: 1,
            currentPosition: 3,
            positionMs: 83000,
            loopMode: 'all',
            shuffleEnabled: 1,
            volume: 0.4,
            muted: 1,
            updatedAt: 1790000000000,
          ),
        ]);
      },
    );
  });

  Future<void> expectPlayerMixSchema(AppDatabase db) async {
    // 持久化格式：`mode` 的字串寫死，Mix 的四欄都是文字且可空。
    await db.customStatement(
      "INSERT INTO player_state (id, position_ms, loop_mode, shuffle_enabled, "
      "volume, muted, updated_at, mode, mix_plugin_id, mix_id, mix_title, "
      "mix_cursor) VALUES (1, 0, 'off', 0, 1, 0, 1, 'mix', 'youtube', 'RD1', "
      "'My Mix', 'abc')",
    );
    final row = await db
        .customSelect(
          'SELECT mode, mix_plugin_id, mix_id, mix_title, mix_cursor '
          'FROM player_state',
        )
        .getSingle();
    expect(row.data, {
      'mode': 'mix',
      'mix_plugin_id': 'youtube',
      'mix_id': 'RD1',
      'mix_title': 'My Mix',
      'mix_cursor': 'abc',
    });
  }

  for (final from in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]) {
    test('migration from v$from to v13 adds the mix columns', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 13);

      await expectPlayerMixSchema(db);
      await db.close();
    });
  }

  test('a new database has the mix columns', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await expectPlayerMixSchema(db);
  });

  // v14 在 tracks 加分 P 的兩欄（M3 design §3.1、§11.1）：既有的曲目都不是分 P，
  // 原樣保留，新欄位是 NULL。
  test('migration from v13 to v14 keeps the stored tracks', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 13,
      newVersion: 14,
      createOld: v13.DatabaseAtV13.new,
      createNew: v14.DatabaseAtV14.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.tracks,
          const v13.TracksData(
            trackKey: 'bilibili:BV1:100',
            sourceTypeId: 'bilibili',
            sourceId: 'BV1',
            cid: 100,
            title: 'Song',
            uploader: 'Up',
            durationMs: 1000,
            artworkJson: '[{"url":"https://i.example/a.jpg"}]',
            updatedAt: 1790000000000,
          ),
        );
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.tracks).get(), [
          const v14.TracksData(
            trackKey: 'bilibili:BV1:100',
            sourceTypeId: 'bilibili',
            sourceId: 'BV1',
            cid: 100,
            title: 'Song',
            uploader: 'Up',
            durationMs: 1000,
            artworkJson: '[{"url":"https://i.example/a.jpg"}]',
            updatedAt: 1790000000000,
          ),
        ]);
      },
    );
  });

  Future<void> expectTrackPartSchema(AppDatabase db) async {
    // 持久化格式：序號是整數、影片標題是文字，兩欄都可空。
    await db.customStatement(
      "INSERT INTO tracks (track_key, source_type_id, source_id, cid, title, "
      "updated_at, part_index, parent_title) VALUES "
      "('bilibili:BV1:2', 'bilibili', 'BV1', 2, 'Part two', 1, 2, 'Video')",
    );
    await db.customStatement(
      "INSERT INTO tracks (track_key, source_type_id, source_id, title, "
      "updated_at) VALUES ('bilibili:BV2', 'bilibili', 'BV2', 'Single', 1)",
    );
    final rows = await db
        .customSelect(
          'SELECT track_key, part_index, parent_title FROM tracks '
          'ORDER BY track_key',
        )
        .get();
    expect(
      [for (final row in rows) row.data],
      [
        {
          'track_key': 'bilibili:BV1:2',
          'part_index': 2,
          'parent_title': 'Video',
        },
        {'track_key': 'bilibili:BV2', 'part_index': null, 'parent_title': null},
      ],
    );
  }

  for (final from in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]) {
    test('migration from v$from to v14 adds the part columns', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 14);

      await expectTrackPartSchema(db);
      await db.close();
    });
  }

  test('a new database has the part columns', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await expectTrackPartSchema(db);
  });

  // v15 加 playlists 與 playlist_entries（M4 design §3.1）：既有表的資料與使用者值原樣保留，
  // 新表升級後是空的。
  test('migration from v14 to v15 keeps existing data', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 14,
      newVersion: 15,
      createOld: v14.DatabaseAtV14.new,
      createNew: v15.DatabaseAtV15.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.appearanceSettings,
          const v14.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        );
        batch.insert(
          oldDb.tracks,
          const v14.TracksData(
            trackKey: 'bilibili:BV1:100',
            sourceTypeId: 'bilibili',
            sourceId: 'BV1',
            cid: 100,
            title: 'Song',
            updatedAt: 1790000000000,
          ),
        );
        batch.insert(
          oldDb.queueEntries,
          const v14.QueueEntriesData(position: 0, trackKey: 'bilibili:BV1:100'),
        );
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.appearanceSettings).get(), [
          const v15.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        ]);
        expect(await newDb.select(newDb.tracks).get(), [
          const v15.TracksData(
            trackKey: 'bilibili:BV1:100',
            sourceTypeId: 'bilibili',
            sourceId: 'BV1',
            cid: 100,
            title: 'Song',
            updatedAt: 1790000000000,
          ),
        ]);
        expect(await newDb.select(newDb.queueEntries).get(), [
          const v15.QueueEntriesData(position: 0, trackKey: 'bilibili:BV1:100'),
        ]);
        expect(await newDb.select(newDb.playlists).get(), isEmpty);
        expect(await newDb.select(newDb.playlistEntries).get(), isEmpty);
      },
    );
  });

  Future<List<String>> indexesOf(AppDatabase db, String table) async => [
    for (final row
        in await db.customSelect("PRAGMA index_list('$table')").get())
      row.read<String>('name'),
  ];

  Future<void> expectPlaylistSchema(AppDatabase db) async {
    expect(
      await indexesOf(db, 'playlist_entries'),
      containsAll(['playlist_entries_playlist', 'playlist_entries_track_key']),
    );
    // 持久化格式：種類是寫死的字串，遠端三欄有預設。
    await db.customStatement(
      "INSERT INTO playlists (kind, name, sort_order, created_at, updated_at) "
      "VALUES ('local', 'Mine', 0, 1, 1)",
    );
    await db.customStatement(
      "INSERT INTO tracks (track_key, source_type_id, source_id, title, "
      "updated_at) VALUES ('p:1', 'p', '1', 'T', 1)",
    );
    await db.customStatement(
      "INSERT INTO playlist_entries (playlist_id, position, track_key) "
      "VALUES (1, 0, 'p:1')",
    );
    final row = await db
        .customSelect(
          'SELECT kind, remote_item_id, unavailable, seen_generation '
          'FROM playlists, playlist_entries',
        )
        .getSingle();
    expect(row.data, {
      'kind': 'local',
      'remote_item_id': null,
      'unavailable': 0,
      'seen_generation': 0,
    });
  }

  for (final from in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]) {
    test('migration from v$from to v15 adds the playlist tables', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 15);

      await expectPlaylistSchema(db);
      await db.close();
    });
  }

  test('a new database has the playlist tables', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await expectPlaylistSchema(db);
  });

  // v16 加 playlist_remote（M4 design §3.1）：既有表的資料與使用者值原樣保留，新表升級後是空的。
  test('migration from v15 to v16 keeps existing data', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 15,
      newVersion: 16,
      createOld: v15.DatabaseAtV15.new,
      createNew: v16.DatabaseAtV16.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.appearanceSettings,
          const v15.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        );
        batch.insert(
          oldDb.tracks,
          const v15.TracksData(
            trackKey: 'bilibili:BV1:100',
            sourceTypeId: 'bilibili',
            sourceId: 'BV1',
            cid: 100,
            title: 'Song',
            updatedAt: 1790000000000,
          ),
        );
        batch.insert(
          oldDb.playlists,
          const v15.PlaylistsData(
            id: 1,
            kind: 'local',
            name: 'Mine',
            sortOrder: 0,
            createdAt: 1790000000000,
            updatedAt: 1790000000000,
          ),
        );
        batch.insert(
          oldDb.playlistEntries,
          const v15.PlaylistEntriesData(
            id: 1,
            playlistId: 1,
            position: 0,
            trackKey: 'bilibili:BV1:100',
            unavailable: 0,
            seenGeneration: 0,
          ),
        );
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.appearanceSettings).get(), [
          const v16.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        ]);
        expect(await newDb.select(newDb.playlists).get(), [
          const v16.PlaylistsData(
            id: 1,
            kind: 'local',
            name: 'Mine',
            sortOrder: 0,
            createdAt: 1790000000000,
            updatedAt: 1790000000000,
          ),
        ]);
        expect(await newDb.select(newDb.playlistEntries).get(), [
          const v16.PlaylistEntriesData(
            id: 1,
            playlistId: 1,
            position: 0,
            trackKey: 'bilibili:BV1:100',
            unavailable: 0,
            seenGeneration: 0,
          ),
        ]);
        expect(await newDb.select(newDb.playlistRemote).get(), isEmpty);
      },
    );
  });

  Future<void> expectPlaylistRemoteSchema(AppDatabase db) async {
    // 唯一鍵（plugin_id, remote_id）是一個唯一索引。
    final unique = [
      for (final index
          in await db
              .customSelect("PRAGMA index_list('playlist_remote')")
              .get())
        if (index.read<int>('unique') == 1) index.read<String>('name'),
    ];
    expect(unique, hasLength(1));
    expect(
      [
        for (final column
            in await db
                .customSelect("PRAGMA index_info('${unique.single}')")
                .get())
          column.read<String>('name'),
      ],
      ['plugin_id', 'remote_id'],
    );
    for (final id in [1, 2]) {
      await db.customStatement(
        'INSERT INTO playlists (kind, name, sort_order, created_at, '
        "updated_at) VALUES ('imported', 'P$id', $id, 1, 1)",
      );
    }
    await db.customStatement(
      'INSERT INTO playlist_remote (playlist_id, plugin_id, remote_id) '
      "VALUES (1, 'fmp-test', 'pl-basic')",
    );
    // 持久化格式：旗標預設假、代際 0、狀態是寫死的字串，其餘為空。
    final row = await db
        .customSelect('SELECT * FROM playlist_remote')
        .getSingle();
    expect(row.data, {
      'playlist_id': 1,
      'plugin_id': 'fmp-test',
      'remote_id': 'pl-basic',
      'owner_name': null,
      'writable': 0,
      'name_overridden': 0,
      'description_overridden': 0,
      'artwork_overridden': 0,
      'refresh_interval_hours': null,
      'last_refreshed_at': null,
      'last_result': null,
      'status': 'active',
      'refresh_generation': 0,
    });
    // 同一個（插件, 遠端 id）寫不進第二列；不同遠端 id 可以。
    await expectLater(
      db.customStatement(
        'INSERT INTO playlist_remote (playlist_id, plugin_id, remote_id) '
        "VALUES (2, 'fmp-test', 'pl-basic')",
      ),
      throwsA(
        isA<SqliteException>().having(
          (e) => e.message,
          'message',
          contains('UNIQUE constraint failed'),
        ),
      ),
    );
    await db.customStatement(
      'INSERT INTO playlist_remote (playlist_id, plugin_id, remote_id) '
      "VALUES (2, 'fmp-test', 'pl-grow')",
    );
    // 歌單刪除時連帶刪除。
    await db.customStatement('DELETE FROM playlists WHERE id = 1');
    expect(
      [
        for (final r
            in await db
                .customSelect('SELECT remote_id FROM playlist_remote')
                .get())
          r.read<String>('remote_id'),
      ],
      ['pl-grow'],
    );
  }

  for (final from in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]) {
    test('migration from v$from to v16 adds playlist_remote', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 16);

      await expectPlaylistRemoteSchema(db);
      await db.close();
    });
  }

  test('a new database has playlist_remote', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await expectPlaylistRemoteSchema(db);
  });

  // v17 在 network_settings 加排行刷新間隔、建 chart_settings（M4 design §3.1、§3.3）：
  // 既有的列原樣保留（使用者設定過的值不變），新欄位是空的＝沒設定過。
  test('migration from v16 to v17 keeps existing data', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 16,
      newVersion: 17,
      createOld: v16.DatabaseAtV16.new,
      createNew: v17.DatabaseAtV17.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.networkSettings,
          const v16.NetworkSettingsData(
            id: 1,
            cacheLimitMb: 512,
            radioStatusIntervalMinutes: 3,
          ),
        );
        batch.insert(
          oldDb.sourceSettings,
          const v16.SourceSettingsData(
            pluginId: 'fmp-test',
            browseAsLoggedIn: 1,
          ),
        );
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.networkSettings).get(), [
          const v17.NetworkSettingsData(
            id: 1,
            cacheLimitMb: 512,
            radioStatusIntervalMinutes: 3,
          ),
        ]);
        expect(await newDb.select(newDb.sourceSettings).get(), [
          const v17.SourceSettingsData(
            pluginId: 'fmp-test',
            browseAsLoggedIn: 1,
          ),
        ]);
        expect(await newDb.select(newDb.chartSettings).get(), isEmpty);
      },
    );
  });

  Future<void> expectChartSettingsSchema(AppDatabase db) async {
    // 主鍵是（插件, 榜單）；兩個設定欄位都可空，空＝沒設定過；不建外鍵到 installed_plugins。
    await db.customStatement(
      'INSERT INTO chart_settings (plugin_id, chart_id, enabled, sort_order) '
      "VALUES ('fmp-test', 'hot', 0, 2)",
    );
    await db.customStatement(
      'INSERT INTO chart_settings (plugin_id, chart_id) '
      "VALUES ('fmp-test', 'new')",
    );
    final rows = await db
        .customSelect(
          'SELECT plugin_id, chart_id, enabled, sort_order '
          'FROM chart_settings ORDER BY chart_id',
        )
        .get();
    expect(
      [for (final row in rows) row.data],
      [
        {
          'plugin_id': 'fmp-test',
          'chart_id': 'hot',
          'enabled': 0,
          'sort_order': 2,
        },
        {
          'plugin_id': 'fmp-test',
          'chart_id': 'new',
          'enabled': null,
          'sort_order': null,
        },
      ],
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO chart_settings (plugin_id, chart_id) VALUES ('fmp-test', 'hot')",
      ),
      throwsA(anything),
    );
    // 另一個插件的同名榜單是另一列。
    await db.customStatement(
      "INSERT INTO chart_settings (plugin_id, chart_id) VALUES ('other', 'hot')",
    );
  }

  for (final from in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]) {
    test('migration from v$from to v17 adds chart_settings and the chart '
        'interval column', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 17);

      await expectChartSettingsSchema(db);
      // 沒有設定過：新欄位是 NULL。
      if (from >= 2) {
        await db.customStatement(
          'INSERT OR IGNORE INTO network_settings (id) VALUES (1)',
        );
        final interval = await db
            .customSelect(
              'SELECT chart_refresh_interval_minutes AS v FROM network_settings',
            )
            .getSingle();
        expect(interval.data['v'], equals(null));
      }
      await db.close();
    });
  }

  test('a new database has chart_settings', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await expectChartSettingsSchema(db);
  });

  // v18 加 match_results、track_origins 與 source_settings 的匹配兩欄（M4 design §3.1、§8.3）：
  // 既有表的資料與使用者值原樣保留，新欄位是空的（沒設定過＝依預設），新表升級後是空的。
  test('migration from v17 to v18 keeps existing data', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 17,
      newVersion: 18,
      createOld: v17.DatabaseAtV17.new,
      createNew: v18.DatabaseAtV18.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.sourceSettings,
          const v17.SourceSettingsData(
            pluginId: 'fmp-test',
            browseAsLoggedIn: 0,
          ),
        );
        batch.insert(
          oldDb.tracks,
          const v17.TracksData(
            trackKey: 'fmp-test:a',
            sourceTypeId: 'fmp-test',
            sourceId: 'a',
            title: 'Song a',
            updatedAt: 1,
          ),
        );
        batch.insert(
          oldDb.chartSettings,
          const v17.ChartSettingsData(
            pluginId: 'fmp-test',
            chartId: 'hot',
            enabled: 0,
            sortOrder: 1,
          ),
        );
      },
      validateItems: (newDb) async {
        // 使用者設定過的 browse_as_logged_in 不變；匹配兩欄是空的。
        expect(await newDb.select(newDb.sourceSettings).get(), [
          const v18.SourceSettingsData(
            pluginId: 'fmp-test',
            browseAsLoggedIn: 0,
          ),
        ]);
        expect(await newDb.select(newDb.tracks).get(), [
          const v18.TracksData(
            trackKey: 'fmp-test:a',
            sourceTypeId: 'fmp-test',
            sourceId: 'a',
            title: 'Song a',
            updatedAt: 1,
          ),
        ]);
        expect(await newDb.select(newDb.chartSettings).get(), [
          const v18.ChartSettingsData(
            pluginId: 'fmp-test',
            chartId: 'hot',
            enabled: 0,
            sortOrder: 1,
          ),
        ]);
        expect(await newDb.select(newDb.matchResults).get(), isEmpty);
        expect(await newDb.select(newDb.trackOrigins).get(), isEmpty);
      },
    );
  });

  Future<void> expectMatchSchema(AppDatabase db) async {
    await db.customStatement('PRAGMA foreign_keys = ON');
    await db.customStatement(
      "INSERT INTO tracks (track_key, source_type_id, source_id, title, "
      "updated_at) VALUES ('p:1', 'p', '1', 'T', 0)",
    );
    // 主鍵是（來源插件, 外部 id）；選定的曲目可空（匹配失敗或排除），user_selected 預設假；
    // 不建外鍵到 installed_plugins。
    await db.customStatement(
      'INSERT INTO match_results (origin_plugin_id, origin_id, title, '
      "selected_track_key, score) VALUES ('spotify', 's1', 'Song', 'p:1', 0.8)",
    );
    await db.customStatement(
      'INSERT INTO match_results (origin_plugin_id, origin_id, title) '
      "VALUES ('spotify', 's2', 'Other')",
    );
    final rows = await db
        .customSelect(
          'SELECT origin_id, artists, duration_ms, selected_track_key, score, '
          'user_selected FROM match_results ORDER BY origin_id',
        )
        .get();
    expect(
      [for (final row in rows) row.data],
      [
        {
          'origin_id': 's1',
          'artists': null,
          'duration_ms': null,
          'selected_track_key': 'p:1',
          'score': 0.8,
          'user_selected': 0,
        },
        {
          'origin_id': 's2',
          'artists': null,
          'duration_ms': null,
          'selected_track_key': null,
          'score': null,
          'user_selected': 0,
        },
      ],
    );
    await expectLater(
      db.customStatement(
        'INSERT INTO match_results (origin_plugin_id, origin_id, title) '
        "VALUES ('spotify', 's1', 'Again')",
      ),
      throwsA(anything),
    );
    // 選定的曲目要在 tracks 裡，而且被參照時刪不掉（RESTRICT）。
    await expectLater(
      db.customStatement(
        'INSERT INTO match_results (origin_plugin_id, origin_id, title, '
        "selected_track_key) VALUES ('qqmusic', 'q1', 'Song', 'p:missing')",
      ),
      throwsA(anything),
    );
    await db.customStatement(
      'INSERT INTO track_origins (track_key, origin_plugin_id, origin_id) '
      "VALUES ('p:1', 'spotify', 's1')",
    );
    // 同一首可以同時是另一個插件的匹配結果；同一個插件只有一列。
    await db.customStatement(
      'INSERT INTO track_origins (track_key, origin_plugin_id, origin_id) '
      "VALUES ('p:1', 'qqmusic', 'q1')",
    );
    await expectLater(
      db.customStatement(
        'INSERT INTO track_origins (track_key, origin_plugin_id, origin_id) '
        "VALUES ('p:1', 'spotify', 's9')",
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement("DELETE FROM tracks WHERE track_key = 'p:1'"),
      throwsA(anything),
      reason: 'match_results restricts the deletion',
    );
    // 不再被 match_results 參照時可以刪，track_origins 連帶刪除。
    await db.customStatement(
      "UPDATE match_results SET selected_track_key = NULL WHERE origin_id = 's1'",
    );
    await db.customStatement("DELETE FROM tracks WHERE track_key = 'p:1'");
    final origins = await db
        .customSelect('SELECT COUNT(*) AS n FROM track_origins')
        .getSingle();
    expect(origins.data['n'], 0);
  }

  for (var from = 1; from <= 17; from++) {
    test('migration from v$from to v18 adds the match tables and the match '
        'target columns', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 18);

      await expectMatchSchema(db);
      // 沒有設定過：新欄位是 NULL。
      await db.customStatement(
        "INSERT INTO source_settings (plugin_id) VALUES ('x')",
      );
      final row = await db
          .customSelect(
            'SELECT match_target, match_rank FROM source_settings '
            "WHERE plugin_id = 'x'",
          )
          .getSingle();
      expect(row.data, {'match_target': null, 'match_rank': null});
      await db.close();
    });
  }

  test('a new database has the match tables', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await expectMatchSchema(db);
  });

  // 孤兒清理刪曲目時 RESTRICT 的檢查要靠 match_results.selected_track_key 的索引（理由同
  // queue_entries_track_key）。升級來的與全新建的都要有。
  Future<List<String>> matchResultIndexes(AppDatabase db) async => [
    for (final row
        in await db.customSelect("PRAGMA index_list('match_results')").get())
      row.read<String>('name'),
  ];

  test(
    'migration from v17 to v18 indexes match_results.selected_track_key',
    () async {
      final schema = await verifier.schemaAt(17);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 18);

      expect(await matchResultIndexes(db), contains('match_results_selected'));
      await db.close();
    },
  );

  test('a new database indexes match_results.selected_track_key', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await matchResultIndexes(db), contains('match_results_selected'));
  });

  // v19 加 legacy_imports 與 legacy_playlist_ids（M5 design §6.4）：既有的資料與使用者設定過的值
  // 一個都不能變，新表升級後是空的。
  test('migration from v18 to v19 keeps existing data', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 18,
      newVersion: 19,
      createOld: v18.DatabaseAtV18.new,
      createNew: v19.DatabaseAtV19.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.appearanceSettings,
          const v18.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        );
        batch.insert(
          oldDb.playlists,
          const v18.PlaylistsData(
            id: 1,
            kind: 'local',
            name: 'Mine',
            sortOrder: 0,
            createdAt: 1790000000000,
            updatedAt: 1790000000001,
          ),
        );
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.appearanceSettings).get(), [
          const v19.AppearanceSettingsData(
            id: 1,
            themeMode: 'dark',
            locale: 'zh-CN',
          ),
        ]);
        expect(await newDb.select(newDb.playlists).get(), [
          const v19.PlaylistsData(
            id: 1,
            kind: 'local',
            name: 'Mine',
            sortOrder: 0,
            createdAt: 1790000000000,
            updatedAt: 1790000000001,
          ),
        ]);
        expect(await newDb.select(newDb.legacyImports).get(), isEmpty);
        expect(await newDb.select(newDb.legacyPlaylistIds).get(), isEmpty);
      },
    );
  });

  Future<void> expectLegacyImportSchema(AppDatabase db) async {
    await db.customStatement('PRAGMA foreign_keys = ON');
    await db.customStatement(
      "INSERT INTO playlists (kind, name, sort_order, created_at, updated_at) "
      "VALUES ('local', 'Mine', 0, 1, 1)",
    );
    await db.customStatement(
      'INSERT INTO legacy_imports (source, imported_at, summary_json) '
      "VALUES ('database', 1790000000000, '{}')",
    );
    final imports = await db
        .customSelect(
          'SELECT id, legacy_schema_version, backup_version, acknowledged '
          'FROM legacy_imports',
        )
        .getSingle();
    // 兩個版本欄可空，acknowledged 預設假。
    expect(imports.data, {
      'id': 1,
      'legacy_schema_version': null,
      'backup_version': null,
      'acknowledged': 0,
    });
    await db.customStatement(
      'INSERT INTO legacy_playlist_ids (legacy_import_id, legacy_playlist_id, '
      'playlist_id) VALUES (1, 7, 1)',
    );
    // 主鍵是（匯入紀錄, 舊歌單 id）。
    await expectLater(
      db.customStatement(
        'INSERT INTO legacy_playlist_ids (legacy_import_id, '
        'legacy_playlist_id, playlist_id) VALUES (1, 7, 1)',
      ),
      throwsA(anything),
    );
    // 兩個外鍵都要成立。
    await expectLater(
      db.customStatement(
        'INSERT INTO legacy_playlist_ids (legacy_import_id, '
        'legacy_playlist_id, playlist_id) VALUES (99, 8, 1)',
      ),
      throwsA(anything),
      reason: 'the import record must exist',
    );
    await expectLater(
      db.customStatement(
        'INSERT INTO legacy_playlist_ids (legacy_import_id, '
        'legacy_playlist_id, playlist_id) VALUES (1, 8, 99)',
      ),
      throwsA(anything),
      reason: 'the playlist must exist',
    );
    // 歌單刪了對照就沒了；匯入紀錄刪了也是。
    await db.customStatement('DELETE FROM playlists WHERE id = 1');
    var mappings = await db
        .customSelect('SELECT COUNT(*) AS n FROM legacy_playlist_ids')
        .getSingle();
    expect(mappings.data['n'], 0);
    await db.customStatement(
      "INSERT INTO playlists (kind, name, sort_order, created_at, updated_at) "
      "VALUES ('local', 'Again', 0, 1, 1)",
    );
    await db.customStatement(
      'INSERT INTO legacy_playlist_ids (legacy_import_id, legacy_playlist_id, '
      'playlist_id) VALUES (1, 7, 2)',
    );
    await db.customStatement('DELETE FROM legacy_imports WHERE id = 1');
    mappings = await db
        .customSelect('SELECT COUNT(*) AS n FROM legacy_playlist_ids')
        .getSingle();
    expect(mappings.data['n'], 0);
  }

  for (var from = 1; from <= 18; from++) {
    test(
      'migration from v$from to v19 adds the legacy import tables',
      () async {
        final schema = await verifier.schemaAt(from);
        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, 19);

        await expectLegacyImportSchema(db);
        await db.close();
      },
    );
  }

  test('a new database has the legacy import tables', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await expectLegacyImportSchema(db);
  });

  test(
    'migration from v19 to v20 keeps existing data and user values',
    () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 19,
        newVersion: 20,
        createOld: v19.DatabaseAtV19.new,
        createNew: v20.DatabaseAtV20.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          // 使用者設定過的值，升級後不能變。
          batch.insert(
            oldDb.appearanceSettings,
            const v19.AppearanceSettingsData(
              id: 1,
              themeMode: 'dark',
              locale: 'zh-CN',
            ),
          );
          batch.insert(
            oldDb.playlists,
            const v19.PlaylistsData(
              id: 1,
              kind: 'local',
              name: 'Mine',
              sortOrder: 0,
              createdAt: 1790000000000,
              updatedAt: 1790000000001,
            ),
          );
        },
        validateItems: (newDb) async {
          // 新的兩欄是空的＝沒設定過，預設只在 resolveAppearance 套用。
          expect(await newDb.select(newDb.appearanceSettings).get(), [
            const v20.AppearanceSettingsData(
              id: 1,
              themeMode: 'dark',
              locale: 'zh-CN',
              seedColor: null,
              fontFamily: null,
            ),
          ]);
          expect(await newDb.select(newDb.playlists).get(), [
            const v20.PlaylistsData(
              id: 1,
              kind: 'local',
              name: 'Mine',
              sortOrder: 0,
              createdAt: 1790000000000,
              updatedAt: 1790000000001,
            ),
          ]);
        },
      );
    },
  );

  for (var from = 1; from <= 19; from++) {
    test('migration from v$from to v20 adds the appearance columns', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 20);

      await db.customStatement(
        'INSERT INTO appearance_settings (id, seed_color, font_family) '
        "VALUES (1, 4284955319, 'serif') "
        'ON CONFLICT (id) DO UPDATE SET seed_color = 4284955319, '
        "font_family = 'serif'",
      );
      final row = await db
          .customSelect(
            'SELECT seed_color, font_family FROM appearance_settings',
          )
          .getSingle();
      expect(row.data, {'seed_color': 4284955319, 'font_family': 'serif'});
      await db.close();
    });
  }

  // v21 加 layout_state.rail_expanded（ADR 0035 §決定 5）：既有的列這一欄是空的，其餘值不變。
  test(
    'migration from v20 to v21 keeps existing data and user values',
    () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 20,
        newVersion: 21,
        createOld: v20.DatabaseAtV20.new,
        createNew: v21.DatabaseAtV21.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          // 使用者記過的值，升級後不能變。
          batch.insert(
            oldDb.layoutState,
            const v20.LayoutStateData(
              id: 1,
              playerTab: 'queue',
              panelExpanded: 0,
              panelWidth: 480,
            ),
          );
        },
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.layoutState).get(), [
            const v21.LayoutStateData(
              id: 1,
              playerTab: 'queue',
              panelExpanded: 0,
              panelWidth: 480,
              railExpanded: null,
            ),
          ]);
        },
      );
    },
  );

  for (var from = 1; from <= 20; from++) {
    test(
      'migration from v$from to v21 adds layout_state.rail_expanded',
      () async {
        final schema = await verifier.schemaAt(from);
        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, 21);

        await db.customStatement(
          'INSERT INTO layout_state (id, rail_expanded) VALUES (1, 1) '
          'ON CONFLICT (id) DO UPDATE SET rail_expanded = 1',
        );
        final row = await db
            .customSelect('SELECT rail_expanded FROM layout_state')
            .getSingle();
        expect(row.data, {'rail_expanded': 1});
        await db.close();
      },
    );
  }

  // v22 加 search_history（ADR 0035 §決定 9）：新表升級後是空的，其餘資料不變。
  test(
    'migration from v21 to v22 keeps existing data and adds an empty table',
    () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 21,
        newVersion: 22,
        createOld: v21.DatabaseAtV21.new,
        createNew: v22.DatabaseAtV22.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          // 使用者記過的值，升級後不能變。
          batch.insert(
            oldDb.layoutState,
            const v21.LayoutStateData(
              id: 1,
              playerTab: 'queue',
              panelExpanded: 0,
              panelWidth: 480,
              railExpanded: 1,
            ),
          );
        },
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.layoutState).get(), [
            const v22.LayoutStateData(
              id: 1,
              playerTab: 'queue',
              panelExpanded: 0,
              panelWidth: 480,
              railExpanded: 1,
            ),
          ]);
          expect(await newDb.select(newDb.searchHistory).get(), isEmpty);
        },
      );
    },
  );

  for (var from = 1; from <= 21; from++) {
    test('migration from v$from to v22 adds search_history', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 22);

      await db.customStatement(
        "INSERT INTO search_history (query, searched_at) VALUES ('a', 5)",
      );
      final row = await db
          .customSelect('SELECT query, searched_at FROM search_history')
          .getSingle();
      expect(row.data, {'query': 'a', 'searched_at': 5});
      // 主鍵是 query：同一個關鍵字插不進第二列。
      await expectLater(
        db.customStatement(
          "INSERT INTO search_history (query, searched_at) VALUES ('a', 6)",
        ),
        throwsA(anything),
      );
      await db.close();
    });
  }

  // v23 刪 layout_state.player_tab（ADR 0035 §決定 5）：其餘欄位的值不變。
  test(
    'migration from v22 to v23 drops player_tab and keeps the other values',
    () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 22,
        newVersion: 23,
        createOld: v22.DatabaseAtV22.new,
        createNew: v23.DatabaseAtV23.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch.insert(
            oldDb.layoutState,
            const v22.LayoutStateData(
              id: 1,
              playerTab: 'queue',
              panelExpanded: 0,
              panelWidth: 480,
              railExpanded: 1,
            ),
          );
        },
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.layoutState).get(), [
            const v23.LayoutStateData(
              id: 1,
              panelExpanded: 0,
              panelWidth: 480,
              railExpanded: 1,
            ),
          ]);
        },
      );
    },
  );

  for (var from = 1; from <= 22; from++) {
    test('migration from v$from to v23 leaves no player_tab column', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 23);

      final columns = await db
          .customSelect('PRAGMA table_info(layout_state)')
          .get();
      expect(columns.map((c) => c.read<String>('name')), [
        'id',
        'panel_expanded',
        'panel_width',
        'rail_expanded',
      ]);
      await db.close();
    });
  }
}
