import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/legacy_import.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locator.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/memory_database.dart';
import '../support/fake_data_reset.dart';
import '../support/plugin_page_harness.dart';
import '../support/shell_harness.dart';

// 設定頁「備份與還原」組的「從舊版匯入…」（M5 PR 7，design §3.2、§7.4、§9「設定頁」）。

/// 記下被呼叫的方式、回固定摘要的 [LegacyImport]。
final class _FakeLegacyImport implements LegacyImport {
  _FakeLegacyImport({this.source, this.error});

  final LegacySource? source;

  /// 非空時 [stage]、[stageBackup] 拋這個。
  final Object? error;

  final calls = <String>[];
  AppDatabase? replacingGiven;
  Uint8List? backupGiven;
  Set<String>? loggedInGiven;

  static final summary = const ImportSummary(
    collections: {
      'playlists': CollectionSummary(read: 3, written: 3),
      'tracks': CollectionSummary(read: 120, written: 120),
      'history': CollectionSummary(read: 40, written: 40),
      'radioStations': CollectionSummary(read: 2, written: 2),
      'queue': CollectionSummary(read: 5, written: 5),
      'accounts': CollectionSummary(read: 2, written: 1),
    },
  );

  LegacyStaged _staged() => LegacyStaged(
    file: File('/fake/legacy-import/staging.db'),
    credentials: const {},
    summary: summary,
    keptAccountPluginIds: const {'bilibili'},
  );

  @override
  Future<LegacySource?> locate() async => source;

  @override
  Future<LegacyStaged> stage(
    LegacySource source, {
    void Function(LegacyImportStep step)? progress,
    AppDatabase? replacing,
  }) async {
    calls.add('stage');
    replacingGiven = replacing;
    if (error case final error?) throw error;
    return _staged();
  }

  @override
  Future<LegacyStaged> stageBackup(
    Uint8List bytes, {
    void Function(LegacyImportStep step)? progress,
    AppDatabase? replacing,
  }) async {
    calls.add('stageBackup');
    backupGiven = bytes;
    replacingGiven = replacing;
    if (error case final error?) throw error;
    return _staged();
  }

  @override
  Future<Set<String>> writeCredentials(
    LegacyStaged staged, {
    required Set<String> loggedInPluginIds,
  }) async {
    calls.add('writeCredentials');
    loggedInGiven = loggedInPluginIds;
    return const {};
  }
}

LegacySource _found() => LegacySource(
  database: File('/fake/fmp_database.isar'),
  credentialReader: const NoLegacyCredentialReader(),
);

