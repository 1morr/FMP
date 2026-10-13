import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/database_inspector.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/track_info.dart';

import '../../support/memory_database.dart';

// Debug 頁資料庫區塊的唯讀查詢（M3 PR 14a，ADR 0025 §決定 8）。

TrackInfo track(String id, {String? title}) => TrackInfo(
  sourceTypeId: 'fmp-test',
  sourceId: id,
  title: title ?? 'Song $id',
);

void main() {
  late AppDatabase database;
  late DatabaseInspector inspector;

  setUp(() {
    database = memoryDatabase();
    inspector = DatabaseInspector(database, Redactor());
  });

  Future<void> installPlugin(String id) => PluginRepository(database).install(
    InstalledPlugin(
      id: id,
      version: '1.0.0',
      manifestJson: '{}',
      script: '',
      installedAt: DateTime.utc(2026),
    ),
  );

  group('tables and rows', () {
    test('lists every table of the database with its row count', () async {
      await TracksRepository(database).upsert([track('a'), track('b')]);

      final tables = await inspector.tables();

      expect([
        for (final table in tables) table.name,
      ], containsAll(['tracks', 'plugin_storage', 'installed_plugins']));
      expect(tables.length, database.allTables.length);
      expect(tables.firstWhere((table) => table.name == 'tracks').count, 2);
      expect(tables.firstWhere((table) => table.name == 'accounts').count, 0);
    });

    test('pages are 50 rows long', () async {
      await TracksRepository(database)
          .upsert([for (var i = 0; i < 120; i++) track('t$i')]);

      final first = await inspector.rows('tracks', 0);
      final second = await inspector.rows('tracks', 1);
      final third = await inspector.rows('tracks', 2);
      final beyond = await inspector.rows('tracks', 3);

      expect(DatabaseInspector.pageSize, 50);
      expect(
        [first.rows.length, second.rows.length, third.rows.length],
        [50, 50, 20],
      );
      expect(beyond.rows, isEmpty);
      expect(first.total, 120);
      expect(first.columns, contains('track_key'));
      // 三頁沒有重複的列。
      final keyIndex = first.columns.indexOf('track_key');
      final seen = {
        for (final page in [first, second, third])
          for (final row in page.rows) row[keyIndex],
      };
      expect(seen, hasLength(120));
    });

    test('an empty table still has its columns', () async {
      final page = await inspector.rows('accounts', 0);

      expect(page.rows, isEmpty);
      expect(page.total, 0);
      expect(page.columns, contains('plugin_id'));
    });

    test('shows stored values: NULL stays null, times are epoch ms', () async {
      await TracksRepository(database).upsert([track('a')]);

      final page = await inspector.rows('tracks', 0);
      final row = page.rows.single;

      expect(row[page.columns.indexOf('uploader')], isNull);
      expect(row[page.columns.indexOf('title')], 'Song a');
      expect(int.tryParse(row[page.columns.indexOf('updated_at')]!), isNotNull);
    });

    test('the value column of plugin_storage is masked as a whole', () async {
      await installPlugin('fmp-test');
      await PluginStorageRepository(database)
          .write('fmp-test', 'session', 'FAKE_COOKIE_VALUE');

      final page = await inspector.rows('plugin_storage', 0);
      final row = page.rows.single;

      expect(row[page.columns.indexOf('value')], redactedValue);
      expect(row[page.columns.indexOf('key')], 'session');
      expect(row.join(), isNot(contains('FAKE_COOKIE_VALUE')));
    });

    // 插件原始碼可達 800 KB：整份跑遮蔽會讓開表卡上百毫秒，所以只顯示長度。
    test(
      'the script column of installed_plugins shows only its length',
      () async {
        const script = 'export default { name: "FAKE_SCRIPT_BODY" };';
        await PluginRepository(database).install(
          InstalledPlugin(
            id: 'fmp-test',
            version: '1.0.0',
            manifestJson: '{}',
            script: script,
            installedAt: DateTime.utc(2026),
          ),
        );

        final page = await inspector.rows('installed_plugins', 0);
        final row = page.rows.single;

        expect(
          row[page.columns.indexOf('script')],
          '<${script.length} characters>',
        );
        expect(row[page.columns.indexOf('id')], 'fmp-test');
        expect(row.join(), isNot(contains('FAKE_SCRIPT_BODY')));
      },
    );

    test('values in other tables go through the redactor', () async {
      final redactor = Redactor()..registerSecret('FAKE_SECRET_VALUE');
      await TracksRepository(database).upsert([
        track('a', title: 'x token=FAKE_TOKEN_VALUE y FAKE_SECRET_VALUE'),
      ]);

      final page = await DatabaseInspector(
        database,
        redactor,
      ).rows('tracks', 0);
      final title = page.rows.single[page.columns.indexOf('title')]!;

      expect(title, isNot(contains('FAKE_TOKEN_VALUE')));
      expect(title, isNot(contains('FAKE_SECRET_VALUE')));
      expect(title, contains(redactedValue));
    });

    test('only the tables of the database can be read', () async {
      await expectLater(
        inspector.rows('tracks"; DROP TABLE tracks; --', 0),
        throwsArgumentError,
      );
      await expectLater(
        inspector.rows('sqlite_master', 0),
        throwsArgumentError,
      );
      await expectLater(inspector.rows('tracks', -1), throwsRangeError);
    });
  });

  group('check', () {
    test('a clean database has no problems', () async {
      final report = await inspector.check();

      expect(report.hasProblems, isFalse);
      expect(report.integrityMessages, isEmpty);
      expect(report.foreignKeyViolations, isEmpty);
      expect(report.orphanTracks, 0);
    });

    test('a row that breaks a foreign key is listed', () async {
      await database.customStatement('PRAGMA foreign_keys = OFF');
      await database.customStatement(
        'INSERT INTO plugin_storage (plugin_id, key, value) '
        "VALUES ('missing-plugin', 'k', 'v')",
      );
      await database.customStatement('PRAGMA foreign_keys = ON');

      final report = await inspector.check();

      expect(report.hasProblems, isTrue);
      expect(report.foreignKeyViolations, hasLength(1));
      final violation = report.foreignKeyViolations.single;
      expect(violation.table, 'plugin_storage');
      expect(violation.parent, 'installed_plugins');
      expect(violation.rowId, isNotNull);
      expect(report.integrityMessages, isEmpty);
    });

    test('the orphan count is what deleteOrphans would delete', () async {
      final tracks = TracksRepository(database);
      await tracks.upsert([
        track('queued'),
        track('orphan1'),
        track('orphan2'),
        track('listened'),
      ]);
      await PlayHistoryRepository(database).record(
        track('listened'),
        playedAt: DateTime.utc(2026, 10, 14),
        limit: 100,
      );
      await QueueRepository(database).write(
        edit: QueueRangeEdit(from: 0, removed: 0, inserted: [track('queued')]),
        player: const PlayerState(
          currentPosition: 0,
          position: Duration.zero,
          loopMode: LoopMode.off,
          shuffleEnabled: false,
          volume: 1,
          muted: false,
        ),
      );

      final report = await inspector.check();
      expect(report.orphanTracks, 2);
      // 孤兒不算損壞。
      expect(report.hasProblems, isFalse);

      expect(await tracks.deleteOrphans(), report.orphanTracks);
      expect((await inspector.check()).orphanTracks, 0);
    });
  });
}
