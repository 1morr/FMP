import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/diagnostics/diagnostics_service.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../support/fake_file_sharer.dart';
import '../support/plugin_page_harness.dart' show FakeFileDialogs;
import '../support/shell_harness.dart';

// Debug 頁的診斷包與 log 檔匯出（M3 PR 15，ADR 0025 §決定 3、10）。

void main() {
  late Directory temp;
  late FakeFileDialogs dialogs;
  late FakeFileSharer sharer;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('fmp_debug_export_test');
    addTearDown(() async {
      // Windows 上 log 檔的最後一次寫入可能還沒放開檔案：等一下再刪，幾次都不行才算失敗。
      for (var attempt = 0; ; attempt++) {
        try {
          temp.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          if (attempt == 10) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
    dialogs = FakeFileDialogs();
    sharer = FakeFileSharer();
  });

  /// 有 log 檔的門面，log 檔在 [temp] 底下。
  Log fileLog() => Log(
    redactor: Redactor(),
    minimumLevel: LogLevel.debug,
    file: LogFile(Directory(p.join(temp.path, 'logs'))),
  );

  /// 開 Debug 頁的 [section]。診斷包的資料用固定的小物件，暫存目錄放在 [temp]。
  Future<ShellHarness> open(
    WidgetTester tester, {
    String section = 'Overview',
    bool share = true,
    bool save = true,
    Log? log,
  }) async {
    final redactor = Redactor();
    final logFacade = log ?? fileLog();
    final h = ShellHarness(
      log: logFacade,
      redactor: redactor,
      fileDialogs: save ? dialogs : null,
      fileSharer: share ? sharer : null,
      extraOverrides: [
        diagnosticsDataProvider.overrideWithValue(
          () async => {
            'app': {'version': '1.2.3'},
          },
        ),
        diagnosticsExporterProvider.overrideWith(
          (ref) => DiagnosticsExporter(
            fileDialogs: save ? dialogs : null,
            fileSharer: share ? sharer : null,
            tempDirectory: Directory(
              p.join(temp.path, diagnosticsTempDirectoryName),
            ),
            log: logFacade,
          ),
        ),
      ],
    );
    h.log.minimumLevel = LogLevel.debug;
    await h.pumpShell(tester, size: const Size(1000, 900), collapsePanel: true);
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Debug'));
    await h.loadSettings(tester);
    await tester.pumpAndSettle();
    if (section != 'Overview') {
      await tester.tap(find.widgetWithText(ListTile, section));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();
    }
    return h;
  }

  /// 讓真的檔案 I/O 與 isolate 的壓縮跑完，再讓假時間的後續也跑完。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
  }

  /// 一直等到 [done] 成立（上限 10 秒）：zip 在另一個 isolate 壓，要等真實時間。
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await settle(tester);
  }

  Map<String, String> unzip(List<int> bytes) => {
    for (final file in ZipDecoder().decodeBytes(bytes))
      file.name: utf8.decode(file.content),
  };

  final reminder = find.text('Check before you submit');

  Future<void> tapAndSettle(
    WidgetTester tester,
    Finder finder, {
    bool Function()? until,
  }) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    if (until == null) {
      await settle(tester);
    } else {
      await settleUntil(tester, until);
    }
  }

  group('which buttons show', () {
    testWidgets('save and share follow the platform capabilities', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Copy summary'), findsOneWidget);
      expect(find.text('Save as file'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('a platform that cannot share files shows no Share', (
      tester,
    ) async {
      await open(tester, share: false);

      expect(find.text('Save as file'), findsOneWidget);
      expect(find.text('Share'), findsNothing);
    });

    testWidgets('the log export menu lists only what the platform can do', (
      tester,
    ) async {
      await open(tester, section: 'Log & errors', share: false);

      await tester.tap(find.byTooltip('Export log files'));
      await tester.pumpAndSettle();

      expect(find.text('Save as file'), findsOneWidget);
      expect(find.text('Share'), findsNothing);
    });
  });

  group('the reminder', () {
    testWidgets('asks on the first export; cancelling exports nothing', (
      tester,
    ) async {
      await open(tester);

      await tapAndSettle(tester, find.text('Save as file'));
      expect(reminder, findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(dialogs.saves, isEmpty);
      // 取消不算提醒過：下一次還會問。
      await tapAndSettle(tester, find.text('Save as file'));
      expect(reminder, findsOneWidget);
    });

    testWidgets('"Don\'t remind me again" is the setting the GitHub report '
        'shares', (tester) async {
      final h = await open(tester);

      await tapAndSettle(tester, find.text('Save as file'));
      await tester.tap(find.text("Don't remind me again"));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await settleUntil(tester, () => dialogs.saves.isNotEmpty);

      expect(dialogs.saves, hasLength(1));
      final stored = await tester.runAsync(
        () => h
            .container(tester)
            .read(developerSettingsRepositoryProvider)
            .read(),
      );
      expect(stored!.reportReminderDismissed, isTrue);

      await tapAndSettle(
        tester,
        find.text('Share'),
        until: () => sharer.shared.isNotEmpty,
      );
      expect(reminder, findsNothing);
      expect(sharer.shared, hasLength(1));
    });

    testWidgets('continuing without the box keeps asking', (tester) async {
      await open(tester);

      for (var round = 1; round <= 2; round++) {
        await tapAndSettle(tester, find.text('Save as file'));
        expect(reminder, findsOneWidget);
        await tester.tap(find.text('Continue'));
        await settleUntil(tester, () => dialogs.saves.length >= round);
        expect(dialogs.saves, hasLength(round));
      }
    });

    testWidgets('a setting made elsewhere (the GitHub report) skips it', (
      tester,
    ) async {
      final h = await open(tester);
      await tester.runAsync(
        () => h
            .container(tester)
            .read(developerSettingsRepositoryProvider)
            .write(reportReminderDismissed: true),
      );
      await h.loadSettings(tester);

      await tapAndSettle(
        tester,
        find.text('Save as file'),
        until: () => dialogs.saves.isNotEmpty,
      );

      expect(reminder, findsNothing);
      expect(dialogs.saves, hasLength(1));
    });

    testWidgets('copying the summary does not ask', (tester) async {
      await open(tester);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tapAndSettle(tester, find.text('Copy summary'));

      expect(reminder, findsNothing);
      expect(copied.single, contains('version: 1.2.3'));
      expect(find.text('Summary copied'), findsOneWidget);
    });
  });

  group('saving', () {
    testWidgets('writes a diagnostics zip named for the time, no colon', (
      tester,
    ) async {
      final h = await open(tester);
      await tester.runAsync(
        () => h
            .container(tester)
            .read(developerSettingsRepositoryProvider)
            .write(reportReminderDismissed: true),
      );
      await h.loadSettings(tester);
      h.log.info('a log line', tag: 'app');

      await tapAndSettle(
        tester,
        find.text('Save as file'),
        until: () => dialogs.saves.isNotEmpty,
      );

      final saved = dialogs.saves.single;
      expect(saved.name, matches(r'^fmp-diagnostics-\d{8}-\d{6}\.zip$'));
      expect(saved.mimeType, 'application/zip');
      final files = unzip(saved.bytes);
      expect(files.keys, containsAll(['diagnostics.txt', 'diagnostics.json']));
      expect(files['fmp.jsonl'], contains('a log line'));
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('cancelling the save dialog shows no success', (tester) async {
      final h = await open(tester);
      dialogs.saveResult = null;
      await tester.runAsync(
        () => h
            .container(tester)
            .read(developerSettingsRepositoryProvider)
            .write(reportReminderDismissed: true),
      );
      await h.loadSettings(tester);

      await tapAndSettle(
        tester,
        find.text('Save as file'),
        until: () => dialogs.saves.isNotEmpty,
      );

      expect(dialogs.saves, hasLength(1));
      expect(find.text('Saved'), findsNothing);
      expect(
        Directory(p.join(temp.path, diagnosticsTempDirectoryName)).existsSync(),
        isFalse,
      );
    });
  });

  group('sharing', () {
    testWidgets('shares the zip from the temp directory and removes it', (
      tester,
    ) async {
      final h = await open(tester);
      await tester.runAsync(
        () => h
            .container(tester)
            .read(developerSettingsRepositoryProvider)
            .write(reportReminderDismissed: true),
      );
      await h.loadSettings(tester);

      await tapAndSettle(
        tester,
        find.text('Share'),
        until: () => sharer.shared.isNotEmpty,
      );

      final shared = sharer.shared.single;
      expect(
        p.dirname(shared.path),
        p.join(temp.path, diagnosticsTempDirectoryName),
      );
      expect(shared.mimeType, 'application/zip');
      expect(unzip(shared.bytes).keys, contains('diagnostics.txt'));
      expect(File(shared.path).existsSync(), isFalse);
    });

    testWidgets('a share window that cannot open is reported and cleaned', (
      tester,
    ) async {
      final h = await open(tester);
      sharer.error = StateError('no share window');
      await tester.runAsync(
        () => h
            .container(tester)
            .read(developerSettingsRepositoryProvider)
            .write(reportReminderDismissed: true),
      );
      await h.loadSettings(tester);

      await tapAndSettle(
        tester,
        find.text('Share'),
        until: () => sharer.shared.isNotEmpty,
      );

      expect(find.textContaining("Couldn't create the file"), findsOneWidget);
      expect(
        Directory(p.join(temp.path, diagnosticsTempDirectoryName)).listSync(),
        isEmpty,
      );
    });
  });

  group('exporting the log files', () {
    testWidgets('the zip holds the log files and nothing else', (tester) async {
      final h = await open(tester, section: 'Log & errors');
      await tester.runAsync(
        () => h
            .container(tester)
            .read(developerSettingsRepositoryProvider)
            .write(reportReminderDismissed: true),
      );
      await h.loadSettings(tester);
      h.log.info('exported line', tag: 'app');

      await tester.tap(find.byTooltip('Export log files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as file'));
      await settleUntil(tester, () => dialogs.saves.isNotEmpty);

      final saved = dialogs.saves.single;
      expect(saved.name, matches(r'^fmp-logs-\d{8}-\d{6}\.zip$'));
      final files = unzip(saved.bytes);
      expect(files.keys, ['fmp.jsonl']);
      expect(files['fmp.jsonl'], contains('exported line'));
    });
  });
}
