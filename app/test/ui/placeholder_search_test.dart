import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/placeholder/placeholder_page.dart';

import '../support/fake_http.dart';
import '../support/fjs.dart';

/// 佔位畫面的搜尋（票 08）：搜一次，每個能搜尋的插件列出結果或錯誤。
/// 插件是寫在這裡的小插件，跑在真的引擎裡；引擎的呼叫是真的非同步，
/// 所以等結果時用 `runAsync`。
void main() {
  late Directory logDir;
  late Log log;
  late PluginHost host;

  setUpAll(loadFjsForTests);
  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    logDir = Directory.systemTemp.createTempSync('fmp_search_ui_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    String manifest(String id, String name, List<String> capabilities) =>
        jsonEncode({
          'id': id,
          'name': name,
          'version': '1.0.0',
          'capabilities': capabilities,
          'domains': ['api.example.com'],
        });
    host = PluginHost(
      bundles: [
        PluginBundle(
          manifest: manifest('songs', 'Songs', ['search']),
          code: '''
            export async function search({ query }) {
              const res = await host.http.request({ url: 'https://api.example.com/s' });
              return { tracks: [
                { id: '1', title: query + ' ' + res.body, author: 'Alice', durationMs: 245000 },
                { id: '2', title: 'Long one', author: 'Bob', durationMs: 3723000 },
                { id: '3', title: 'No length', author: 'Carol' },
              ] };
            }
          ''',
        ),
        PluginBundle(
          manifest: manifest('busy', 'Busy', ['search']),
          code: '''
            export async function search() { throw new PluginError('rate_limited'); }
          ''',
        ),
        PluginBundle(
          manifest: manifest('quiet', 'Quiet', []),
          code: 'export async function search() { throw new Error("never"); }',
        ),
      ],
      log: log,
      httpAdapter: FakeHttp((_) => const FakeResponse(200, 'live')),
    );
  });
  tearDown(() async {
    LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale);
    logDir.deleteSync(recursive: true);
  });

  testWidgets('searching lists title, author and duration per plugin, and '
      'the error of a plugin that failed', (tester) async {
    await tester.pumpWidget(
      buildRoot(overrides: [pluginHostProvider.overrideWith((_) => host)]),
    );

    await tester.enterText(find.byType(TextField), '晴天');
    // 在真的 zone 裡送出：搜尋的 Future 跟著建在那裡，fjs 的回應才排得
    // 進來（在 widget 測試的假時間 zone 裡發起會一直停在載入中）。
    await tester.runAsync(
      () => tester.testTextInput.receiveAction(TextInputAction.search),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 引擎在真的時間裡回答；結果回來後要 pump 才會畫出來。
    for (
      var i = 0;
      i < 500 && find.text('Alice · 4:05').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('晴天 live'), findsOneWidget);
    expect(find.text('Alice · 4:05'), findsOneWidget);
    expect(find.text('Bob · 1:02:03'), findsOneWidget);
    expect(find.text('Carol'), findsOneWidget);
    expect(find.text('Busy'), findsOneWidget);
    expect(find.text('請求太頻繁，請稍後再試'), findsOneWidget);
    // 沒宣告 search 的插件不出現。
    expect(find.text('Quiet'), findsNothing);

    // 關引擎與 log 要真的 I/O，不能在 widget 測試的假時間裡等。
    await tester.runAsync(() async {
      await host.close();
      await log.close();
    });
  });

  test('formatDuration', () {
    expect(formatDuration(const Duration(seconds: 5)), '0:05');
    expect(formatDuration(const Duration(minutes: 12, seconds: 3)), '12:03');
    expect(formatDuration(const Duration(hours: 2, seconds: 9)), '2:00:09');
  });
}
