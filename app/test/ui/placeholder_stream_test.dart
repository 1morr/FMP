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

/// 佔位畫面點一首曲目（票 10）：用提供它的插件解析串流，顯示音質、到期
/// 時間與遮蔽過的網址；失敗時顯示錯誤分類。插件寫在這裡，跑在真的引擎裡。
void main() {
  late Directory logDir;
  late Log log;
  late PluginHost host;

  setUpAll(loadFjsForTests);
  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    logDir = Directory.systemTemp.createTempSync('fmp_stream_ui_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    String manifest(String id, List<String> capabilities) => jsonEncode({
      'id': id,
      'name': id,
      'version': '1.0.0',
      'capabilities': capabilities,
      'domains': ['api.example.com'],
    });
    host = PluginHost(
      bundles: [
        PluginBundle(
          manifest: manifest('songs', ['search', 'resolveStream']),
          code: '''
            export async function search() {
              return { tracks: [
                { id: 'ok', title: 'Playable', author: 'Alice' },
                { id: 'gone', title: 'Gone', author: 'Bob' },
              ] };
            }
            export async function resolveStream({ trackId }) {
              if (trackId === 'gone') throw new PluginError('not_found');
              return {
                url: 'https://cdn.example.com/' + trackId +
                  '.m4a?deadline=1767225600&upsig=SECRET123',
                headers: { Referer: 'https://example.com' },
                expiresAtMs: 1767225600000,
                codec: 'mp4a.40.2',
                bitrate: 134695,
              };
            }
          ''',
        ),
        PluginBundle(
          manifest: manifest('searchonly', ['search']),
          code: '''
            export async function search() {
              return { tracks: [{ id: 'x', title: 'Search only', author: 'Carol' }] };
            }
          ''',
        ),
      ],
      log: log,
      httpAdapter: FakeHttp((_) => const FakeResponse(404)),
    );
  });
  tearDown(() async {
    LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale);
    logDir.deleteSync(recursive: true);
  });

  /// 在真的時間裡等引擎回答，直到 [finder] 出現。
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 500 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('tapping a track shows its stream, or why it has none', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildRoot(overrides: [pluginHostProvider.overrideWith((_) => host)]),
    );
    await tester.enterText(find.byType(TextField), 'q');
    await tester.runAsync(
      () => tester.testTextInput.receiveAction(TextInputAction.search),
    );
    await waitFor(tester, find.text('Playable'));

    await tester.runAsync(() async => tester.tap(find.text('Playable')));
    await waitFor(tester, find.textContaining('音質'));

    expect(find.text('音質：mp4a.40.2 · 135 kbps'), findsOneWidget);
    expect(
      find.text('到期：${formatExpiry(DateTime.utc(2026).toLocal())}'),
      findsOneWidget,
    );
    // 網址照遮蔽規則顯示（brief §13）。
    expect(
      find.text('網址：https://cdn.example.com/ok.m4a?deadline=***&upsig=***'),
      findsOneWidget,
    );
    expect(find.textContaining('SECRET123'), findsNothing);

    await tester.runAsync(() async => tester.tap(find.text('Gone')));
    await waitFor(tester, find.text('找不到這首曲目'));
    expect(find.text('找不到這首曲目'), findsOneWidget);
    expect(find.textContaining('音質'), findsNothing);

    await tester.runAsync(() async => tester.tap(find.text('Search only')));
    await waitFor(tester, find.text('這個音源不支援解析串流'));
    expect(find.text('這個音源不支援解析串流'), findsOneWidget);

    await tester.runAsync(() async {
      await host.close();
      await log.close();
    });
  });

  test('formatExpiry', () {
    expect(formatExpiry(DateTime(2026, 1, 2, 3, 4)), '2026-01-02 03:04');
    expect(formatExpiry(DateTime(2026, 11, 12, 23, 59)), '2026-11-12 23:59');
  });
}
