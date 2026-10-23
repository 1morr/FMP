import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/import/legacy_imports_repository.dart';
import 'package:fmp/domain/legacy_import.dart';

import '../../support/memory_database.dart';

void main() {
  test(
    'a database without records has none and nothing unacknowledged',
    () async {
      final repository = LegacyImportsRepository(memoryDatabase());

      expect(await repository.hasAny(), isFalse);
      expect(await repository.latestUnacknowledged(), isNull);
    },
  );

  test('reads the newest record that has not been acknowledged', () async {
    final database = memoryDatabase();
    final repository = LegacyImportsRepository(database);
    Future<void> insert(String source, int importedAt) =>
        database.customStatement(
          'INSERT INTO legacy_imports (source, imported_at, backup_version, '
          "summary_json) VALUES ('$source', $importedAt, 5, "
          '\'{"collections":{},"unimportedSettings":[],"reloginPlatforms":["netease"]}\')',
        );
    await insert('database', 1790000000000);
    await insert('backup', 1790000001000);

    expect(await repository.hasAny(), isTrue);
    final latest = (await repository.latestUnacknowledged())!;
    expect(latest.id, 2);
    expect(latest.source, LegacyImportSource.backup);
    expect(
      latest.importedAt,
      DateTime.fromMillisecondsSinceEpoch(1790000001000, isUtc: true),
    );
    expect(latest.backupVersion, 5);
    expect(latest.legacySchemaVersion, isNull);
    expect(latest.summary.reloginPlatforms, ['netease']);
    expect(latest.acknowledged, isFalse);
  });

  test('acknowledging a record moves on to the one before it', () async {
    final database = memoryDatabase();
    final repository = LegacyImportsRepository(database);
    for (final at in [1, 2]) {
      await database.customStatement(
        'INSERT INTO legacy_imports (source, imported_at, summary_json) '
        "VALUES ('database', $at, "
        '\'{"collections":{},"unimportedSettings":[],"reloginPlatforms":[]}\')',
      );
    }

    await repository.acknowledge(2);
    expect((await repository.latestUnacknowledged())!.id, 1);
    await repository.acknowledge(1);
    expect(await repository.latestUnacknowledged(), isNull);
    // 紀錄還在：設定頁的提示看的是「有沒有紀錄」。
    expect(await repository.hasAny(), isTrue);
    // 沒有這一列時什麼都不做。
    await repository.acknowledge(99);
  });

  test(
    'addReloginPlatforms adds to the newest record without repeating',
    () async {
      final database = memoryDatabase();
      final repository = LegacyImportsRepository(database);
      Future<void> insert(String relogin) => database.customStatement(
        'INSERT INTO legacy_imports (source, imported_at, summary_json) '
        "VALUES ('database', 1790000000000, "
        "'{\"collections\":{},\"unimportedSettings\":[\"a\"],"
        "\"reloginPlatforms\":[$relogin]}')",
      );
      await insert('"netease"');
      await insert('');

      await repository.addReloginPlatforms({'bilibili', 'netease'});
      await repository.addReloginPlatforms(const {});

      final latest = (await repository.latestUnacknowledged())!;
      expect(
        latest.summary.reloginPlatforms,
        unorderedEquals(['bilibili', 'netease']),
      );
      expect(latest.summary.unimportedSettings, ['a']);
      await repository.acknowledge(latest.id);
      // 舊的一筆沒動。
      expect(
        (await repository.latestUnacknowledged())!.summary.reloginPlatforms,
        ['netease'],
      );
      // 沒有紀錄時什麼都不做。
      await LegacyImportsRepository(memoryDatabase())
          .addReloginPlatforms({'x'});
    },
  );

  test('referencedPluginIds gathers every table that names a plugin', () async {
    final database = memoryDatabase();
    final repository = LegacyImportsRepository(database);
    expect(await repository.referencedPluginIds(), isEmpty);

    await database.customStatement(
      'INSERT INTO tracks (track_key, source_type_id, source_id, title, '
      "updated_at) VALUES ('bilibili:x', 'bilibili', 'x', 't', 0)",
    );
    final ids = await repository.referencedPluginIds();
    expect(ids, {'bilibili'});
  });

  group('ImportSummary', () {
    const summary = ImportSummary(
      collections: {
        'playlists': CollectionSummary(
          read: 4,
          written: 3,
          skipped: {'mixWithoutSeed': 1},
        ),
        'history': CollectionSummary(read: 10, written: 10),
      },
      unimportedSettings: ['themeColor', 'fontFamily'],
      reloginPlatforms: ['bilibili'],
    );

    test('round-trips through its JSON', () {
      expect(ImportSummary.decode(summary.encode()), summary);
      expect(
        ImportSummary.decode(const ImportSummary().encode()),
        const ImportSummary(),
      );
    });

    test('stored format', () {
      expect(
        summary.encode(),
        '{"collections":{"playlists":{"read":4,"written":3,'
        '"skipped":{"mixWithoutSeed":1},"notes":{}},'
        '"history":{"read":10,"written":10,"skipped":{},"notes":{}}},'
        '"unimportedSettings":["themeColor","fontFamily"],'
        '"reloginPlatforms":["bilibili"]}',
      );
    });
  });
}
