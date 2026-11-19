import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show DioException;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/storage_notice.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/search/search_page.dart';

import '../support/fake_audio_backend.dart';
import '../support/fake_http.dart';
import '../support/fjs.dart';
import '../support/shell.dart';

/// 搜尋頁裡的佔位搜尋點一首曲目（M0 票 10、11）：用提供它的插件解析串流並播放，顯示
/// 播放狀態、音質、到期時間與遮蔽過的網址，能用播放膠囊暫停、繼續；失敗時
/// 顯示錯誤分類，沒有網路時跳出提示。插件寫在這裡，跑在真的引擎裡；音訊後端是假的。
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
            export async function search({ query }) {
              if (query === 'long') {
                return { tracks: [
                  { id: 'long', title: 'Long', author: 'Eve', durationMs: 3573000 },
                ] };
              }
              return { tracks: [
                { id: 'ok', title: 'Playable', author: 'Alice' },
                { id: 'gone', title: 'Gone', author: 'Bob' },
                { id: 'offline', title: 'Offline', author: 'Dan' },
              ] };
            }
            export async function resolveStream({ trackId }) {
              if (trackId === 'gone') throw new PluginError('not_found');
              if (trackId === 'offline') {
                await host.http.request({ url: 'https://api.example.com/play' });
              }
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
      // 沒有網路：連不上 API。
      httpAdapter: FakeHttp(
        (request) => throw DioException.connectionError(
          requestOptions: request,
          reason: 'offline',
        ),
      ),
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

  /// 等到正在播（搜尋頁沒有狀態文字，讀播放狀態）。
  Future<void> waitForPlaying(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchPage)),
    );
    for (
      var i = 0;
      i < 500 &&
          container.read(playbackProvider)?.status != PlaybackStatus.playing;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(container.read(playbackProvider)?.status, PlaybackStatus.playing);
  }

  testWidgets('the transport bar shows the track\'s own length '
      'when the backend reports a much shorter one', (tester) async {
    // AVPlayer 遇到 CDN 中途斷線時把長度截短（事實 M14）。
    final backend = FakeAudioBackend()
      ..loadedDuration = const Duration(minutes: 33, seconds: 10);
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          pluginHostProvider.overrideWith((_) => host),
          audioBackendProvider.overrideWithValue(backend),
        ],
      ),
    );
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'long');
    await tester.runAsync(
      () => tester.testTextInput.receiveAction(TextInputAction.search),
    );
    await waitFor(tester, find.text('Long'));

    await tester.runAsync(() async => tester.tap(find.text('Long')));
    await waitForPlaying(tester);

    expect(find.text('0:00 / 59:33'), findsOneWidget);
    expect(find.textContaining('33:10'), findsNothing);
  });

  testWidgets('when the database cannot be opened, a toast says nothing will '
      'be saved and tracks still play', (tester) async {
    final backend = FakeAudioBackend();
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          pluginHostProvider.overrideWith((_) => host),
          audioBackendProvider.overrideWithValue(backend),
          storageNoticeProvider.overrideWithValue(
            StorageNotice.databaseUnavailable,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('無法開啟資料庫，這次的佇列與進度不會保存'), findsOneWidget);

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'q');
    await tester.runAsync(
      () => tester.testTextInput.receiveAction(TextInputAction.search),
    );
    await waitFor(tester, find.text('Playable'));
    await tester.runAsync(() async => tester.tap(find.text('Playable')));
    await waitForPlaying(tester);

    expect(backend.calls, ['load', 'play']);
  });

  testWidgets('when the last queue cannot be read back, a toast says a copy '
      'was kept', (tester) async {
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          pluginHostProvider.overrideWith((_) => host),
          audioBackendProvider.overrideWithValue(FakeAudioBackend()),
          storageNoticeProvider.overrideWithValue(
            StorageNotice.queueUnreadable,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('上次的佇列讀不回來，已另存一份'), findsOneWidget);
    // 和其他沒有動作的提示一樣，4 秒後收起（再等淡出跑完）。
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('上次的佇列讀不回來，已另存一份'), findsNothing);
  });
}