void main() {
  late AppDatabase database;

  Future<ShellHarness> openBackup(
    WidgetTester tester, {
    required _FakeLegacyImport legacy,
    FakeDataReset? reset,
    FakeFileDialogs? dialogs,
    bool restartsItself = false,
  }) async {
    final h = ShellHarness(
      fileDialogs: dialogs ?? FakeFileDialogs(),
      dataReset: reset ?? FakeDataReset(),
      restartsItself: restartsItself,
      redactor: Redactor(),
      database: database,
      extraOverrides: [legacyImportProvider.overrideWithValue(legacy)],
    );
    await h.pumpShell(tester, size: const Size(1000, 900), collapsePanel: true);
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Backup and restore'));
    await h.loadSettings(tester);
    await tester.pumpAndSettle();
    return h;
  }

  setUp(() => database = memoryDatabase());

  Finder importButton() =>
      find.widgetWithText(OutlinedButton, 'Import from the old version…');
  Finder hint() => find.textContaining('has not been imported yet');

  Future<void> choose(WidgetTester tester, String option) async {
    await tester.tap(importButton());
    await tester.pumpAndSettle();
    expect(
      find.text('Where do you want to import the old data from?'),
      findsOneWidget,
    );
    await tester.tap(find.text(option));
    await tester.pumpAndSettle();
  }

  group('the choice', () {
    testWidgets('the old database cannot be chosen when none is found', (
      tester,
    ) async {
      final legacy = _FakeLegacyImport();
      await openBackup(tester, legacy: legacy);

      await tester.tap(importButton());
      await tester.pumpAndSettle();

      final tile = tester.widget<ListTile>(
        find.widgetWithText(
          ListTile,
          'Old database (not found on this device)',
        ),
      );
      expect(tile.enabled, isFalse);
      // 備份檔仍可選。
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, 'Old backup file (.json)'),
            )
            .enabled,
        isTrue,
      );
      await tester.tap(find.text('Old database (not found on this device)'));
      await tester.pumpAndSettle();
      expect(legacy.calls, isEmpty);
    });

    testWidgets('cancelling the choice does nothing', (tester) async {
      final legacy = _FakeLegacyImport(source: _found());
      final reset = FakeDataReset();
      await openBackup(tester, legacy: legacy, reset: reset);

      await tester.tap(importButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(legacy.calls, isEmpty);
      expect(reset.calls, isEmpty);
    });
  });

  group('the hint', () {
    testWidgets('shows when the old database is found and nothing was '
        'imported before', (tester) async {
      await openBackup(tester, legacy: _FakeLegacyImport(source: _found()));
      expect(hint(), findsOneWidget);
    });

    testWidgets('is not shown when an import was recorded', (tester) async {
      await database.customStatement(
        // 看過了：沒看過的紀錄會讓外殼彈出結果對話框。
        "INSERT INTO legacy_imports (source, imported_at, summary_json, "
        "acknowledged) "
        "VALUES ('database', 1000, '${const ImportSummary().encode()}', 1)",
      );
      await openBackup(tester, legacy: _FakeLegacyImport(source: _found()));
      expect(importButton(), findsOneWidget);
      expect(hint(), findsNothing);
    });

    testWidgets('is not shown when no old database is found', (tester) async {
      await openBackup(tester, legacy: _FakeLegacyImport());
      expect(importButton(), findsOneWidget);
      expect(hint(), findsNothing);
    });
  });

  group('from the old database', () {
    testWidgets('the confirmation lists what is replaced, kept and imported; '
        'confirming replaces, writes credentials and restarts', (tester) async {
      final legacy = _FakeLegacyImport(source: _found());
      final reset = FakeDataReset();
      await openBackup(tester, legacy: legacy, reset: reset);

      await choose(tester, 'Old database');

      // 在目前的資料庫的副本上寫（取代模式）。
      expect(legacy.calls, ['stage']);
      expect(legacy.replacingGiven, same(database));
      expect(find.text('Import from the old version?'), findsOneWidget);
      expect(
        find.textContaining('This replaces the current playlists'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'installed plugins, their settings and the sign-ins on this device '
          'are kept',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('A backup is made first'), findsOneWidget);
      expect(find.text('Playlists: 3'), findsOneWidget);
      expect(find.text('Tracks: 120'), findsOneWidget);
      expect(find.text('Play history: 40'), findsOneWidget);
      expect(find.text('Radio stations: 2'), findsOneWidget);
      expect(find.text('Queue: 5'), findsOneWidget);
      expect(find.text('Accounts: 1'), findsOneWidget);
      expect(find.textContaining('has no queue'), findsNothing);
      expect(
        find.text('The app closes afterwards; open it again yourself.'),
        findsOneWidget,
      );
      expect(reset.calls, isEmpty);

      await tester.tap(find.text('Replace and restart'));
      await tester.pumpAndSettle();

      expect(reset.calls, ['replaceWithImport']);
      expect(reset.importedStaging?.path, endsWith('staging.db'));
      // 憑證只補這台沒登入的平台。
      expect(legacy.calls, ['stage', 'writeCredentials']);
      expect(legacy.loggedInGiven, {'bilibili'});
    });

    testWidgets('cancelling the confirmation deletes the staging file and '
        'replaces nothing', (tester) async {
      final legacy = _FakeLegacyImport(source: _found());
      final reset = FakeDataReset();
      await openBackup(tester, legacy: legacy, reset: reset);

      await choose(tester, 'Old database');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(reset.calls, ['discardImport']);
      expect(legacy.calls, ['stage']);
    });

    testWidgets('a failed import says which step and does not replace', (
      tester,
    ) async {
      final legacy = _FakeLegacyImport(
        source: _found(),
        error: const LegacyImportFailed(LegacyImportStep.verify, 'injected'),
      );
      final reset = FakeDataReset();
      await openBackup(tester, legacy: legacy, reset: reset);

      await choose(tester, 'Old database');

      expect(find.textContaining('The import did not finish'), findsOneWidget);
      expect(find.text('Import from the old version?'), findsNothing);
      expect(reset.calls, isEmpty);
    });

    // 同首次啟動：轉換步驟的原因可能帶著舊資料的值，不進 log；其他步驟的原因照記。
    for (final (step, logged) in [
      (LegacyImportStep.convert, false),
      (LegacyImportStep.write, true),
    ]) {
      testWidgets('the cause of a ${step.name} failure '
          '${logged ? 'is' : 'is not'} logged', (tester) async {
        final legacy = _FakeLegacyImport(
          source: _found(),
          error: LegacyImportFailed(
            step,
            'injected',
            cause: StateError('Fake Song Title'),
          ),
        );
        final h = await openBackup(tester, legacy: legacy);

        await choose(tester, 'Old database');

        expect(
          find.textContaining('The import did not finish'),
          findsOneWidget,
        );
        final logs = [for (final r in h.log.history) r.toJsonLine()];
        expect(logs, isNotEmpty);
        expect(logs.any((line) => line.contains('Fake Song Title')), logged);
      });
    }

    testWidgets('a failure while replacing deletes the staging file', (
      tester,
    ) async {
      final legacy = _FakeLegacyImport(source: _found());
      final reset = FakeDataReset(importError: StateError('disk full'));
      await openBackup(tester, legacy: legacy, reset: reset);

      await choose(tester, 'Old database');
      await tester.tap(find.text('Replace and restart'));
      await tester.pumpAndSettle();

      expect(reset.calls, ['replaceWithImport', 'discardImport']);
      expect(find.textContaining('The import did not finish'), findsOneWidget);
    });
  });

  group('from an old backup file', () {
    final json = Uint8List.fromList('{"version":5}'.codeUnits);

    testWidgets('the confirmation says the queue will be empty', (
      tester,
    ) async {
      final legacy = _FakeLegacyImport();
      final reset = FakeDataReset();
      final dialogs = FakeFileDialogs(
        PickedFile(name: 'fmp_backup.json', bytes: json),
      );
      await openBackup(
        tester,
        legacy: legacy,
        reset: reset,
        dialogs: dialogs,
        restartsItself: true,
      );

      await choose(tester, 'Old backup file (.json)');

      expect(dialogs.extensions, ['json']);
      expect(legacy.calls, ['stageBackup']);
      expect(legacy.backupGiven, json);
      expect(legacy.replacingGiven, same(database));
      expect(
        find.text(
          'An old backup file has no queue, so the queue will be empty '
          'afterwards.',
        ),
        findsOneWidget,
      );
      expect(find.text('Queue: 5'), findsNothing);
      expect(find.text('Playlists: 3'), findsOneWidget);
      expect(
        find.text('The app restarts by itself afterwards.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Replace and restart'));
      await tester.pumpAndSettle();
      expect(reset.calls, ['replaceWithImport']);
    });

    testWidgets('cancelling the file dialog does nothing', (tester) async {
      final legacy = _FakeLegacyImport();
      final reset = FakeDataReset();
      await openBackup(tester, legacy: legacy, reset: reset);

      await choose(tester, 'Old backup file (.json)');

      expect(legacy.calls, isEmpty);
      expect(reset.calls, isEmpty);
      expect(find.text('Import from the old version?'), findsNothing);
    });

    for (final (reason, message) in [
      (LegacyBackupRejection.notBackup, 'not a backup file of the old FMP'),
      (LegacyBackupRejection.newerVersion, 'comes from a newer version'),
      (LegacyBackupRejection.corrupt, 'The backup file is damaged.'),
      (LegacyBackupRejection.empty, 'has nothing to import'),
    ]) {
      testWidgets('a rejected file (${reason.name}) says why', (tester) async {
        final legacy = _FakeLegacyImport(error: LegacyBackupRejected(reason));
        final reset = FakeDataReset();
        await openBackup(
          tester,
          legacy: legacy,
          reset: reset,
          dialogs: FakeFileDialogs(PickedFile(name: 'b.json', bytes: json)),
        );

        await choose(tester, 'Old backup file (.json)');

        expect(find.textContaining(message), findsOneWidget);
        expect(find.text('Import from the old version?'), findsNothing);
        expect(reset.calls, isEmpty);
      });
    }
  });
}
