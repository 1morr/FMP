import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/backup.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/backup_format.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/ui/plugins/plugin_dialogs.dart';
import 'package:fmp/ui/settings/backup_controls.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../support/fake_app_backup.dart';
import '../support/fake_data_reset.dart';
import '../support/plugin_page_harness.dart';
import '../support/shell_harness.dart';

// 設定頁的「備份與還原」組與還原確認框（M4 PR 22，ADR 0034 §決定 4、5）。

void main() {
  Future<ShellHarness> openBackup(
    WidgetTester tester, {
    required FakeAppBackup backup,
    FakeDataReset? reset,
    bool files = true,
    bool restartsItself = false,
    double width = 1000,
  }) async {
    final h = ShellHarness(
      fileDialogs: files ? FakeFileDialogs() : null,
      dataReset: reset ?? FakeDataReset(),
      restartsItself: restartsItself,
      redactor: Redactor(),
      extraOverrides: [appBackupProvider.overrideWithValue(backup)],
    );
    await h.pumpShell(tester, size: Size(width, 900), collapsePanel: true);
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Backup and restore'));
    await h.loadSettings(tester);
    await tester.pumpAndSettle();
    return h;
  }

  Finder exportButton() => find.widgetWithText(FilledButton, 'Export backup');
  Finder restoreButton() =>
      find.widgetWithText(OutlinedButton, 'Restore from backup file');

  group('the section', () {
    testWidgets('explains what a backup holds and what it leaves out', (
      tester,
    ) async {
      await openBackup(tester, backup: FakeAppBackup());

      expect(find.byType(BackupControls), findsOneWidget);
      expect(
        find.textContaining('playlists, settings, installed plugins'),
        findsOneWidget,
      );
      expect(
        find.textContaining('does not include sign-ins, cookies, the cache'),
        findsOneWidget,
      );
      expect(
        find.textContaining('keeps the sign-ins on this device'),
        findsOneWidget,
      );
      expect(exportButton(), findsOneWidget);
      expect(restoreButton(), findsOneWidget);
    });

    testWidgets('a platform without file dialogs shows only the text', (
      tester,
    ) async {
      await openBackup(tester, backup: FakeAppBackup(), files: false);

      expect(find.byType(BackupControls), findsOneWidget);
      expect(exportButton(), findsNothing);
      expect(restoreButton(), findsNothing);
    });

    testWidgets('works on a narrow window', (tester) async {
      await openBackup(tester, backup: FakeAppBackup(), width: 400);

      expect(exportButton(), findsOneWidget);
      expect(restoreButton(), findsOneWidget);
    });
  });

  group('export', () {
    testWidgets('shows where the file was saved', (tester) async {
      final backup = FakeAppBackup(
        exportResult: Uri.parse('content://fake.provider/fmp-backup.db'),
      );
      await openBackup(tester, backup: backup);

      await tester.tap(exportButton());
      await tester.pumpAndSettle();

      expect(backup.calls, ['export']);
      expect(
        find.text('Backup saved to content://fake.provider/fmp-backup.db'),
        findsOneWidget,
      );
    });

    testWidgets('a file location is shown as a path', (tester) async {
      final backup = FakeAppBackup(
        exportResult: Uri.file(
          p.join(Directory.systemTemp.path, 'fmp-backup.db'),
        ),
      );
      await openBackup(tester, backup: backup);

      await tester.tap(exportButton());
      await tester.pumpAndSettle();

      expect(find.textContaining('fmp-backup.db'), findsOneWidget);
      expect(find.textContaining('file:'), findsNothing);
    });

    testWidgets('cancelling the save dialog says nothing', (tester) async {
      final backup = FakeAppBackup();
      await openBackup(tester, backup: backup);

      await tester.tap(exportButton());
      await tester.pumpAndSettle();

      expect(backup.calls, ['export']);
      expect(find.textContaining('Backup saved'), findsNothing);
      expect(find.textContaining('not exported'), findsNothing);
    });

    testWidgets('a failure shows the reason', (tester) async {
      final backup = FakeAppBackup(exportError: StateError('disk full'));
      await openBackup(tester, backup: backup);

      await tester.tap(exportButton());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('The backup was not exported'),
        findsOneWidget,
      );
    });

    testWidgets('both buttons are disabled while exporting', (tester) async {
      final gate = Completer<Uri?>();
      final backup = _SlowBackup(gate.future);
      await openBackup(tester, backup: backup);

      await tester.tap(exportButton());
      await tester.pump();

      expect(find.text('Exporting…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Restore from backup file'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Exporting…'),
            )
            .onPressed,
        isNull,
      );

      gate.complete(null);
      await tester.pumpAndSettle();
      expect(exportButton(), findsOneWidget);
    });
  });

  group('restore', () {
    Future<void> tapRestore(WidgetTester tester) async {
      await tester.tap(restoreButton());
      await tester.pumpAndSettle();
    }

    for (final (reason, message) in [
      (BackupRejection.newerVersion, 'comes from a newer version of FMP'),
      (BackupRejection.notFmpBackup, 'This is not an FMP backup.'),
      (BackupRejection.corrupt, 'The backup file is damaged.'),
    ]) {
      testWidgets('a rejected file (${reason.name}) says why', (tester) async {
        final reset = FakeDataReset();
        final backup = FakeAppBackup(stageError: BackupRejected(reason));
        await openBackup(tester, backup: backup, reset: reset);

        await tapRestore(tester);

        expect(find.textContaining(message), findsOneWidget);
        expect(find.text('Restore from this backup?'), findsNothing);
        expect(reset.calls, isEmpty);
      });
    }

    testWidgets('cancelling the file dialog does nothing', (tester) async {
      final reset = FakeDataReset();
      final backup = FakeAppBackup();
      await openBackup(tester, backup: backup, reset: reset);

      await tapRestore(tester);

      expect(backup.calls, ['pickAndStage']);
      expect(find.text('Restore from this backup?'), findsNothing);
      expect(reset.calls, isEmpty);
    });

    testWidgets('another failure shows the reason', (tester) async {
      final backup = FakeAppBackup(stageError: StateError('unreadable'));
      await openBackup(tester, backup: backup);

      await tapRestore(tester);

      expect(find.textContaining('The restore did not finish'), findsOneWidget);
    });

    testWidgets('the confirmation lists plugins, sites, warning and the '
        'replacement note, and confirming restores', (tester) async {
      final reset = FakeDataReset();
      final backup = FakeAppBackup(staged: FakeDataReset.staged);
      await openBackup(tester, backup: backup, reset: reset);

      await tapRestore(tester);

      expect(find.text('Restore from this backup?'), findsOneWidget);
      expect(find.text('Test Source 1.2.3'), findsOneWidget);
      expect(
        find.text('Sites it connects to: example.test, cdn.example.test'),
        findsOneWidget,
      );
      expect(find.text('Other Source 0.1.0'), findsOneWidget);
      expect(
        find.text('Sites it connects to: other.example.test'),
        findsOneWidget,
      );
      expect(
        find.text(
          'This script will access these sites as you, with your sign-in.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('current data is replaced; a backup of it is made'),
        findsOneWidget,
      );
      expect(
        find.text('The app closes afterwards; open it again yourself.'),
        findsOneWidget,
      );
      expect(reset.calls, isEmpty);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Restore and restart'),
      );
      await tester.pumpAndSettle();

      expect(reset.calls, ['restore']);
    });

    testWidgets('lists the plugins that cannot be used and will not be '
        'restored', (tester) async {
      final backup = FakeAppBackup(staged: FakeDataReset.staged);
      await openBackup(tester, backup: backup);

      await tapRestore(tester);

      expect(
        find.text(
          'These plugins cannot be used in this version and will not be '
          'restored',
        ),
        findsOneWidget,
      );
      expect(find.text('broken-plugin'), findsOneWidget);
    });

    testWidgets('a backup whose only plugins are unusable does not claim '
        'to have none', (tester) async {
      final backup = FakeAppBackup(
        staged: const StagedBackup(
          path: '/s.db',
          plugins: [],
          unusablePluginIds: ['old-plugin'],
        ),
      );
      await openBackup(tester, backup: backup);

      await tapRestore(tester);

      expect(find.text('old-plugin'), findsOneWidget);
      expect(find.text('This backup has no plugins.'), findsNothing);
    });

    testWidgets('lists the custom plugin indexes the backup adds', (
      tester,
    ) async {
      final backup = FakeAppBackup(staged: FakeDataReset.staged);
      await openBackup(tester, backup: backup);

      await tapRestore(tester);

      expect(
        find.text('Custom plugin indexes this backup adds'),
        findsOneWidget,
      );
      expect(find.text('https://index.example.test/'), findsOneWidget);
    });

    testWidgets('a plugin this device also has: older version and the sites '
        'it lacks are called out', (tester) async {
      final backup = FakeAppBackup(staged: FakeDataReset.staged);
      final h = await openBackup(tester, backup: backup);
      // 這台有較新的 fmp-test，而且只允許 example.test。
      final script = pluginScript(
        'fmp-test',
        version: '2.0.0',
        hosts: ['example.test'],
      );
      await tester.runAsync(() async {
        await h
            .container(tester)
            .read(pluginRepositoryProvider)
            .install(
              InstalledPlugin(
                id: 'fmp-test',
                version: '2.0.0',
                manifestJson: PluginFile.parse(script).manifestJson,
                script: script,
                installedAt: DateTime.utc(2026),
              ),
            );
      });

      await tapRestore(tester);

      expect(find.text("Older than this device's (2.0.0)"), findsOneWidget);
      expect(find.text('New on this device: cdn.example.test'), findsOneWidget);
      // 這台沒裝的 other：照常列網域，不標「新」也不標「舊」。
      expect(find.text('Other Source 0.1.0'), findsOneWidget);
      expect(find.textContaining('New on this device'), findsOneWidget);
    });

    testWidgets('a plugin that is not on this device shows no comparison', (
      tester,
    ) async {
      final backup = FakeAppBackup(staged: FakeDataReset.staged);
      await openBackup(tester, backup: backup);

      await tapRestore(tester);

      expect(find.textContaining('Older than'), findsNothing);
      expect(find.textContaining('New on this device'), findsNothing);
    });

    testWidgets('Windows says the app restarts by itself', (tester) async {
      final backup = FakeAppBackup(staged: FakeDataReset.staged);
      await openBackup(tester, backup: backup, restartsItself: true);

      await tapRestore(tester);

      expect(
        find.text('The app restarts by itself afterwards.'),
        findsOneWidget,
      );
    });

    testWidgets('cancelling the confirmation discards the staged file', (
      tester,
    ) async {
      final reset = FakeDataReset();
      final backup = FakeAppBackup(staged: FakeDataReset.staged);
      await openBackup(tester, backup: backup, reset: reset);

      await tapRestore(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(reset.calls, ['discard']);
      expect(find.text('Restore from this backup?'), findsNothing);
    });

    testWidgets('a failed restore (for example the automatic backup) shows '
        'the reason and discards the staged file', (tester) async {
      final reset = FakeDataReset(restoreError: StateError('disk full'));
      final backup = FakeAppBackup(staged: FakeDataReset.staged);
      await openBackup(tester, backup: backup, reset: reset);

      await tapRestore(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Restore and restart'),
      );
      await tester.pumpAndSettle();

      expect(reset.calls, ['restore', 'discard']);
      expect(find.textContaining('The restore did not finish'), findsOneWidget);
    });

    testWidgets('a backup without plugins says so and shows no warning', (
      tester,
    ) async {
      final backup = FakeAppBackup(
        staged: const StagedBackup(path: '/staged.db', plugins: []),
      );
      await openBackup(tester, backup: backup);

      await tapRestore(tester);

      expect(find.text('This backup has no plugins.'), findsOneWidget);
      expect(find.byType(WarningNote), findsNothing);
    });
  });
}

/// 慢速的匯出，讓測試看得到進行中的狀態。
final class _SlowBackup extends FakeAppBackup {
  _SlowBackup(this._result);

  final Future<Uri?> _result;

  @override
  Future<Uri?> export() => _result;
}
