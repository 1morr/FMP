import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/ui/debug/debug_database.dart';
import 'package:fmp/ui/debug/debug_playback.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// Debug 頁的播放狀態與資料庫區塊（M3 PR 14a，ADR 0025 §決定 5、8）。

void main() {
  Future<ShellHarness> openSection(
    WidgetTester tester,
    String section, {
    double width = 1000,
    Redactor? redactor,
    Future<void> Function(ShellHarness h)? beforeOpen,
  }) async {
    final h = ShellHarness(redactor: redactor ?? Redactor());
    await h.pumpShell(tester, size: Size(width, 900), collapsePanel: true);
    await beforeOpen?.call(h);
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

  List<String> captureClipboard(WidgetTester tester) {
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
    return copied;
  }

  /// 區塊裡 [label] 那一列的值。
  String fact(WidgetTester tester, String label) {
    final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, label));
    return (tile.subtitle! as SelectableText).data!;
  }

  group('playback section', () {
    testWidgets('shows an empty state when nothing is playing', (tester) async {
      await openSection(tester, 'Playback');

      expect(find.byType(DebugPlayback), findsOneWidget);
      expect(find.text('Nothing is playing'), findsOneWidget);
      expect(find.text('Copy snapshot'), findsNothing);
    });

    testWidgets('shows the state, the stream and the queue', (tester) async {
      final h = await openSection(tester, 'Playback');
      await h.play(tester, [summary('a'), summary('b'), summary('c')]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('Nothing is playing'), findsNothing);
      expect(fact(tester, 'State'), 'Playing');
      expect(fact(tester, 'Track'), 'fmp-test:a');
      expect(fact(tester, 'Plugin'), 'fmp-test');
      expect(fact(tester, 'Stream'), contains('mp4 · aac'));
      expect(fact(tester, 'Stream'), contains('network'));
      expect(fact(tester, 'Queue'), '3 tracks, current is #1');
      expect(fact(tester, 'Before'), 'none');
      expect(fact(tester, 'After'), 'fmp-test:b\nfmp-test:c');
      // 這個 harness 沒有輸出裝置可選：不寫成假的裝置名。
      expect(fact(tester, 'Output device'), 'System default or not applicable');
    });

    testWidgets('the position follows the progress stream', (tester) async {
      final h = await openSection(tester, 'Playback');
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      final first = fact(tester, 'Position');

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(fact(tester, 'Position'), isNot(first));
    });

    testWidgets('copies a redacted JSON snapshot', (tester) async {
      final redactor = Redactor()..registerSecret('FAKE_SECRET_VALUE');
      final copied = captureClipboard(tester);
      final h = await openSection(tester, 'Playback', redactor: redactor);
      await h.play(tester, [summary('FAKE_SECRET_VALUE')]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // 畫面上的曲目鍵也經遮蔽（播放列的曲名不歸這個區塊管）。
      expect(fact(tester, 'Track'), 'fmp-test:$redactedValue');
      expect(
        find.descendant(
          of: find.byType(DebugPlayback),
          matching: find.textContaining('FAKE_SECRET_VALUE'),
        ),
        findsNothing,
      );

      await tester.tap(find.text('Copy snapshot'));
      await tester.pump();

      expect(copied, hasLength(1));
      expect(copied.single, isNot(contains('FAKE_SECRET_VALUE')));
      final json = jsonDecode(copied.single) as Map<String, Object?>;
      expect(json['state'], 'playing');
      expect(json['backend'], 'unknown');
      expect((json['queue']! as Map)['total'], 1);
      expect(find.text('Snapshot copied'), findsOneWidget);
    });
  });

  group('database section', () {
    Future<void> seedStorage(ShellHarness h, WidgetTester tester) =>
        tester.runAsync(() async {
          final database = h.container(tester).read(appDatabaseProvider);
          await PluginRepository(database).install(
            InstalledPlugin(
              id: 'fmp-test',
              version: '1.0.0',
              manifestJson: '{}',
              script: '',
              installedAt: DateTime.utc(2026),
            ),
          );
          await PluginStorageRepository(database)
              .write('fmp-test', 'session', 'FAKE_COOKIE_VALUE');
        });

    testWidgets('lists the tables with their row counts', (tester) async {
      await openSection(tester, 'Database');

      expect(find.byType(DebugDatabase), findsOneWidget);
      expect(find.text('plugin_storage'), findsOneWidget);
      expect(find.text('tracks'), findsOneWidget);
      expect(find.text('0 rows'), findsWidgets);
    });

    testWidgets('shows the rows of a table, masking plugin_storage', (
      tester,
    ) async {
      final h = await openSection(tester, 'Database', width: 1400);
      await tester.tap(find.text('plugin_storage'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();
      expect(find.text('This table is empty'), findsOneWidget);

      // 看表的期間寫進來的列：回到清單時筆數重讀。
      await seedStorage(h, tester);
      await tester.tap(find.byTooltip('Back to the table list'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'plugin_storage'),
          matching: find.text('1 rows'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('plugin_storage'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();

      expect(find.text('session'), findsOneWidget);
      expect(find.text('***'), findsOneWidget);
      expect(find.textContaining('FAKE_COOKIE_VALUE'), findsNothing);
      expect(find.text('Page 1 / 1, 1 rows'), findsOneWidget);
    });

    testWidgets('pages through a long table 50 rows at a time', (tester) async {
      final h = await openSection(tester, 'Database', width: 1400);
      await tester.runAsync(
        () => TracksRepository(h.container(tester).read(appDatabaseProvider))
            .upsert([
              for (var i = 0; i < 60; i++)
                TrackInfo(
                  sourceTypeId: 'fmp-test',
                  sourceId: 't$i',
                  title: 'Song $i',
                ),
            ]),
      );
      await tester.tap(find.widgetWithText(ListTile, 'Overview'));
      await h.loadSettings(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Database'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('tracks'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();
      expect(find.text('Page 1 / 2, 60 rows'), findsOneWidget);
      expect(
        tester.widget<DataTable>(find.byType(DataTable)).rows,
        hasLength(50),
      );

      await tester.tap(find.byTooltip('Next page'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();
      expect(find.text('Page 2 / 2, 60 rows'), findsOneWidget);
      expect(
        tester.widget<DataTable>(find.byType(DataTable)).rows,
        hasLength(10),
      );

      await tester.tap(find.byTooltip('Back to the table list'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();
      expect(find.text('plugin_storage'), findsOneWidget);
    });

    testWidgets('a clean database reports no problems', (tester) async {
      final h = await openSection(tester, 'Database');

      await tester.tap(find.text('Check'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();

      expect(find.text('No problems found'), findsOneWidget);
      expect(find.text('Orphan tracks'), findsOneWidget);
    });

    testWidgets('a foreign key violation is listed', (tester) async {
      final h = await openSection(tester, 'Database');
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
      expect(
        find.textContaining('plugin_storage rowid 1 has no matching row in'),
        findsOneWidget,
      );
    });
  });
}
