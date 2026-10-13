import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/endpoints.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/ui/errors/error_detail_page.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_url_opener.dart';
import '../support/shell_harness.dart';

// 錯誤詳細頁與提示的「詳細」「回報」（M3 PR 13，ADR 0023 §決定 4）。

void main() {
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

  /// 寫一筆對應請求加一筆錯誤歷史（含假憑證），回傳 `report` 寫的紀錄。
  LogRecord seedError(ShellHarness h) {
    writeNetworkRecord(
      h.log,
      client: NetworkClient.source,
      id: 7,
      pluginId: 'alpha',
      method: 'GET',
      uri: Uri.parse(
        'https://api.example.test/search?q=song&access_key=FAKE_ACCESS_KEY_123',
      ),
      failed: true,
      credentials: false,
      retry: 0,
      status: 412,
      ms: 830,
    );
    return h.log.report(
      'Search failed',
      ParseError(
        pluginId: 'alpha',
        networkRecordId: 7,
        cause: StateError('bad payload Cookie: SESSDATA=FAKE_SESSDATA_123'),
        stackTrace: StackTrace.fromString(
          '#0      parse (package:alpha/x.js:1)',
        ),
      ),
      tag: 'search',
    )!;
  }

  Future<ShellHarness> openPage(
    WidgetTester tester, {
    FakeUrlOpener? opener,
    Size size = const Size(1000, 800),
    LogRecord Function(ShellHarness h)? record,
  }) async {
    final h = ShellHarness(urlOpener: opener, redactor: Redactor());
    await h.pumpApp(
      tester,
      ErrorDetailPage(record: (record ?? seedError)(h)),
      size: size,
    );
    await h.loadSettings(tester);
    await tester.pumpAndSettle();
    return h;
  }

  Future<void> tapAndLoad(WidgetTester tester, ShellHarness h, Finder f) async {
    await tester.tap(f);
    await h.loadSettings(tester);
    await tester.pumpAndSettle();
  }

  final copyButton = find.widgetWithText(OutlinedButton, 'Copy');
  final reportButton = find.widgetWithText(FilledButton, 'Report on GitHub');
  final reminder = find.text('Check before you submit');

  Future<bool?> dismissed(WidgetTester tester, ShellHarness h) async =>
      (await tester.runAsync(
        () => h
            .container(tester)
            .read(developerSettingsRepositoryProvider)
            .read(),
      ))!.reportReminderDismissed;

  testWidgets('shows the report fields, selectable', (tester) async {
    await openPage(tester);

    expect(find.byType(SelectionArea), findsWidgets);
    for (final text in [
      'ParseError',
      'alpha',
      'Search failed',
      'GET api.example.test/search?q=song',
      '412',
      '830 ms',
      '1.2.3 (dev)',
      'Windows, Windows 11 (test)',
    ]) {
      expect(find.textContaining(text), findsWidgets, reason: text);
    }
    expect(find.textContaining('package:alpha/x.js:1'), findsOneWidget);
    // 紀錄與頁面都不出現假憑證。
    expect(find.textContaining('FAKE_'), findsNothing);
  });

  testWidgets('a record without a matching request says so', (tester) async {
    await openPage(
      tester,
      record: (h) =>
          h.log.report('Load failed', UnexpectedError(), tag: 'app')!,
    );

    expect(find.text('No matching request record'), findsOneWidget);
  });

  testWidgets('Copy puts the markdown on the clipboard', (tester) async {
    final copied = captureClipboard(tester);
    await openPage(tester);

    await tester.tap(copyButton);
    await tester.pump();

    expect(copied, hasLength(1));
    expect(copied.single, startsWith('## ParseError: Search failed\n'));
    expect(copied.single, contains('- **Source**: alpha\n'));
    expect(copied.single, contains('### Stack trace'));
    expect(copied.single, isNot(contains('FAKE_')));
    expect(find.text('Copied'), findsOneWidget);
  });

  group('Report on GitHub', () {
    testWidgets('asks first, then copies and opens exactly the template url', (
      tester,
    ) async {
      final copied = captureClipboard(tester);
      final opener = FakeUrlOpener();
      final h = await openPage(tester, opener: opener);

      await tapAndLoad(tester, h, reportButton);
      expect(reminder, findsOneWidget);
      expect(opener.opened, isEmpty);
      expect(copied, isEmpty);

      await tapAndLoad(tester, h, find.text('Continue'));

      // 網址就是常數，報告內容不在網址裡。
      expect(opener.opened, [Uri.parse(newIssueUrl)]);
      final url = opener.opened.single.toString();
      expect(url, newIssueUrl);
      for (final part in ['ParseError', 'alpha', 'search', 'Search', 'FAKE']) {
        expect(url, isNot(contains(part)));
      }
      expect(copied.single, startsWith('## ParseError: Search failed'));
      expect(
        find.text(
          'Report copied. Paste it into the "Error report" field on GitHub.',
        ),
        findsOneWidget,
      );
      // 沒勾「不再提醒」：沒寫入，下次還會問。
      expect(await dismissed(tester, h), isNull);
      await tapAndLoad(tester, h, reportButton);
      expect(reminder, findsOneWidget);
    });

    testWidgets('"don\'t remind me again" is stored and skips the dialog', (
      tester,
    ) async {
      final opener = FakeUrlOpener();
      final h = await openPage(tester, opener: opener);

      await tapAndLoad(tester, h, reportButton);
      await tapAndLoad(tester, h, find.text("Don't remind me again"));
      await tapAndLoad(tester, h, find.text('Continue'));
      expect(await dismissed(tester, h), isTrue);
      expect(opener.opened, hasLength(1));

      await tapAndLoad(tester, h, reportButton);
      expect(reminder, findsNothing);
      expect(opener.opened, hasLength(2));
    });

    testWidgets('cancelling opens nothing, copies nothing, stores nothing', (
      tester,
    ) async {
      final copied = captureClipboard(tester);
      final opener = FakeUrlOpener();
      final h = await openPage(tester, opener: opener);

      await tapAndLoad(tester, h, reportButton);
      await tapAndLoad(tester, h, find.text("Don't remind me again"));
      await tapAndLoad(tester, h, find.text('Cancel'));

      expect(reminder, findsNothing);
      expect(opener.opened, isEmpty);
      expect(copied, isEmpty);
      expect(await dismissed(tester, h), isNull);
    });

    testWidgets('without the capability it only copies and shows the url', (
      tester,
    ) async {
      final copied = captureClipboard(tester);
      final h = await openPage(tester);
      expect(find.text(newIssueUrl), findsOneWidget);

      await tapAndLoad(tester, h, reportButton);
      await tapAndLoad(tester, h, find.text('Continue'));

      expect(copied.single, startsWith('## ParseError: Search failed'));
      expect(find.text(newIssueUrl), findsOneWidget);
    });

    testWidgets('a browser that cannot open shows the url too', (tester) async {
      final opener = FakeUrlOpener(result: false);
      final h = await openPage(tester, opener: opener);
      expect(find.text(newIssueUrl), findsNothing);

      await tapAndLoad(tester, h, reportButton);
      await tapAndLoad(tester, h, find.text('Continue'));

      expect(opener.opened, hasLength(1));
      expect(
        find.text(
          'Could not open the browser. Open the address below yourself.',
        ),
        findsWidgets,
      );
      expect(find.text(newIssueUrl), findsOneWidget);
    });
  });

  group('the toast actions open this page', () {
    Future<ShellHarness> pumpHome(WidgetTester tester) async {
      final h = ShellHarness(redactor: Redactor());
      await h.pumpApp(
        tester,
        const Scaffold(body: Center(child: Text('home'))),
      );
      await h.loadSettings(tester);
      return h;
    }

    testWidgets('Details in developer mode', (tester) async {
      final h = await pumpHome(tester);
      h.toastDeveloperMode = true;

      h.toaster.error(
        ParseError(pluginId: 'alpha'),
        operation: 'Search failed',
        tag: 'search',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Details'));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorDetailPage), findsOneWidget);
      expect(find.text('ParseError'), findsOneWidget);
      // 動作按下後提示收起；頁面是全螢幕路由，之後的提示仍在它之上（ADR 0023 §決定 3）。
      expect(find.byType(SnackBar), findsNothing);
      h.toaster.warning('Above the page');
      await tester.pumpAndSettle();
      expect(find.text('Above the page').hitTestable(), findsOneWidget);
    });

    testWidgets('Report for a bug in normal mode', (tester) async {
      final h = await pumpHome(tester);

      h.toaster.error(
        UnexpectedError(),
        operation: 'Search failed',
        tag: 'search',
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Details'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Report'));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorDetailPage), findsOneWidget);
      expect(find.text('UnexpectedError'), findsOneWidget);
    });
  });
}
