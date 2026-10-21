import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/backup_format.dart';
import 'package:fmp/data/database/database_backups.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/ui/debug/debug_database.dart';
import 'package:fmp/ui/debug/debug_reset.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_data_reset.dart';
import '../support/shell_harness.dart';

// Debug 頁的重設資料、從備份還原與立即備份（M3 PR 14b，ADR 0025 §決定 8、9）。

void main() {
  Future<ShellHarness> openSection(
    WidgetTester tester,
    String section,
    FakeDataReset reset, {
    double width = 1000,
    bool restartsItself = false,
  }) async {
    final h = ShellHarness(
      dataReset: reset,
      restartsItself: restartsItself,
      redactor: Redactor(),
    );
    await h.pumpShell(tester, size: Size(width, 900), collapsePanel: true);
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Debug'));
    await h.loadSettings(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, section));
    await h.loadSettings(tester);
    await tester.pumpAndSettle();
    return h;
  }

  Finder confirmButton(String label) =>
      find.widgetWithText(FilledButton, label);

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<FilledButton>(button).onPressed != null;

  group('reset section', () {
    testWidgets('explains what is cleared and what is kept', (tester) async {
      await openSection(tester, 'Reset data', FakeDataReset());

      expect(find.byType(DebugReset), findsOneWidget);
      expect(find.textContaining('Log files, backups'), findsOneWidget);
      expect(find.text('Reset data…'), findsOneWidget);
    });

    testWidgets('backs up first, then needs a second, explicit confirmation', (
      tester,
    ) async {
      final reset = FakeDataReset();
      await openSection(tester, 'Reset data', reset);

      await tester.tap(find.text('Reset data…'));
      await tester.pumpAndSettle();

      // 備份已做；對話框列出位置（家目錄換成 ~），但還沒清。
      expect(reset.calls, ['backUp']);
      expect(find.text('Reset all data?'), findsOneWidget);
      expect(
        find.textContaining('~/data/backups/fmp-20261014T010203000Z.db'),
        findsOneWidget,
      );
      expect(find.textContaining('tester'), findsNothing);
      // 沒勾「我了解」之前按不下去。
      expect(enabled(tester, confirmButton('Clear and restart')), isFalse);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(enabled(tester, confirmButton('Clear and restart')), isTrue);
      expect(reset.calls, ['backUp']);

      await tester.tap(confirmButton('Clear and restart'));
      await tester.pumpAndSettle();

      expect(reset.calls, ['backUp', 'reset ${FakeDataReset.made.path}']);
    });

    testWidgets('cancelling clears nothing', (tester) async {
      final reset = FakeDataReset();
      await openSection(tester, 'Reset data', reset);

      await tester.tap(find.text('Reset data…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(reset.calls, ['backUp']);
      expect(find.text('Reset all data?'), findsNothing);
    });

    testWidgets('a failed backup shows the error and clears nothing', (
      tester,
    ) async {
      final reset = FakeDataReset(backUpError: StateError('disk full'));
      await openSection(tester, 'Reset data', reset);

      await tester.tap(find.text('Reset data…'));
      await tester.pumpAndSettle();

      expect(reset.calls, ['backUp']);
      expect(find.text('Reset all data?'), findsNothing);
      expect(
        find.textContaining('Could not back up the database, nothing was'),
        findsOneWidget,
      );
    });

    testWidgets('Android tells the user to reopen the app by hand', (
      tester,
    ) async {
      await openSection(tester, 'Reset data', FakeDataReset());

      await tester.tap(find.text('Reset data…'));
      await tester.pumpAndSettle();

      expect(
        find.text('The app closes afterwards; open it again yourself.'),
        findsOneWidget,
      );
    });

    testWidgets('Windows says the app restarts by itself', (tester) async {
      await openSection(
        tester,
        'Reset data',
        FakeDataReset(),
        restartsItself: true,
      );

      await tester.tap(find.text('Reset data…'));
      await tester.pumpAndSettle();

      expect(
        find.text('The app restarts by itself afterwards.'),
        findsOneWidget,
      );
    });
  });

  group('database section', () {
    testWidgets('backs up on demand and shows where the file is', (
      tester,
    ) async {
      final reset = FakeDataReset();
      await openSection(tester, 'Database', reset);

      await tester.tap(find.text('Back up now'));
      await tester.pumpAndSettle();

      expect(reset.calls, ['backUp']);
      expect(
        find.textContaining('Backed up to ~/data/backups/fmp-2026'),
        findsOneWidget,
      );
    });

    testWidgets('restores the chosen backup after a confirmation', (
      tester,
    ) async {
      final older = DatabaseBackup(
        path: '/home/tester/data/backups/fmp-20261013T000000000Z.db',
        createdAt: DateTime.utc(2026, 10, 13),
        sizeBytes: 1024,
      );
      final reset = FakeDataReset(listed: [FakeDataReset.made, older]);
      await openSection(tester, 'Database', reset);

      await tester.tap(find.text('Restore from backup'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a backup to restore'), findsOneWidget);
      expect(find.text('2 KB'), findsOneWidget);
      expect(find.text('1 KB'), findsOneWidget);

      await tester.tap(find.text('1 KB'));
      await tester.pumpAndSettle();
      // 選了還沒還原，要再確認一次；確認框列出備份裡的插件。
      expect(find.text('Restore from this backup?'), findsOneWidget);
      expect(find.text('Test Source 1.2.3'), findsOneWidget);
      expect(reset.calls, ['backups', 'stage ${older.path}']);

      await tester.tap(confirmButton('Restore and restart'));
      await tester.pumpAndSettle();

      expect(reset.calls, ['backups', 'stage ${older.path}', 'restore']);
    });

    testWidgets('declining the confirmation restores nothing', (tester) async {
      final reset = FakeDataReset(listed: [FakeDataReset.made]);
      await openSection(tester, 'Database', reset);

      await tester.tap(find.text('Restore from backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 KB'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // 取消：不還原，暫存檔刪掉。
      expect(reset.calls, [
        'backups',
        'stage ${FakeDataReset.made.path}',
        'discard',
      ]);
    });

    testWidgets('a rejected backup says why and restores nothing', (
      tester,
    ) async {
      final reset = FakeDataReset(
        listed: [FakeDataReset.made],
        stageError: const BackupRejected(BackupRejection.corrupt),
      );
      await openSection(tester, 'Database', reset);

      await tester.tap(find.text('Restore from backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 KB'));
      await tester.pumpAndSettle();

      expect(find.text('The backup file is damaged.'), findsOneWidget);
      expect(find.text('Restore from this backup?'), findsNothing);
      expect(reset.calls, ['backups', 'stage ${FakeDataReset.made.path}']);
    });

    testWidgets('says so when there are no backups', (tester) async {
      final reset = FakeDataReset();
      await openSection(tester, 'Database', reset);

      await tester.tap(find.text('Restore from backup'));
      await tester.pumpAndSettle();

      expect(find.textContaining('There are no backups'), findsOneWidget);
    });

    testWidgets('a clean check offers no recovery buttons', (tester) async {
      final reset = FakeDataReset();
      final h = await openSection(tester, 'Database', reset);

      await tester.tap(find.text('Check'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();

      expect(find.text('No problems found'), findsOneWidget);
      expect(find.text('Reset data…'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(Card),
          matching: find.text('Restore from backup'),
        ),
        findsNothing,
      );
    });

    testWidgets('a check with problems offers restore and reset', (
      tester,
    ) async {
      final reset = FakeDataReset(listed: [FakeDataReset.made]);
      final h = await openSection(tester, 'Database', reset);
      await tester.runAsync(() async {
        final database = h.container(tester).read(appDatabaseProvider);
        await database.customStatement('PRAGMA foreign_keys = OFF');
        await database.customStatement(
          'INSERT INTO plugin_storage (plugin_id, key, value) '
          "VALUES ('missing-plugin', 'k', 'v')",
        );
        await database.customStatement('PRAGMA foreign_keys = ON');
      });

      await tester.tap(find.text('Check'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();

      expect(find.text('Problems found'), findsOneWidget);
      final card = find.byType(Card);
      final restore = find.descendant(
        of: card,
        matching: find.text('Restore from backup'),
      );
      final resetButton = find.descendant(
        of: card,
        matching: find.text('Reset data…'),
      );
      expect(restore, findsOneWidget);
      expect(resetButton, findsOneWidget);

      await tester.ensureVisible(resetButton);
      await tester.tap(resetButton);
      await tester.pumpAndSettle();
      expect(reset.calls, ['backUp']);
      expect(find.text('Reset all data?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(reset.calls, ['backUp', 'backups']);
      expect(find.text('Choose a backup to restore'), findsOneWidget);
      expect(find.byType(DebugDatabase), findsOneWidget);
    });
  });
}
