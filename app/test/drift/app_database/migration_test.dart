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
}
