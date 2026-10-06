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
}
