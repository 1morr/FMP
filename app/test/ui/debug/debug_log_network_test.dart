import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/ui/debug/debug_log.dart';
import 'package:fmp/ui/debug/debug_log_state.dart';
import 'package:fmp/ui/debug/debug_network.dart';
import 'package:fmp/ui/errors/error_detail_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../support/shell_harness.dart';

// Debug 頁的 Log 與網路區塊（M3 PR 12，ADR 0025 §決定 3、4）。

void main() {
  /// 開 Debug 頁並點進 [section] 那一列。
  Future<ShellHarness> openSection(
    WidgetTester tester,
    String section, {
    double width = 1000,
    Log? log,
    void Function(ShellHarness h)? seed,
  }) async {
    final h = ShellHarness(log: log, redactor: Redactor());
    // 先清掉 harness 自己記的，測試只看自己寫的。
    h.log.minimumLevel = LogLevel.debug;
    await tester.runAsync(h.log.clear);
    seed?.call(h);
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

  /// 讓記憶體歷史的快照（合併過的重發）送到畫面。
  Future<void> refresh(WidgetTester tester) async {
    await tester.pump(logHistoryRefreshDelay);
    await tester.pump();
  }

  /// 讓真的檔案 I/O（與它在假時間 zone 裡的後續）跑完：log 檔的操作從畫面發起時，後續在
  /// 假時間的微任務裡，只有 `pump` 會推進它，所以交替等真實時間與 pump。
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
  }

  /// 在畫面外攔下 `Clipboard.setData`。
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

  /// 在系統暫存目錄建一個有 log 檔的門面（測試結束時刪掉）。
  Log fileLog() {
    final dir = Directory.systemTemp.createTempSync('fmp_debug_log_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    return Log(
      redactor: Redactor(),
      minimumLevel: LogLevel.debug,
      file: LogFile(Directory(p.join(dir.path, 'logs'))),
    );
  }

  /// 選下拉選單的項目：先點目前的值，再點選單裡的那一項（目前值也在選單裡，取最後一個）。
  Future<void> pick(WidgetTester tester, String current, String item) async {
    await tester.tap(find.text(current));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  void seedLog(ShellHarness h) {
    h.log
      ..info('alpha message', tag: 'app')
      ..warning('beta message', tag: 'net')
      ..error('gamma message', tag: 'app', fields: {'type': 'ParseError'})
      ..debug('delta message', tag: 'net');
  }

  /// 畫面上這些文字由上到下的順序。
  List<String> order(WidgetTester tester, List<String> texts) {
    final found = [
      for (final text in texts)
        if (find.text(text).evaluate().isNotEmpty)
          (text, tester.getTopLeft(find.text(text)).dy),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final (text, _) in found) text];
  }

  group('the sections', () {
    testWidgets('are Overview, Log and Network in the ADR 0025 order', (
      tester,
    ) async {
      await openSection(tester, 'Overview');

      final tops = [
        for (final name in ['Overview', 'Log & errors', 'Network'])
          tester.getTopLeft(find.widgetWithText(ListTile, name)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(tops.toSet(), hasLength(3));
    });

    testWidgets('400 wide: Log opens from the list and back goes to it', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(
        tester,
        size: const Size(400, 800),
        collapsePanel: true,
      );
      await tester.tap(find.text('Settings').first);
      await h.loadSettings(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Debug'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Log & errors'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();
      expect(find.byType(DebugLog), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(DebugLog), findsNothing);
      expect(find.widgetWithText(ListTile, 'Network'), findsOneWidget);
    });
  });

  group('the Log section', () {
    // ADR 0025 §決定 3：`report` 寫的錯誤紀錄（有 `fields.type`）展開後有「詳細」，開
    // 和提示同一個詳細頁；別的紀錄沒有。
    testWidgets(
      'an error record opens the detail page, others have no button',
      (tester) async {
        await openSection(
          tester,
          'Log & errors',
          seed: (h) {
            h.log
              ..info('plain message', tag: 'app', fields: {'a': 1})
              ..report(
                'Search failed',
                ParseError(pluginId: 'alpha'),
                tag: 'search',
              );
          },
        );

        await tester.tap(find.text('plain message'));
        await tester.pumpAndSettle();
        expect(find.text('Details'), findsNothing);

        await tester.tap(find.text('Search failed'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Details'));
        await tester.pumpAndSettle();

        expect(find.byType(ErrorDetailPage), findsOneWidget);
        expect(find.text('ParseError'), findsOneWidget);
        expect(find.text('alpha'), findsWidgets);
      },
    );

    testWidgets('lists this run, newest first, with a count', (tester) async {
      await openSection(tester, 'Log & errors', seed: seedLog);

      expect(find.text('4 of 4 records'), findsOneWidget);
      expect(
        order(tester, [
          'alpha message',
          'beta message',
          'gamma message',
          'delta message',
        ]),
        ['delta message', 'gamma message', 'beta message', 'alpha message'],
      );
    });

    testWidgets('a record written while it is open shows up', (tester) async {
      final h = await openSection(tester, 'Log & errors', seed: seedLog);
      expect(find.text('late message'), findsNothing);

      h.log.info('late message', tag: 'app');
      await refresh(tester);

      expect(find.text('late message'), findsOneWidget);
      expect(find.text('5 of 5 records'), findsOneWidget);
    });

    testWidgets('filters by level, tag and text', (tester) async {
      await openSection(tester, 'Log & errors', seed: seedLog);

      await pick(tester, 'All levels', 'warning and above');
      expect(find.text('2 of 4 records'), findsOneWidget);
      expect(find.text('alpha message'), findsNothing);
      expect(find.text('delta message'), findsNothing);
      expect(find.text('beta message'), findsOneWidget);

      await pick(tester, 'All tags', 'app');
      expect(find.text('1 of 4 records'), findsOneWidget);
      expect(find.text('gamma message'), findsOneWidget);
      expect(find.text('beta message'), findsNothing);

      await pick(tester, 'warning and above', 'All levels');
      await pick(tester, 'app', 'All tags');
      await tester.enterText(find.byType(TextField), 'DELTA');
      await tester.pump();
      expect(find.text('1 of 4 records'), findsOneWidget);
      expect(find.text('delta message'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'matches nothing');
      await tester.pump();
      expect(find.text('No records match the filters'), findsOneWidget);
    });

    testWidgets('errors only is the warning and error history', (tester) async {
      await openSection(tester, 'Log & errors', seed: seedLog);

      await tester.tap(find.widgetWithText(FilterChip, 'Errors only'));
      await tester.pump();

      expect(find.text('2 of 4 records'), findsOneWidget);
      expect(find.text('gamma message'), findsOneWidget);
      expect(find.text('beta message'), findsOneWidget);
      expect(find.text('alpha message'), findsNothing);
    });

    testWidgets('a record with details expands in place', (tester) async {
      await openSection(tester, 'Log & errors', seed: seedLog);
      expect(find.textContaining('ParseError'), findsNothing);

      await tester.tap(find.text('gamma message'));
      await tester.pumpAndSettle();

      expect(find.textContaining('"type":"ParseError"'), findsOneWidget);
    });

    testWidgets('copy filtered copies only what is shown, oldest first', (
      tester,
    ) async {
      final copied = captureClipboard(tester);
      await openSection(tester, 'Log & errors', seed: seedLog);
      await tester.tap(find.widgetWithText(FilterChip, 'Errors only'));
      await tester.pump();

      await tester.tap(find.byTooltip('Copy filtered'));
      await tester.pump();

      expect(copied, hasLength(1));
      final lines = copied.single.split('\n');
      expect(lines.first, contains('warning [net] beta message'));
      expect(copied.single, contains('error [app] gamma message'));
      expect(
        copied.single.indexOf('beta message'),
        lessThan(copied.single.indexOf('gamma message')),
      );
      expect(copied.single, isNot(contains('alpha message')));
      expect(copied.single, contains('"type":"ParseError"'));
      expect(find.text('Copied 2 records'), findsOneWidget);
    });

    testWidgets('clear log asks first; cancel keeps everything', (
      tester,
    ) async {
      final h = await openSection(tester, 'Log & errors', seed: seedLog);

      await tester.tap(find.byTooltip('Clear log'));
      await tester.pumpAndSettle();
      expect(find.text('Clear the log?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(h.log.history, hasLength(4));
      expect(find.text('alpha message'), findsOneWidget);
    });

    testWidgets('clear log empties the history and the log files', (
      tester,
    ) async {
      final log = fileLog();
      await openSection(tester, 'Log & errors', log: log, seed: (h) {});
      await tester.runAsync(() async {
        log
          ..info('alpha message', tag: 'app')
          ..warning('beta message', tag: 'net');
        await log.file!.flush();
      });
      await refresh(tester);
      expect(find.text('alpha message'), findsOneWidget);
      expect(log.file!.currentFile.existsSync(), isTrue);

      await tester.tap(find.byTooltip('Clear log'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear log'));
      await tester.pump();
      await settleIo(tester);
      await refresh(tester);

      expect(log.history, isEmpty);
      expect(log.file!.currentFile.existsSync(), isFalse);
      expect(find.text('No records'), findsOneWidget);
      expect(find.text('Log cleared'), findsOneWidget);
    });

    testWidgets('the earlier records toggle is hidden without a log file', (
      tester,
    ) async {
      await openSection(tester, 'Log & errors', seed: seedLog);

      expect(
        find.widgetWithText(FilterChip, 'Include earlier records'),
        findsNothing,
      );
    });

    testWidgets('including earlier records merges the files without '
        'repeating this run', (tester) async {
      final log = fileLog();
      // 上一次執行留在檔案裡的；這次執行寫的那兩筆同時在記憶體和檔案。
      final earlier = LogRecord(
        time: DateTime.utc(2020, 1, 1),
        level: LogLevel.error,
        tag: 'old',
        message: 'earlier message',
      );
      await openSection(tester, 'Log & errors', log: log, seed: (h) {});
      await tester.runAsync(() async {
        log.file!.write(earlier.toJsonLine());
        log
          ..info('alpha message', tag: 'app')
          ..warning('beta message', tag: 'net');
        await log.file!.flush();
      });
      await refresh(tester);
      expect(find.text('earlier message'), findsNothing);
      expect(find.text('2 of 2 records'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FilterChip, 'Include earlier records'),
      );
      await tester.pump();
      await settleIo(tester);

      expect(find.text('earlier message'), findsOneWidget);
      expect(find.text('3 of 3 records'), findsOneWidget);
      expect(find.text('alpha message'), findsOneWidget);
      // 最舊的在最下面。
      expect(
        order(tester, ['earlier message', 'alpha message', 'beta message']),
        ['beta message', 'alpha message', 'earlier message'],
      );

      // 「只看錯誤」對檔案裡的也成立。
      await tester.tap(find.widgetWithText(FilterChip, 'Errors only'));
      await tester.pump();
      expect(find.text('earlier message'), findsOneWidget);
      expect(find.text('alpha message'), findsNothing);
    });
  });

  group('the Network section', () {
    void request(
      Log log,
      int id, {
      String pluginId = 'alpha',
      String path = '/search',
      int? status = 200,
      int? bytes = 2048,
      String? error,
      String query = 'q=song',
    }) => writeNetworkRecord(
      log,
      client: NetworkClient.source,
      id: id,
      pluginId: pluginId,
      method: 'GET',
      uri: Uri.parse('https://api.example.test$path?$query'),
      failed: status == null || status >= 400,
      credentials: false,
      retry: 0,
      status: status,
      ms: 120,
      bytes: bytes,
      error: error,
    );

    void seedRequests(ShellHarness h) {
      request(h.log, 1);
      request(h.log, 2, path: '/missing', status: 404);
      request(h.log, 3, pluginId: 'beta', path: '/boom', status: 503);
      request(
        h.log,
        4,
        pluginId: 'beta',
        path: '/offline',
        status: null,
        bytes: null,
        error: 'NetworkError',
      );
    }

    testWidgets('says what it lists when it is empty', (tester) async {
      await openSection(tester, 'Network');

      expect(find.text('No requests recorded'), findsOneWidget);
      expect(find.textContaining('during this run'), findsOneWidget);
    });

    testWidgets('a row shows the time, status, duration, size and source', (
      tester,
    ) async {
      await openSection(tester, 'Network', seed: seedRequests);

      expect(find.text('4 of 4 requests'), findsOneWidget);
      expect(
        find.textContaining('GET api.example.test/search'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          RegExp(r'\d\d:\d\d:\d\d\.\d{3} · 200 · 120 ms · 2 KB · alpha'),
        ),
        findsOneWidget,
      );
      // 沒有回應：沒有狀態碼、大小未知。
      expect(
        find.textContaining(RegExp(r'· Failed · 120 ms · — · beta')),
        findsOneWidget,
      );
      // 最新的在最上面。
      expect(
        order(tester, [
          'GET api.example.test/search',
          'GET api.example.test/missing',
          'GET api.example.test/boom',
          'GET api.example.test/offline',
        ]),
        [
          'GET api.example.test/offline',
          'GET api.example.test/boom',
          'GET api.example.test/missing',
          'GET api.example.test/search',
        ],
      );
    });

    testWidgets('filters by source, status class and text', (tester) async {
      await openSection(tester, 'Network', seed: seedRequests);

      await pick(tester, 'All sources', 'beta');
      expect(find.text('2 of 4 requests'), findsOneWidget);
      expect(find.textContaining('/search'), findsNothing);
      expect(find.textContaining('/boom'), findsOneWidget);

      await pick(tester, 'All statuses', '5xx');
      expect(find.text('1 of 4 requests'), findsOneWidget);
      expect(find.textContaining('/boom'), findsOneWidget);
      expect(find.textContaining('/offline'), findsNothing);

      await pick(tester, '5xx', 'Failed');
      expect(find.text('1 of 4 requests'), findsOneWidget);
      expect(find.textContaining('/offline'), findsOneWidget);

      await pick(tester, 'Failed', 'All statuses');
      await pick(tester, 'beta', 'All sources');
      await pick(tester, 'All statuses', '4xx');
      expect(find.text('1 of 4 requests'), findsOneWidget);
      expect(find.textContaining('/missing'), findsOneWidget);

      await pick(tester, '4xx', 'All statuses');
      await tester.enterText(find.byType(TextField), 'SEARCH');
      await tester.pump();
      expect(find.text('1 of 4 requests'), findsOneWidget);
    });

    testWidgets('the detail shows the query, the error type and the matching '
        'error records', (tester) async {
      await openSection(
        tester,
        'Network',
        seed: (h) {
          request(h.log, 3, pluginId: 'beta', path: '/boom', status: 503);
          request(
            h.log,
            4,
            pluginId: 'beta',
            path: '/offline',
            status: null,
            bytes: null,
            error: 'NetworkError',
            query: 'q=song&page=2',
          );
          h.log
            ..report(
              'Playback failed',
              NetworkError(networkRecordId: 4),
              tag: 'beta',
            )
            ..report(
              'Other request failed',
              NetworkError(networkRecordId: 3),
              tag: 'beta',
            );
        },
      );

      await tester.tap(find.textContaining('/offline'));
      await tester.pumpAndSettle();

      expect(find.text('GET api.example.test'), findsOneWidget);
      expect(find.text('q=song&page=2'), findsOneWidget);
      expect(find.text('NetworkError'), findsWidgets);
      expect(find.textContaining('Playback failed'), findsOneWidget);
      expect(find.textContaining('"networkRecordId":4'), findsOneWidget);
      // 另一個請求的錯誤不算。
      expect(find.textContaining('Other request failed'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.text('GET api.example.test'), findsNothing);
    });

    // ADR 0011 §決定 3：畫面上與複製出去的都是遮過的內容（兩個區塊只讀門面的歷史）。
    testWidgets('fake credentials never reach the detail or the copied log', (
      tester,
    ) async {
      final copied = captureClipboard(tester);
      final h = await openSection(
        tester,
        'Network',
        seed: (h) {
          request(
            h.log,
            1,
            status: 401,
            query: 'q=song&access_token=FAKE_TOKEN_123',
          );
          h.log.report(
            'Search failed',
            NetworkError(
              networkRecordId: 1,
              cause: 'Cookie: SESSDATA=FAKE_SESSDATA_123',
            ),
            tag: 'alpha',
          );
        },
      );

      await tester.tap(find.textContaining('/search'));
      await tester.pumpAndSettle();
      expect(find.text('q=song&access_token=***'), findsOneWidget);
      expect(find.textContaining('Search failed'), findsOneWidget);
      expect(find.textContaining('FAKE_'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      // 同一份歷史在 Log 區塊複製出去（1000 寬：區塊清單在左邊）。
      await tester.tap(find.widgetWithText(ListTile, 'Log & errors'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();
      expect(find.byType(DebugLog), findsOneWidget);
      await tester.tap(find.byTooltip('Copy filtered'));
      await tester.pump();
      expect(copied.single, contains('Search failed'));
      expect(copied.single, contains('access_token=***'));
      expect(copied.single, isNot(contains('FAKE_')));
    });

    testWidgets('the detail of a request without error records says none', (
      tester,
    ) async {
      await openSection(tester, 'Network', seed: seedRequests);

      await tester.tap(find.textContaining('/search'));
      await tester.pumpAndSettle();

      expect(find.text('Matching error records'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('None'),
        ),
        findsWidgets,
      );
      expect(find.byType(DebugNetwork), findsOneWidget);
    });
  });
}
