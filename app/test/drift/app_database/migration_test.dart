// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

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
}
