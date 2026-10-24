import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/backup.dart';
import 'package:fmp/charts/chart_jobs.dart';
import 'package:fmp/core/endpoints.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/radio.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/developer_settings_repository.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/live_play.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/accounts/web_login.dart';
import 'package:fmp/plugins/dev/plugin_development.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/radio/radio_status_jobs.dart';
import 'package:fmp/ui/charts/explore_page.dart';
import 'package:fmp/ui/debug/debug_database.dart';
import 'package:fmp/ui/debug/debug_health.dart';
import 'package:fmp/ui/debug/debug_log.dart';
import 'package:fmp/ui/debug/debug_network.dart';
import 'package:fmp/ui/debug/debug_overview.dart';
import 'package:fmp/ui/debug/debug_playback.dart';
import 'package:fmp/ui/debug/debug_plugin_dev.dart';
import 'package:fmp/ui/debug/debug_reset.dart';
import 'package:fmp/ui/errors/error_detail_page.dart';
import 'package:fmp/ui/library/remote_write_state.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/track_detail_parts.dart';
import 'package:fmp/ui/player/track_details.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/shell/now_playing_panel.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/player/queue_view.dart';
import 'package:fmp/ui/settings/about_section.dart';
import 'package:fmp/ui/settings/appearance_controls.dart';
import 'package:fmp/ui/settings/backup_controls.dart';
import 'package:fmp/ui/settings/library_controls.dart';
import 'package:fmp/ui/settings/network_controls.dart';
import 'package:fmp/ui/settings/playback_controls.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../playback/fake_audio_backend.dart';
import '../library/fake_import_plugin.dart';
import '../playback/fake_source_plugin.dart';
import '../plugins/dev/dev_support.dart' show tempFolder;
import '../plugins/plugin_harness.dart';
import '../support/fake_login_webview.dart';
import '../support/memory_database.dart';
import 'charts/chart_harness.dart';
import 'library/import_preview_harness.dart';
import 'support/fake_app_backup.dart';
import 'support/fake_artwork.dart';
import 'support/fake_data_reset.dart';
import 'support/fake_file_sharer.dart';
import 'support/fake_url_opener.dart';
import 'support/health_page.dart';
import 'support/plugin_dev_page.dart';
import 'support/plugin_page_harness.dart';
import 'support/shell_harness.dart';

// ADR 0024 §如何確認：淺色與深色主題下通過點擊區與對比度 guideline。示範畫面
// 驗證主題本身（M3 元件、token 的語意色、四種提示）；外殼裡的搜尋頁、設定頁與
// 播放列在窄與寬兩種視窗各驗一次。

/// 示範畫面：文字角色、常見按鈕、外觀設定控制項。
class _Demo extends StatelessWidget {
  const _Demo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('示範')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('標題', style: theme.textTheme.titleLarge),
            Text('內文', style: theme.textTheme.bodyMedium),
            Text('說明', style: theme.textTheme.bodySmall),
            Wrap(
              spacing: tokens.spacing.x2,
              children: [
                FilledButton(onPressed: () {}, child: const Text('確定')),
                OutlinedButton(onPressed: () {}, child: const Text('取消')),
                TextButton(onPressed: () {}, child: const Text('更多')),
                IconButton(
                  tooltip: '播放',
                  onPressed: () {},
                  icon: const Icon(Icons.play_arrow),
                ),
              ],
            ),
            const AppearanceControls(),
          ],
        ),
      ),
    );
  }
}

void main() {
  for (final brightness in Brightness.values) {
    group('$brightness', () {
      late Toaster toaster;

      Future<void> pumpDemo(WidgetTester tester) async {
        toaster = Toaster(
          log: Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
          translations: AppLocale.zhTw.buildSync,
          sourceName: (_) => null,
        );
        addTearDown(toaster.dispose);
        final database = memoryDatabase();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(database),
              toasterProvider.overrideWithValue(toaster),
            ],
            child: MaterialApp(
              theme: buildAppTheme(
                Brightness.light,
                fontFamilyFallback: const [],
                textLocale: _hant,
              ),
              darkTheme: buildAppTheme(
                Brightness.dark,
                fontFamilyFallback: const [],
                textLocale: _hant,
              ),
              themeMode: themeModeOf(switch (brightness) {
                Brightness.light => ThemeModeSetting.light,
                Brightness.dark => ThemeModeSetting.dark,
              }),
              builder: (context, navigator) => ToastHost(child: navigator!),
              home: const _Demo(),
            ),
          ),
        );
        // 外觀設定從記憶體資料庫讀出來（drift 的串流要真的事件迴圈）。
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RadioListTile<LocaleSetting?>), findsNWidgets(4));
      }

      Future<void> expectGuidelines(WidgetTester tester) async {
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }

      testWidgets('the demo screen meets the guidelines', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpDemo(tester);

        await expectGuidelines(tester);
        handle.dispose();
      });

      for (final kind in ToastKind.values) {
        testWidgets('a ${kind.name} toast meets the guidelines', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          await pumpDemo(tester);
          final action = ToastAction(label: '復原', onPressed: () {});
          switch (kind) {
            case ToastKind.success:
              toaster.success('已加入歌單', action: action);
            case ToastKind.info:
              toaster.info('已複製連結', action: action);
            case ToastKind.warning:
              toaster.warning('儲存空間不足', action: action);
            case ToastKind.error:
              toaster.error(
                RateLimited(pluginId: 'bilibili'),
                operation: 'Search failed',
                tag: 'test',
                action: action,
              );
          }
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });
      }

      for (final size in const [Size(400, 800), Size(1000, 700)]) {
        final width = size.width;

        // 曲目詳細區（M3 PR 21）：完整資料、取不到、載入中。
        Future<void> pumpDetails(
          WidgetTester tester,
          FutureOr<TrackDetail> Function(TrackDetailQuery query) onDetail,
        ) async {
          final h = ShellHarness(trackDetail: true, registryOfSources: true);
          h.plugin.onTrackDetail = onDetail;
          await h.pumpApp(
            tester,
            const Scaffold(
              body: TrackDetails(
                track: TrackInfo(
                  sourceTypeId: 'fmp-test',
                  sourceId: 'a',
                  title: 'Song a',
                  uploader: 'Uploader a',
                ),
              ),
            ),
            size: size,
            brightness: brightness,
          );
          await tester.pump();
          await tester.pump();
        }

        testWidgets('the track details with data at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await pumpDetails(
            tester,
            (_) => TrackDetail(
              description: List.generate(8, (i) => 'Line $i').join('\n'),
              publishedAt: DateTime.utc(2024, 5, 17, 12),
              album: 'The album',
              stats: [
                for (final kind in TrackStatKind.values)
                  TrackStat(kind: kind, count: 12345),
              ],
            ),
          );
          expect(find.text('Published'), findsOneWidget);
          expect(find.text('Show more'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the track details that failed at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await pumpDetails(
            tester,
            (_) => throw NetworkError(pluginId: 'fmp-test'),
          );
          expect(find.text('Retry'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the track details while loading at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          await pumpDetails(tester, (_) => Completer<TrackDetail>().future);
          expect(find.byType(TrackDetailPlaceholder), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('search, before searching, at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await ShellHarness().pumpShell(
            tester,
            size: size,
            brightness: brightness,
          );

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('search results and the player bar at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.enterText(find.byType(TextField), 'song');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pump();
          await tester.tap(find.text('Song a'));
          await tester.pump(const Duration(milliseconds: 200));
          // 輸入框沒有焦點：游標閃爍會讓對比度的取樣時好時壞。
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 分 P 的搜尋結果（M3 PR 20）：影片列有展開鈕，展開後列出分 P、取分 P 失敗時有重試。
        for (final failed in [false, true]) {
          testWidgets(
            'search results with the parts ${failed ? 'failed' : 'expanded'} '
            'at $width',
            (tester) async {
              final handle = tester.ensureSemantics();
              final h = ShellHarness(
                multiPart: true,
                registryOfSources: true,
                onSearch: (_) => SearchPage(
                  items: [summary('a', partCount: 3), summary('b')],
                  hasMore: false,
                ),
              );
              h.plugin.onMultiPart = (_) => failed
                  ? throw RateLimited(pluginId: 'fmp-test')
                  : MultiPartResult(
                      parts: [
                        for (var i = 1; i <= 3; i++)
                          MultiPart(
                            cid: i,
                            title: 'Part $i',
                            duration: Duration(seconds: 30 * i),
                            index: i,
                          ),
                      ],
                    );
              await h.pumpShell(tester, size: size, brightness: brightness);
              await tester.enterText(find.byType(TextField), 'song');
              await tester.testTextInput.receiveAction(TextInputAction.search);
              await tester.pump();
              await tester.pump();
              await tester.tap(find.byTooltip('Show parts').first);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle(const Duration(seconds: 10));
              expect(
                find.text(failed ? 'Couldn’t load the parts' : 'P2 Part 2'),
                findsOneWidget,
              );

              await expectGuidelines(tester);
              handle.dispose();
            },
          );
        }

        // 多選（M4 PR 5）：選取列換掉音源 chip 列，影片列與展開的分 P 列都有勾選框、選了的有底色。
        testWidgets('search results while selecting at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(
            multiPart: true,
            registryOfSources: true,
            onSearch: (_) => SearchPage(
              items: [summary('a', partCount: 3), summary('b')],
              hasMore: false,
            ),
          );
          h.plugin.onMultiPart = (_) => MultiPartResult(
            parts: [
              for (var i = 1; i <= 3; i++)
                MultiPart(cid: i, title: 'Part $i', index: i),
            ],
          );
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.enterText(find.byType(TextField), 'song');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pump();
          await tester.pump();
          await tester.tap(find.byTooltip('Show parts').first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.longPress(find.text('Song a'));
          await tester.pump();
          await tester.tap(find.text('P2 Part 2'));
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle(const Duration(seconds: 10));
          expect(find.text('2 selected'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        for (final status in [
          NetworkStatus.noInterface,
          NetworkStatus.unreachable,
        ]) {
          testWidgets('a search that failed while ${status.name} at $width', (
            tester,
          ) async {
            final handle = tester.ensureSemantics();
            final h = ShellHarness(
              onSearch: (_) => throw NetworkError(pluginId: 'fmp-test'),
            );
            await h.pumpShell(tester, size: size, brightness: brightness);
            await h.setNetwork(tester, status);
            await tester.enterText(find.byType(TextField), 'song');
            await tester.testTextInput.receiveAction(TextInputAction.search);
            FocusManager.instance.primaryFocus?.unfocus();
            // 錯誤提示照時長消失，只量離線提示與離線空狀態。
            await tester.pumpAndSettle();
            await tester.pump(const Duration(seconds: 7));
            await tester.pumpAndSettle();
            expect(find.byType(SnackBar), findsNothing);
            expect(find.text('Retry'), findsOneWidget);

            await expectGuidelines(tester);
            handle.dispose();
          });
        }

        // 播放列的狀態標示（ADR 0018 §決定 7）：以主色寫在曲名下面。
        testWidgets('the player bar waiting for the network at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          h.plugin.respond = (_) => throw NetworkError(pluginId: 'fmp-test');
          await h.pumpShell(tester, size: size, brightness: brightness);
          await h.setNetwork(tester, NetworkStatus.noInterface);
          await h.play(tester, [summary('a')]);
          // 按鈕裡的轉圈一直在動，不能等 pumpAndSettle。
          await tester.pump(const Duration(seconds: 1));
          expect(
            find.textContaining('Waiting for the network'),
            findsOneWidget,
          );

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('history, empty, at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          await h.pumpShell(tester, size: size, brightness: brightness);
          await h.openHistory(tester);
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          expect(find.text('No play history yet'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('history with entries and the player bar at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          await h.pumpShell(tester, size: size, brightness: brightness);
          await h.openHistory(tester);
          final repository = h
              .container(tester)
              .read(playHistoryRepositoryProvider);
          await tester.runAsync(() async {
            for (final (id, at) in [
              ('a', DateTime(2026, 10, 7, 14, 5)),
              ('b', DateTime(2026, 10, 6, 9, 30)),
              ('c', DateTime(2025, 12, 31, 23, 30)),
            ]) {
              await repository.record(
                summary(id).toTrackInfo(),
                playedAt: at,
                limit: 100,
              );
            }
          });
          await h.loadSettings(tester);
          await h.play(tester, [summary('a')]);
          await tester.pumpAndSettle(const Duration(seconds: 1));
          expect(find.text('Song c'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('history while selecting at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          await h.pumpShell(tester, size: size, brightness: brightness);
          await h.openHistory(tester);
          final repository = h
              .container(tester)
              .read(playHistoryRepositoryProvider);
          await tester.runAsync(() async {
            for (final (id, minute) in [('a', 5), ('b', 6)]) {
              await repository.record(
                summary(id).toTrackInfo(),
                playedAt: DateTime(2026, 10, 7, 14, minute),
                limit: 100,
              );
            }
          });
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          await tester.longPress(find.text('Song b'));
          await tester.pumpAndSettle();
          expect(find.text('1 selected'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 電台頁（M3 PR 18c）：空清單、四種狀態的列（開播中附直播標題）。
        testWidgets('radio, empty, at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Radio'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          expect(find.text('No stations yet'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('radio with stations at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(artworkManager: FakeArtworkManager());
          await h.pumpShell(tester, size: size, brightness: brightness);
          await h.loadSettings(tester);
          final repository = h.container(tester).read(radioRepositoryProvider);
          // 假時間裡寫：電台頁已經在監看這張表（見 radio_page_test 的說明）。
          for (final (id, status, liveTitle) in [
            ('a', RadioLiveStatus.live, 'Tonight on air'),
            ('b', RadioLiveStatus.offline, null),
            ('c', null, null),
            ('d', RadioLiveStatus.offline, null),
          ]) {
            await repository.add(
              pluginId: 'fmp-test',
              roomId: id,
              title: 'Station $id',
              hostName: 'Host $id',
              artwork: _trackArtwork(TestArtwork.darkest),
              addedAt: DateTime.utc(2026, 10, 14),
              liveStatus: status,
              liveTitle: liveTitle,
            );
          }
          await h.loadSettings(tester);
          final stations = h
              .container(tester)
              .read(radioStationsProvider)
              .value!;
          h
              .container(tester)
              .read(radioQueryFailuresProvider.notifier)
              .mark(stations.last.id);
          await tester.tap(find.text('Radio'));
          await h.loadSettings(tester);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          expect(find.text('Tonight on air'), findsOneWidget);
          expect(find.text('Check failed'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 首頁（M4 PR 2）：沒有內容時的說明；最近播放一排卡片加播放列。
        testWidgets('home, empty, at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          await h.pumpShell(
            tester,
            size: size,
            brightness: brightness,
            at: ShellDestination.home,
          );
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          expect(find.text('Nothing here yet'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('home with recent plays and the player bar at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(artworkManager: FakeArtworkManager());
          await h.pumpShell(
            tester,
            size: size,
            brightness: brightness,
            at: ShellDestination.home,
          );
          await tester.runAsync(() async {
            final repository = h
                .container(tester)
                .read(playHistoryRepositoryProvider);
            for (final (index, id) in ['a', 'b', 'c', 'd'].indexed) {
              await repository.record(
                summary(
                  id,
                  artwork: index.isEven
                      ? TestArtwork.darkest.artwork
                      : TestArtwork.lightest.artwork,
                ).toTrackInfo(),
                playedAt: DateTime(2026, 10, 15, 8, index),
                limit: 100,
              );
            }
          });
          await h.loadSettings(tester);
          await h.play(tester, [summary('a')]);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle(const Duration(seconds: 1));
          expect(find.text('Recently played'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 首頁（M4 PR 4）：我的歌單與電台（四種狀態）加最近播放。
        testWidgets('home with playlists, radio and recent plays at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(artworkManager: FakeArtworkManager());
          await h.pumpShell(
            tester,
            size: size,
            brightness: brightness,
            at: ShellDestination.home,
          );
          await tester.runAsync(() async {
            final container = h.container(tester);
            final playlists = container.read(playlistRepositoryProvider);
            final road = await playlists.create(name: 'Road trip');
            await playlists.addTracks(road, [
              summary('a', artwork: TestArtwork.darkest.artwork).toTrackInfo(),
            ]);
            await playlists.create(name: 'Empty');
            await container
                .read(playHistoryRepositoryProvider)
                .record(
                  summary(
                    'b',
                    artwork: TestArtwork.lightest.artwork,
                  ).toTrackInfo(),
                  playedAt: DateTime(2026, 10, 15, 8),
                  limit: 100,
                );
          });
          // 假時間裡寫：首頁已經在監看電台表（見 radio_page_test 的說明）。
          final radio = h.container(tester).read(radioRepositoryProvider);
          for (final (id, status) in [
            ('a', RadioLiveStatus.live),
            ('b', RadioLiveStatus.offline),
            ('c', null),
            ('d', RadioLiveStatus.offline),
          ]) {
            await radio.add(
              pluginId: 'fmp-test',
              roomId: id,
              title: 'Station $id',
              hostName: 'Host $id',
              artwork: _trackArtwork(TestArtwork.darkest),
              addedAt: DateTime.utc(2026, 10, 14),
              liveStatus: status,
            );
          }
          for (var i = 0; i < 3; i++) {
            await h.loadSettings(tester);
          }
          h
              .container(tester)
              .read(radioQueryFailuresProvider.notifier)
              .mark(
                h.container(tester).read(radioStationsProvider).value!.last.id,
              );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          expect(find.text('My playlists'), findsOneWidget);
          expect(find.text('Check failed'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 首頁的排行與探索頁（M4 PR 21）：有快取（含「更新失敗」）、沒有快取而離線、探索頁與多選中。
        testWidgets('home with charts at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final c = ChartHarness();
          await c.pumpShell(tester, size: size, brightness: brightness);
          c.shell
              .container(tester)
              .read(chartFailuresProvider.notifier)
              .mark(c.key('new'));
          await tester.pump();
          expect(find.text('Update failed'), findsOneWidget);
          expect(find.text('Track 1 of hot'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('home charts offline without a cache at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final c = ChartHarness();
          hangCharts(c.plugin);
          await c.pumpShell(tester, size: size, brightness: brightness);
          await c.shell.setNetwork(tester, NetworkStatus.noInterface);
          expect(find.byType(OfflineMessage), findsNWidgets(2));

          await expectGuidelines(tester);
          handle.dispose();
        });

        Future<ChartHarness> openExplore(WidgetTester tester) async {
          final c = ChartHarness();
          await c.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('View all').first);
          await tester.pumpAndSettle();
          expect(find.byType(ExplorePage), findsOneWidget);
          return c;
        }

        testWidgets('explore at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openExplore(tester);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('explore while selecting at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openExplore(tester);
          await tester.longPress(
            find.descendant(
              of: find.byType(ExplorePage),
              matching: find.text('Track 2 of hot'),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('1 selected'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 音樂庫（M4 PR 2）：空的、有歌單（1000 寬時面板開著，內容區是清單；收起面板是格狀）、
        // 卡片選單、建立對話框與刪除的確認框。
        Future<ShellHarness> openLibrary(
          WidgetTester tester, {
          bool playlists = true,
          bool collapsePanel = false,
          bool registry = false,
          bool mix = false,
        }) async {
          final h = ShellHarness(
            artworkManager: FakeArtworkManager(),
            registryOfSources: registry,
            mix: mix,
          );
          await h.pumpShell(
            tester,
            size: size,
            brightness: brightness,
            at: ShellDestination.library,
            collapsePanel: collapsePanel,
          );
          if (playlists) {
            await tester.runAsync(() async {
              final repository = h
                  .container(tester)
                  .read(playlistRepositoryProvider);
              final road = await repository.create(name: 'Road trip');
              await repository.addTracks(road, [
                summary(
                  'a',
                  artwork: TestArtwork.darkest.artwork,
                ).toTrackInfo(),
                summary('b').toTrackInfo(),
              ]);
              await repository.create(name: 'Empty');
              final one = await repository.create(name: 'Late night');
              await repository.addTracks(one, [
                summary(
                  'c',
                  artwork: TestArtwork.lightest.artwork,
                ).toTrackInfo(),
              ]);
            });
          }
          for (var i = 0; i < 3; i++) {
            await h.loadSettings(tester);
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          return h;
        }

        testWidgets('library, empty, at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openLibrary(tester, playlists: false);
          expect(find.text('No playlists yet'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('library with playlists at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openLibrary(tester);
          expect(find.text('Local · 2 songs'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('library with playlists, panel collapsed, at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          await openLibrary(tester, collapsePanel: true);
          expect(find.text('Late night'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the playlist menu at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openLibrary(tester);
          await tester.tap(
            find
                .descendant(
                  of: find.ancestor(
                    of: find.text('Road trip'),
                    matching: find.byType(ListTile),
                  ),
                  matching: find.byTooltip('More options'),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(find.text('Add all to queue'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the new playlist dialog at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openLibrary(tester);
          await tester.tap(find.byTooltip('New playlist'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).first, 'Road');
          await tester.enterText(find.byType(TextField).first, '');
          await tester.pump();
          expect(find.text('Enter a name'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the delete confirmation at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openLibrary(tester);
          await tester.tap(
            find
                .descendant(
                  of: find.ancestor(
                    of: find.text('Empty'),
                    matching: find.byType(ListTile),
                  ),
                  matching: find.byTooltip('More options'),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          expect(find.text('Delete the playlist?'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 歌單詳情（M4 PR 3）：標頭、分 P 群組、本機歌單的把手；匯入歌單；空的；「加入歌單」
        // 對話框；自訂封面被拒的編輯對話框。
        Future<ShellHarness> openDetail(
          WidgetTester tester, {
          bool imported = false,
          bool empty = false,
        }) async {
          final h = await openLibrary(tester, playlists: false);
          await tester.runAsync(() async {
            final repository = h
                .container(tester)
                .read(playlistRepositoryProvider);
            final id = imported
                ? (await repository.createImported(
                    pluginId: 'fmp-test',
                    remoteId: 'r1',
                    info: const RemotePlaylistInfo(
                      name: 'Road trip',
                      description: 'Songs for the drive',
                    ),
                  ))!
                : await repository.create(
                    name: 'Road trip',
                    description: 'Songs for the drive',
                  );
            if (empty) return;
            await repository.addTracks(id, [
              summary('a', artwork: TestArtwork.darkest.artwork).toTrackInfo(),
              for (final index in [1, 2])
                TrackInfo(
                  sourceTypeId: 'fmp-test',
                  sourceId: 'v',
                  cid: index,
                  title: 'Part $index',
                  uploader: 'Uploader v',
                  duration: const Duration(minutes: 1),
                  partIndex: index,
                  parentTitle: 'A video',
                  artwork: [
                    TrackArtwork(url: Uri.parse(TestArtwork.lightest.url)),
                  ],
                ),
              summary('b').toTrackInfo(),
            ]);
          });
          for (var i = 0; i < 3; i++) {
            await h.loadSettings(tester);
          }
          await tester.pumpAndSettle();
          await tester.tap(find.text('Road trip'));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          return h;
        }

        testWidgets('the playlist details at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openDetail(tester);
          expect(find.text('A video'), findsOneWidget);
          expect(find.text('P2 Part 2'), findsOneWidget);
          expect(find.byIcon(Icons.drag_handle), findsWidgets);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('an imported playlist details at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openDetail(tester, imported: true);
          expect(find.text('Imported · 4 songs'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 匯入歌單的狀態列（M4 PR 8b）：需要使用者處理的三種（警示色）。
        for (final (name, mark, text, action) in [
          (
            'failed',
            (PlaylistRefreshSession session) => session.markFailed(),
            'Refresh failed',
            'Retry',
          ),
          (
            'source gone',
            (PlaylistRefreshSession session) =>
                session.markStatus(PlaylistRemoteStatus.sourceGone),
            'Source gone: the remote playlist was deleted or is no longer '
                'accessible',
            'Retry',
          ),
          (
            'sign-in needed',
            (PlaylistRefreshSession session) =>
                session.markStatus(PlaylistRemoteStatus.authRequired),
            'Sign in to refresh this playlist',
            'Sign in',
          ),
        ]) {
          testWidgets('an imported playlist, $name, at $width', (tester) async {
            final handle = tester.ensureSemantics();
            final h = await openDetail(tester, imported: true);
            await tester.runAsync(() async {
              final session = (await h
                  .container(tester)
                  .read(playlistRepositoryProvider)
                  .beginRefresh(1, isCurrent: () => true))!;
              await mark(session);
            });
            for (var i = 0; i < 3; i++) {
              await h.loadSettings(tester);
            }
            await tester.pumpAndSettle();
            expect(find.text(text), findsOneWidget);
            expect(find.widgetWithText(TextButton, action), findsOneWidget);

            await expectGuidelines(tester);
            handle.dispose();
          });
        }

        testWidgets('the playlist details while selecting at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          await openDetail(tester);
          await tester.longPress(find.text('Song a'));
          await tester.pump();
          await tester.tap(find.text('P2 Part 2'));
          await tester.pumpAndSettle();
          expect(find.text('2 selected'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('removing the selected songs asks first at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          await openDetail(tester);
          await tester.longPress(find.text('Song a'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Remove from playlist'));
          await tester.pumpAndSettle();
          expect(find.text('Remove the selected songs?'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('an empty playlist details at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openDetail(tester, empty: true);
          expect(find.text('This playlist has no songs yet'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // Mix 歌單（M4 PR 11）：詳情（「Mix 播放」能按與停用寫原因兩種）與編輯對話框（只有名稱）。
        Future<ShellHarness> openMix(
          WidgetTester tester, {
          bool mix = true,
        }) async {
          final h = await openLibrary(
            tester,
            playlists: false,
            registry: true,
            mix: mix,
          );
          await tester.runAsync(() async {
            final container = h.container(tester);
            await container
                .read(playlistRepositoryProvider)
                .createMix(
                  name: 'Chill',
                  pluginId: 'fmp-test',
                  seedSourceId: 'a',
                );
            await container.read(tracksRepositoryProvider).upsert([
              summary('a', artwork: TestArtwork.darkest.artwork).toTrackInfo(),
            ]);
          });
          for (var i = 0; i < 3; i++) {
            await h.loadSettings(tester);
          }
          await tester.pumpAndSettle();
          return h;
        }

        testWidgets('a Mix playlist details at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openMix(tester);
          await tester.tap(find.text('Chill'));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          expect(find.widgetWithText(FilledButton, 'Mix play'), findsOneWidget);
          expect(find.text('Song a'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('a Mix playlist details without Mix at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          await openMix(tester, mix: false);
          await tester.tap(find.text('Chill'));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          expect(find.text("This source doesn't support Mix"), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('editing a Mix playlist at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openMix(tester);
          await tester.tap(find.byTooltip('More options').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Edit'));
          await tester.pumpAndSettle();
          expect(find.text('Name'), findsOneWidget);
          expect(find.text('Cover'), findsNothing);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the add to playlist dialog at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openDetail(tester);
          await tester.tap(
            find
                .descendant(
                  of: find.widgetWithText(ListTile, 'Song a'),
                  matching: find.byTooltip('More options'),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Add to playlist…'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(CheckboxListTile, 'Road trip'));
          await tester.pumpAndSettle();
          expect(find.text('Add to playlist'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the import dialog with an unknown link at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          await openLibrary(tester, registry: true);
          await tester.tap(find.byTooltip('Import a playlist'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextField, 'Link'),
            'https://elsewhere.example/list',
          );
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, 'Import'));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          expect(
            find.text("This link isn't recognized by any installed source"),
            findsOneWidget,
          );

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 能播的插件的歌單（M4 PR 19，§17 第 19 條）：認出網址後的兩個選擇。
        testWidgets('the import dialog with the matching choice at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final source = FakeImportPlugin(onUrl: (_) => PlaylistIdRef('p1'));
          final h = ShellHarness(registryOfSources: true, sources: [source]);
          await h.pumpShell(
            tester,
            size: size,
            brightness: brightness,
            at: ShellDestination.library,
          );
          await h.loadSettings(tester);
          await tester.tap(find.byTooltip('Import a playlist'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextField, 'Link'),
            'https://fmp.test/p1',
          );
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          expect(find.text('Match to other sources'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 匯入預覽頁（M4 PR 19，design §10.9）：匹配中、完成（有匹配失敗與搜尋失敗、展開一首）、
        // `truncated` 的提示。
        testWidgets('the import preview while matching at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final hold = Completer<List<TrackSummary>>();
          final preview = PreviewHarness(
            results: (keyword) => keyword.startsWith('Green')
                ? hold.future
                : previewResults(keyword),
          );
          await preview.open(tester, size: size, brightness: brightness);
          await preview.start(tester, animations: false);
          expect(find.text('Searching…'), findsOneWidget);

          await expectGuidelines(tester);
          hold.complete(const []);
          await preview.settle(tester);
          handle.dispose();
        });

        testWidgets('the import preview when matched at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final preview = PreviewHarness(
            results: (keyword) => keyword.startsWith('Green')
                ? throw RateLimited(pluginId: 'video')
                : previewResults(keyword),
          );
          await preview.open(tester, size: size, brightness: brightness);
          await preview.start(tester);
          expect(find.text('No match'), findsOneWidget);
          expect(find.text('Search failed'), findsOneWidget);
          await expectGuidelines(tester);
          // 展開一首：候選、關鍵字與排除。
          await expandPreviewRow(tester, 'Blue Sky');
          expect(find.text('2 songs left out'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the import preview of a truncated playlist at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final preview = PreviewHarness(
            onPage: (_) => previewPage(previewSongs, truncated: true),
          );
          await preview.open(tester, size: size, brightness: brightness);
          expect(
            find.text('The source only provided part of the playlist'),
            findsOneWidget,
          );

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the import preview leave confirmation at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final preview = PreviewHarness();
          await preview.open(tester, size: size, brightness: brightness);
          // 開始匹配之後才要確認。
          await preview.start(tester);
          await tester.tap(find.byTooltip('Cancel the import'));
          await tester.pumpAndSettle();
          expect(find.text('Stop importing?'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('editing an imported playlist at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = await openLibrary(tester, playlists: false);
          await tester.runAsync(() async {
            final repository = h
                .container(tester)
                .read(playlistRepositoryProvider);
            final id = (await repository.createImported(
              pluginId: 'fmp-test',
              remoteId: 'r1',
              info: const RemotePlaylistInfo(name: 'Road trip'),
            ))!;
            await repository.updateImported(
              id,
              name: 'Mine',
              nameOverridden: true,
              descriptionOverridden: false,
              artworkOverridden: false,
            );
          });
          for (var i = 0; i < 3; i++) {
            await h.loadSettings(tester);
          }
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('More options').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Edit'));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
          expect(find.text("Use the remote's"), findsOneWidget);
          // 有自動刷新間隔欄位（只有匯入歌單的編輯有）。
          expect(find.text('Auto refresh'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the playlist dialog with a refused cover at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          await openLibrary(tester);
          await tester.tap(find.byTooltip('New playlist'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, 'Custom'));
          await tester.pump();
          await tester.enterText(
            find.widgetWithText(TextField, 'Image URL'),
            'https://elsewhere.example/cover.jpg',
          );
          await tester.pumpAndSettle();
          expect(
            find.text("This URL doesn't belong to any installed source"),
            findsOneWidget,
          );

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 搜尋頁的直播間模式（M3 PR 18c）：分段鈕、篩選與直播間結果。
        testWidgets('search in live room mode at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(live: true);
          h.plugin.onLiveSearch = (_) => const LiveSearchPage(
            items: [
              LiveRoom(
                roomId: 'r1',
                title: 'Room one',
                hostName: 'Host one',
                status: LiveRoomStatus.live,
                online: 12345,
              ),
              LiveRoom(
                roomId: 'r2',
                title: 'Room two',
                hostName: 'Host two',
                status: LiveRoomStatus.offline,
              ),
            ],
            hasMore: false,
          );
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Live rooms'));
          await tester.pump();
          await tester.enterText(find.byType(TextField), 'night');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pump();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          expect(find.text('Room one'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 播放列的直播版（M3 PR 18c）；1000 寬時右側面板也是直播版。
        testWidgets('the live player bar at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await _listening(tester, size, brightness);
          expect(find.textContaining('watching'), findsWidgets);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 播放頁的直播版（M3 PR 18c）：直播間的封面當背景，毛玻璃上的標記、已收聽與人數。
        testWidgets('the live player page at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await _listening(tester, size, brightness);
          await tester.tap(
            find
                .descendant(
                  of: find.byKey(PlayerBar.titleKey),
                  matching: find.byType(Text),
                )
                .first,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(PlayerPage), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('settings at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.pumpAndSettle();

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 設定頁寬版的第一組是帳號（M3 PR 8）：外觀另外點開。
        testWidgets('appearance settings at $width', (tester) async {
          final handle = tester.ensureSemantics();
          // 字型清單與主題色塊都在這一頁：給平台的字型，清單才有項目。
          final h = ShellHarness(fontChoices: const ['serif', 'monospace']);
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.text('Appearance'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          expect(find.byType(AppearanceControls), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('playback settings at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.text('Playback'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          expect(find.byType(PlaybackControls), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 設定頁的「音樂庫」（M4 PR 21）：首頁排行的清單（一個停用）與沒有榜單時的說明。
        testWidgets('library settings at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final c = ChartHarness();
          await c.pumpShell(
            tester,
            size: size,
            brightness: brightness,
            at: ShellDestination.settings,
          );
          await tester.tap(find.widgetWithText(ListTile, 'Library'));
          await c.settle(tester);
          await c.setEnabled(tester, 'new', enabled: false);
          expect(find.byType(CheckboxListTile), findsNWidgets(2));

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('library settings without charts at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.widgetWithText(ListTile, 'Library'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          expect(find.byType(LibraryControls), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 設定頁「音樂庫」的「匹配目標音源」（M4 PR 19）：一個取消勾選。
        testWidgets('library settings with match targets at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          FakeSourcePlugin target(String id, String name) => FakeSourcePlugin(
            (_) => const [],
            id: id,
            name: name,
            onSearch: (_) => const SearchPage(items: [], hasMore: false),
          );
          final h = ShellHarness(
            registryOfSources: true,
            sources: [target('alpha', 'Alpha'), target('beta', 'Beta')],
          );
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.widgetWithText(ListTile, 'Library'));
          for (var i = 0; i < 3; i++) {
            await h.loadSettings(tester);
          }
          await tester.pumpAndSettle();
          final beta = find.widgetWithText(CheckboxListTile, 'Beta');
          await tester.ensureVisible(beta);
          await tester.pumpAndSettle();
          await tester.tap(beta);
          for (var i = 0; i < 3; i++) {
            await h.loadSettings(tester);
          }
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<CheckboxListTile>(
                  find.widgetWithText(CheckboxListTile, 'Beta'),
                )
                .value,
            isFalse,
          );

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('network settings at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.text('Network'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          expect(find.byType(NetworkControls), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 「關於」與 Debug 頁（M3 PR 11）：dev 的開發者模式預設開，清單最後有 Debug。
        testWidgets('the about section at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.text('About'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          expect(find.byType(AboutSection), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 備份與還原（M4 PR 22）：設定組，與還原確認框（列出插件與網域、警告）。
        testWidgets('the backup settings at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(
            fileDialogs: FakeFileDialogs(),
            extraOverrides: [
              appBackupProvider.overrideWithValue(FakeAppBackup()),
            ],
          );
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.widgetWithText(ListTile, 'Backup and restore'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          expect(find.byType(BackupControls), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the restore confirmation at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(
            fileDialogs: FakeFileDialogs(),
            dataReset: FakeDataReset(),
            extraOverrides: [
              appBackupProvider.overrideWithValue(
                FakeAppBackup(staged: FakeDataReset.staged),
              ),
            ],
          );
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.widgetWithText(ListTile, 'Backup and restore'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Restore from backup file'));
          await tester.pumpAndSettle();
          expect(find.text('Restore from this backup?'), findsOneWidget);
          expect(find.text('Test Source 1.2.3'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the restore confirmation with a comparison at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(
            fileDialogs: FakeFileDialogs(),
            dataReset: FakeDataReset(),
            extraOverrides: [
              appBackupProvider.overrideWithValue(
                FakeAppBackup(staged: FakeDataReset.staged),
              ),
            ],
          );
          await h.pumpShell(tester, size: size, brightness: brightness);
          // 這台有較新的 fmp-test，只允許 example.test：備份的版本較舊、多一個網域。
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
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.widgetWithText(ListTile, 'Backup and restore'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Restore from backup file'));
          await tester.pumpAndSettle();
          expect(find.textContaining('Older than this device'), findsOneWidget);
          expect(find.textContaining('New on this device'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the Debug overview at $width', (tester) async {
          final handle = tester.ensureSemantics();
          // 有存檔與分享的平台：診斷包的三個按鈕都在。
          final h = ShellHarness(
            fileDialogs: FakeFileDialogs(),
            fileSharer: FakeFileSharer(),
          );
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.text('Debug'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          // 窄版先是區塊清單：清單本身也要過，再點進概覽。
          if (size.width < 600) {
            expect(find.byType(DebugOverview), findsNothing);
            await expectGuidelines(tester);
            await tester.tap(find.text('Overview'));
            await h.loadSettings(tester);
            await tester.pumpAndSettle();
          }
          expect(find.byType(DebugOverview), findsOneWidget);
          expect(find.text('Share'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 診斷包第一次匯出前的「送出前請檢查」提醒（M3 PR 15）。
        testWidgets('the Debug export reminder at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(
            fileDialogs: FakeFileDialogs(),
            redactor: Redactor(),
          );
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.text('Debug'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          if (size.width < 600) {
            await tester.tap(find.text('Overview'));
            await h.loadSettings(tester);
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(find.text('Save as file'));
          await tester.tap(find.text('Save as file'));
          await tester.pumpAndSettle();
          expect(find.text('Check before you submit'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 重設資料與備份還原（M3 PR 14b）：區塊本身、重設的確認對話框、還原的備份清單。
        testWidgets('the Debug reset section at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(
            dataReset: FakeDataReset(listed: [FakeDataReset.made]),
          );
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.text('Debug'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Reset data'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          expect(find.byType(DebugReset), findsOneWidget);
          await expectGuidelines(tester);

          await tester.tap(find.text('Reset data…'));
          await tester.pumpAndSettle();
          expect(find.text('Reset all data?'), findsOneWidget);
          await expectGuidelines(tester);
          await tester.tap(find.byType(CheckboxListTile));
          // 按鈕從停用換成啟用有色彩動畫，停下來再量對比。
          await tester.pumpAndSettle();
          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the Debug restore dialogs at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(
            redactor: Redactor(),
            dataReset: FakeDataReset(listed: [FakeDataReset.made]),
          );
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.text('Debug'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Database'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          await expectGuidelines(tester);

          await tester.tap(find.text('Restore from backup'));
          await tester.pumpAndSettle();
          expect(find.text('Choose a backup to restore'), findsOneWidget);
          await expectGuidelines(tester);
          await tester.tap(find.text('2 KB'));
          await tester.pumpAndSettle();
          expect(find.text('Restore from this backup?'), findsOneWidget);
          await expectGuidelines(tester);
          handle.dispose();
        });

        // Log 與網路區塊（M3 PR 12）：有各層級的紀錄與各狀態的請求、展開一筆。
        for (final section in ['Log', 'Network']) {
          testWidgets('the Debug $section section at $width', (tester) async {
            final handle = tester.ensureSemantics();
            final h = ShellHarness();
            h.log.minimumLevel = LogLevel.debug;
            h.log
              ..debug('a debug record', tag: 'app')
              ..info('an info record', tag: 'app')
              ..warning('a warning record', tag: 'net')
              ..error(
                'an error record',
                tag: 'app',
                error: 'boom',
                fields: {'type': 'ParseError'},
              );
            for (final status in [200, 404, 503, null]) {
              writeNetworkRecord(
                h.log,
                client: NetworkClient.source,
                id: status ?? 0,
                pluginId: 'alpha',
                method: 'GET',
                uri: Uri.parse('https://api.example.test/search?q=song'),
                failed: status == null || status >= 400,
                credentials: false,
                retry: 0,
                status: status,
                ms: 120,
                bytes: status == null ? null : 2048,
              );
            }
            await h.pumpShell(tester, size: size, brightness: brightness);
            await tester.tap(find.text('Settings').first);
            await h.loadSettings(tester);
            await tester.tap(find.text('Debug'));
            await h.loadSettings(tester);
            await tester.pumpAndSettle();
            await tester.tap(
              find.widgetWithText(
                ListTile,
                section == 'Log' ? 'Log & errors' : section,
              ),
            );
            await h.loadSettings(tester);
            await tester.pumpAndSettle();
            expect(
              find.byType(section == 'Log' ? DebugLog : DebugNetwork),
              findsOneWidget,
            );
            await expectGuidelines(tester);

            // 展開的一筆（Log）與單筆詳細的對話框（網路）。
            await tester.tap(
              section == 'Log'
                  ? find.text('an error record')
                  : find.textContaining('api.example.test/search').first,
            );
            await tester.pumpAndSettle();
            if (section == 'Network') {
              expect(find.byType(AlertDialog), findsOneWidget);
            } else {
              expect(find.textContaining('ParseError'), findsOneWidget);
            }
            await expectGuidelines(tester);
            handle.dispose();
          });
        }

        // 播放狀態與資料庫區塊（M3 PR 14a）：有在播的內容；表的列頁與檢查結果。
        Future<ShellHarness> openDebugSection(
          WidgetTester tester,
          String section,
        ) async {
          final h = ShellHarness(redactor: Redactor());
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.tap(find.text('Debug'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ListTile, section));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          return h;
        }

        testWidgets('the Debug Playback section at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = await openDebugSection(tester, 'Playback');
          expect(find.byType(DebugPlayback), findsOneWidget);
          // 空狀態。
          await expectGuidelines(tester);

          await h.play(tester, [summary('a'), summary('b'), summary('c')]);
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
          expect(find.text('Copy snapshot'), findsOneWidget);
          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the Debug Health section at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openHealth(tester, size: size, brightness: brightness);
          expect(find.byType(DebugHealth), findsOneWidget);
          // 清單：有案例、沒有案例、停用。
          await expectGuidelines(tester);

          // 結果：通過、略過與失敗。
          await tester.tap(find.text('Check all'));
          await settleHealth(tester);
          expect(find.textContaining('Failed'), findsWidgets);
          await expectGuidelines(tester);
          handle.dispose();
        });

        // 插件開發（M3 PR 16b）：三種卡片（開發中、取代已安裝、載入失敗），跑完之後通過與
        // 失敗的結果列各展開一個，錄製模式的警告。
        testWidgets('the Debug Plugin Development section at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final folder = buildDevFolder();
          final installed =
              File(p.join(folder.path, 'a-http', 'http_test_plugin.js'))
                  .readAsStringSync()
                  .replaceFirst('"version": "1.0.0"', '"version": "0.5.0"');
          final h = await openPluginDev(
            tester,
            size: Size(width, 2600),
            brightness: brightness,
            folder: folder,
            installed: [installed],
          );
          expect(find.byType(DebugPluginDev), findsOneWidget);
          expect(find.text('Failed to load'), findsOneWidget);
          await expectGuidelines(tester);

          await tester.tap(find.text('Record').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Replay').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Run all').first);
          await settleCases(tester, h);
          await tester.tap(find.text('search').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('resolveStream').first);
          await tester.pumpAndSettle();
          expect(find.text('Return value'), findsOneWidget);
          await expectGuidelines(tester);

          await tester.tap(find.text('Record').first);
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Recording uses the real network'),
            findsOneWidget,
          );
          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the Debug Database section at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = await openDebugSection(tester, 'Database');
          expect(find.byType(DebugDatabase), findsOneWidget);
          // 表清單。
          await expectGuidelines(tester);

          // 一張有列的表（要有東西才看得到表格）。
          await tester.runAsync(
            () =>
                TracksRepository(
                  h.container(tester).read(appDatabaseProvider),
                ).upsert([
                  const TrackInfo(
                    sourceTypeId: 'fmp-test',
                    sourceId: 'a',
                    title:
                        'A song with a title long enough to need truncating '
                        'when the cell is narrow',
                  ),
                ]),
          );
          await tester.tap(find.text('tracks'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          await expectGuidelines(tester);

          // 檢查結果（表的列頁還開著）。
          await tester.tap(find.text('Check'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          expect(find.text('No problems found'), findsOneWidget);
          await expectGuidelines(tester);
          handle.dispose();
        });
      }

      // 錯誤詳細頁（M3 PR 13）：欄位與按鈕，以及第一次回報前的提醒對話框。
      for (final size in const [Size(400, 800), Size(1000, 700)]) {
        testWidgets('the error detail page at ${size.width}', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(
            urlOpener: FakeUrlOpener(),
            redactor: Redactor(),
          );
          final record = h.log.report(
            'Search failed',
            ParseError(
              pluginId: 'alpha',
              cause: StateError('bad payload'),
              stackTrace: StackTrace.fromString(
                '#0      parse (package:alpha/x.js:1)',
              ),
            ),
            tag: 'search',
          )!;
          await h.pumpApp(
            tester,
            ErrorDetailPage(record: record),
            size: size,
            brightness: brightness,
          );
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          expect(find.byType(ErrorDetailPage), findsOneWidget);
          await expectGuidelines(tester);

          await tester.tap(find.text('Report on GitHub'));
          await h.loadSettings(tester);
          await tester.pumpAndSettle();
          expect(find.text('Check before you submit'), findsOneWidget);
          await expectGuidelines(tester);
          handle.dispose();
        });
      }

      // 插件頁（M3 PR 5）：已安裝（停用、有更新、展開詳細資料）、可安裝、安裝的確認框
      // （兩則警告）。
      for (final size in const [Size(400, 800), Size(1000, 700)]) {
        final width = size.width;

        Future<PluginPageHarness> openPlugins(WidgetTester tester) async {
          final alpha = pluginScript(
            'plugin-a',
            name: 'Alpha',
            capabilities: ['search', 'resolveStream'],
            description: 'Plays Alpha songs',
          );
          final h = await PluginPageHarness.create(
            tester,
            dialogs: FakeFileDialogs(
              PickedFile(
                name: 'gamma.js',
                bytes: Uint8List.fromList(
                  utf8.encode(pluginScript('plugin-c', name: 'Gamma')),
                ),
              ),
            ),
          );
          h.publish([
            pluginScript('plugin-a', name: 'Alpha', version: '1.1.0'),
            pluginScript('plugin-b', name: 'Beta'),
            pluginScript('plugin-d', name: 'Delta'),
          ]);
          await tester.runAsync(() async {
            await h.install(alpha, indexUrl: officialPluginIndexUrl);
            await h.install(
              pluginScript('plugin-b', name: 'Beta'),
              enabled: false,
            );
          });
          await h.shell.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.settle(tester);
          await tester.tap(find.text('Plugins'));
          await h.settle(tester);
          await tester.pumpAndSettle();
          return h;
        }

        testWidgets('the installed plugins at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openPlugins(tester);
          await tester.tap(find.text('Details').first);
          await tester.pumpAndSettle();
          expect(find.text('Update available'), findsOneWidget);
          expect(find.text('Disabled'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the available plugins at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = await openPlugins(tester);
          await tester.tap(find.text('Available'));
          await tester.pumpAndSettle();
          await h.settle(tester);
          expect(find.text('Delta'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 開發中的插件（M3 PR 16b）：標記、停用的動作與說明。
        testWidgets('the installed plugins in development at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final folder = tempFolder();
          final directory = Directory(p.join(folder.path, 'alpha'))
            ..createSync();
          File(p.join(directory.path, 'alpha.js')).writeAsStringSync(
            pluginScript(
              'plugin-a',
              name: 'Alpha Dev',
              version: '1.2.0',
              capabilities: ['search', 'resolveStream'],
            ),
          );
          final h = await PluginPageHarness.create(
            tester,
            pluginDevTools: true,
          );
          await tester.runAsync(() async {
            await h.install(
              pluginScript(
                'plugin-a',
                name: 'Alpha',
                capabilities: ['search', 'resolveStream'],
              ),
              indexUrl: officialPluginIndexUrl,
            );
            await DeveloperSettingsRepository(h.plugins.database)
                .write(developerMode: true, pluginDevFolder: folder.path);
          });
          await h.shell.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.settle(tester);
          await tester.tap(find.text('Plugins'));
          await h.settle(tester);
          for (var i = 0; i < 400; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await tester.pump(const Duration(milliseconds: 25));
            final state = h.container(tester).read(pluginDevelopmentProvider);
            if (state != null && !state.busy) break;
          }
          await tester.pumpAndSettle();
          expect(find.text('In development'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the install confirmation at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = await openPlugins(tester);
          await tester.tap(find.byTooltip('More options'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Install from file'));
          await h.settle(tester);
          await tester.pumpAndSettle();
          expect(find.text('Install Gamma?'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });
      }

      // M4 PR 13–15 的畫面：帳號歌單頁、帳號卡的「⋯」選單、加入／移除遠端歌單的對話框。
      for (final size in const [Size(400, 800), Size(1000, 700)]) {
        final width = size.width;

        // 帳號卡：真的腳本插件（QuickJS）、已登入；[rooms] 給了就匯出 `libraryLiveRooms`，
        // [imported] 時先匯入一張歌單（帳號歌單頁的「已匯入」列）。
        Future<PluginPageHarness> openAccountCard(
          WidgetTester tester, {
          bool rooms = false,
          bool imported = false,
        }) async {
          const id = 'plugin-l';
          final h = await PluginPageHarness.create(tester);
          await tester.runAsync(
            () => h.install(
              pluginSource(
                '''
export function search() { return { items: [], hasMore: false }; }
export function loginVerify() { return { userId: 'u', displayName: 'Someone' }; }
export function liveSearch() { return { items: [], hasMore: false }; }
export function liveRoomFromUrl() { return null; }
export function liveStatus() { throw { fmpError: 'NotFound' }; }
export function resolveLive() { return { candidates: [] }; }
export function playlistFromUrl() { return null; }
export function importPlaylist(query) {
  return { playlist: { title: 'Remote' }, items: [], cursor: null, total: 0 };
}
export function libraryPlaylists(query) {
  return { playlists: [
    { playlistId: 'a', title: 'Road trip', trackCount: 3, writable: true },
    { playlistId: 'old', title: 'Already here', trackCount: 5, writable: false },
  ], cursor: null };
}
${rooms ? 'export function libraryLiveRooms() { return { rooms: [] }; }' : ''}
''',
                id: id,
                capabilities: [
                  'search',
                  'live',
                  'libraryRead',
                  'login',
                  'importPlaylist',
                ],
                login: '{"methods": ["cookie"]}',
              ),
            ),
          );
          if (imported) {
            await tester.runAsync(
              () => PlaylistRepository(h.plugins.database).createImported(
                pluginId: id,
                remoteId: 'old',
                info: const RemotePlaylistInfo(name: 'Imported earlier'),
              ),
            );
          }
          // 憑證的存取在假時間 zone 裡跑（見 PluginPageHarness.create）。
          unawaited(
            h.plugins.credentials.save(
              Account(
                pluginId: id,
                userId: 'u',
                displayName: 'Someone',
                status: AccountStatus.active,
                loggedInAt: DateTime.utc(2026, 10, 20),
              ),
              const LoginCredentials(cookies: {'SESSDATA': 'FAKE_SESSDATA'}),
            ),
          );
          await tester.pump();
          await h.shell.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.settle(tester);
          // 窄版先是分組清單。
          if (find.text('Plugin plugin-l').evaluate().isEmpty) {
            await tester.tap(find.text('Accounts'));
            await h.settle(tester);
          }
          await tester.pumpAndSettle();
          expect(find.text('Plugin plugin-l'), findsOneWidget);
          return h;
        }

        testWidgets('the account playlists page at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = await openAccountCard(tester, imported: true);
          await tester.tap(
            find.ancestor(
              of: find.text('Playlists'),
              matching: find.bySubtype<ButtonStyleButton>(),
            ),
          );
          await h.settle(tester);
          await h.settle(tester);
          await tester.pump(const Duration(seconds: 1));
          expect(find.text('Road trip'), findsOneWidget);
          expect(find.text('Already here'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the account card menu at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openAccountCard(tester, rooms: true);
          await tester.tap(
            find.descendant(
              of: find.ancestor(
                of: find.text('Plugin plugin-l'),
                matching: find.byType(Card),
              ),
              matching: find.byTooltip('More options'),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Import live rooms from account'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 加入／移除遠端歌單：插件現在能寫遠端（以 override 決定）。
        ShellHarness remoteHarness() => ShellHarness(
          libraryRead: true,
          libraryWrite: true,
          registryOfSources: true,
          extraOverrides: [
            remoteWritablePluginsProvider.overrideWithValue(const {'fmp-test'}),
          ],
        );

        Future<void> openSongMenuItem(WidgetTester tester, String item) async {
          await tester.tap(
            find
                .descendant(
                  of: find.widgetWithText(ListTile, 'Song a'),
                  matching: find.byTooltip('More options'),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(MenuItemButton, item));
          await tester.pump();
          await tester.pump();
          await tester.pumpAndSettle();
        }

        testWidgets('the add to remote playlist dialog at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final h = remoteHarness();
          h.plugin.onLibraryPlaylists = (query) => const LibraryPlaylistPage(
            playlists: [
              LibraryPlaylist(
                playlistId: 'p1',
                title: 'Road trip',
                writable: true,
                trackCount: 3,
              ),
              LibraryPlaylist(
                playlistId: 'p2',
                title: 'Study',
                writable: true,
                trackCount: 1,
              ),
              LibraryPlaylist(
                playlistId: 'p3',
                title: 'Late night',
                writable: true,
              ),
            ],
          );
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.enterText(find.byType(TextField), 'song');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pump();
          await tester.pump();
          await openSongMenuItem(tester, 'Add to remote playlist…');
          await tester.tap(find.widgetWithText(CheckboxListTile, 'Road trip'));
          // 輸入框沒有焦點：游標閃爍會讓對比度的取樣時好時壞。
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          expect(find.text('Add to remote playlist'), findsOneWidget);
          expect(find.text('Study'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the remove from remote playlist confirmation at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final h = remoteHarness();
          await h.pumpShell(
            tester,
            size: size,
            brightness: brightness,
            at: ShellDestination.library,
          );
          await tester.runAsync(() async {
            final container = h.container(tester);
            final repository = container.read(playlistRepositoryProvider);
            final id = (await repository.createImported(
              pluginId: 'fmp-test',
              remoteId: 'r1',
              info: const RemotePlaylistInfo(name: 'Road'),
            ))!;
            final track = summary('a').toTrackInfo();
            await repository.addTracks(id, [track]);
            await repository.setWritable(id, writable: true);
            await container.read(appDatabaseProvider).customStatement(
              'UPDATE playlist_entries SET remote_item_id = ? '
              'WHERE track_key = ?',
              ['ra', '${track.key}'],
            );
          });
          for (var i = 0; i < 3; i++) {
            await h.loadSettings(tester);
          }
          await tester.pumpAndSettle();
          await tester.tap(find.text('Road'));
          for (var i = 0; i < 3; i++) {
            await h.loadSettings(tester);
          }
          await tester.pumpAndSettle();
          await openSongMenuItem(tester, 'Remove from the remote playlist');
          expect(find.text('Remove from the remote playlist?'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });
      }

      // 帳號（M3 PR 8）：未登入（測試插件，QR 與貼上 cookie）、已登入、已失效（自動化說明）
      // 三張卡，QR 登入與貼上 cookie 的對話框，網頁登入卡住時的頁面（PR 9）。
      for (final size in const [Size(400, 800), Size(1000, 700)]) {
        final width = size.width;

        Future<PluginPageHarness> openAccounts(WidgetTester tester) async {
          final h = await PluginPageHarness.create(tester);
          await tester.runAsync(() async {
            await h.install(testPluginFile.readAsStringSync());
            for (final (id, name, risk) in [
              ('plugin-a', 'Alpha', true),
              ('plugin-b', 'Beta', false),
            ]) {
              await h.install(
                pluginScript(
                  id,
                  name: name,
                  login: {
                    'methods': ['qr'],
                    'automationRisk': risk,
                  },
                ),
              );
            }
          });
          // 憑證的存取在假時間 zone 裡跑（見 PluginPageHarness.create）。
          for (final (id, status) in [
            ('plugin-a', AccountStatus.invalidated),
            ('plugin-b', AccountStatus.active),
          ]) {
            unawaited(
              h.plugins.credentials.save(
                Account(
                  pluginId: id,
                  userId: 'u',
                  displayName: 'Someone',
                  status: status,
                  loggedInAt: DateTime.utc(2026, 10, 9),
                ),
                const LoginCredentials(cookies: {'SESSDATA': 'FAKE_SESSDATA'}),
              ),
            );
            await tester.pump();
          }
          await h.shell.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.settle(tester);
          // 窄版（含 1000 寬時右側面板占掉的內容區）先是分組清單。
          if (find.text('Expired').evaluate().isEmpty) {
            await tester.tap(find.text('Accounts'));
            await h.settle(tester);
          }
          await tester.pumpAndSettle();
          expect(find.text('Expired'), findsOneWidget);
          return h;
        }

        testWidgets('the accounts at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openAccounts(tester);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the QR login at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = await openAccounts(tester);
          await tester.tap(find.text('Sign in with QR code'));
          await h.settle(tester);
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            find.text('Scan the QR code with the app on your phone'),
            findsOneWidget,
          );

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the cookie login at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = await openAccounts(tester);
          await tester.tap(find.text('Paste cookies'));
          await h.settle(tester);
          await tester.pumpAndSettle();
          expect(find.text('How to get them'), findsOneWidget);
          // 帶著錯誤訊息的樣子（錯誤色的字也要過對比度）。
          await tester.enterText(find.byType(TextField), 'not a cookie');
          await tester.tap(find.text('Sign in'));
          await tester.pumpAndSettle();
          expect(find.textContaining('No cookies found'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 網頁登入（M3 PR 9）：卡住時 WebView 上方的警告條（假的 WebView 是一塊空白）。
        testWidgets('the web login at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final webView = FakeLoginWebView();
          final h = await PluginPageHarness.create(
            tester,
            loginWebView: webView,
          );
          await tester.runAsync(
            () => h.install(
              pluginScript(
                'plugin-w',
                name: 'Web',
                login: {
                  'methods': ['webView'],
                  'webView': {
                    'url': 'https://accounts.example.test/login',
                    'cookieHosts': ['https://www.example.test'],
                    'doneCookies': ['SID'],
                  },
                },
              ),
            ),
          );
          await h.shell.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.settle(tester);
          if (find.text('Sign in on the web').evaluate().isEmpty) {
            await tester.tap(find.text('Accounts'));
            await h.settle(tester);
          }
          await tester.tap(find.text('Sign in on the web'));
          await h.settle(tester);
          await tester.pump(const Duration(milliseconds: 500));
          webView
            ..setCookies(Uri.parse('https://accounts.example.test'), {
              'SID': 'FAKE_PAGE_SID',
            })
            ..loadPage();
          await tester.pump();
          await tester.pump(webLoginStuckAfter);
          expect(find.text("The sign-in didn't finish"), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });
      }

      // 首次啟動引導（M3 PR 6）：搜尋頁的插件清單（一個已裝、一個要更新 FMP）與一次確認
      // 的對話框。
      for (final size in const [Size(400, 800), Size(1000, 700)]) {
        final width = size.width;

        Future<PluginPageHarness> openOnboarding(WidgetTester tester) async {
          final h = await PluginPageHarness.create(
            tester,
            registrySources: true,
          );
          h.publish(
            [
              pluginScript('plugin-a', name: 'Alpha', description: 'Search'),
              pluginScript('plugin-b', name: 'Beta'),
              pluginScript('plugin-d', name: 'Delta'),
            ],
            apiVersions: {'plugin-d': 2},
          );
          await tester.runAsync(
            () => h.install(
              pluginScript('plugin-b', name: 'Beta'),
              enabled: false,
            ),
          );
          await h.shell.pumpShell(tester, size: size, brightness: brightness);
          await h.settle(tester);
          expect(
            find.text('Install plugins to start searching'),
            findsOneWidget,
          );
          return h;
        }

        testWidgets('the onboarding at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await openOnboarding(tester);

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('the onboarding confirmation at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = await openOnboarding(tester);
          await tester.tap(find.widgetWithText(FilledButton, 'Install'));
          await h.settle(tester);
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('Install these plugins?'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });
      }

      // 右側「正在播放」面板（M2 PR 19）：有歌、1000 與 1800 寬；面板裡的詳細資料、
      // 收起鈕與拖曳把手。
      for (final width in const [1000.0, 1800.0]) {
        testWidgets('the now playing panel at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(artworkManager: FakeArtworkManager());
          await h.pumpShell(
            tester,
            size: Size(width, 800),
            brightness: brightness,
          );
          await h.play(tester, [summary('a')]);
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(NowPlayingPanel), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });
      }

      // 播放列的音量與輸出裝置（design §9.2）：expanded 的靜音鈕與滑桿、輸出裝置鈕，
      // medium 的音量圖示開出的彈出式滑桿。
      for (final (name, size) in const [
        ('expanded', Size(1000, 700)),
        ('medium', Size(800, 700)),
      ]) {
        testWidgets('the player bar volume and output device, $name', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(
            outputDeviceSelection: true,
            outputDevices: FakeOutputDevices(const [
              OutputDevice(id: 'wasapi/{a}', name: 'Speakers'),
            ]),
          );
          await h.pumpShell(tester, size: size, brightness: brightness);
          await h.play(tester, [summary('a')]);
          await tester.pump(const Duration(milliseconds: 200));
          if (name == 'medium') {
            await tester.tap(find.byTooltip('Volume (Ctrl+↑/↓)'));
            await tester.pump();
            expect(find.byTooltip('Mute'), findsOneWidget);
          }

          await expectGuidelines(tester);
          handle.dispose();
        });
      }

      // 播放頁（design §9.3）：毛玻璃疊在模糊的封面上，最淺與最深的封面各驗一次對比度。
      // 三種版面各一個寬度：手機、兩欄、三欄；沒有封面時是實色背景。
      for (final size in const [
        Size(400, 800),
        Size(1000, 700),
        Size(1800, 900),
      ]) {
        for (final artwork in [null, ...TestArtwork.values]) {
          testWidgets(
            'the player page over ${artwork?.name ?? 'no'} artwork at '
            '${size.width}',
            (tester) async {
              final handle = tester.ensureSemantics();
              final h = ShellHarness(artworkManager: FakeArtworkManager());
              await h.pumpShell(tester, size: size, brightness: brightness);
              await h.play(tester, [
                summary('a', artwork: artwork?.artwork ?? const []),
                summary('b'),
              ]);
              await tester.pump(const Duration(milliseconds: 200));
              await tester.tap(
                find
                    .descendant(
                      of: find.byKey(PlayerBar.titleKey),
                      matching: find.byType(Text),
                    )
                    .first,
              );
              await tester.pumpAndSettle();
              // 封面的解碼是真的非同步工作。
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 100)),
              );
              await tester.pumpAndSettle();
              expect(find.byType(PlayerPage), findsOneWidget);

              await expectGuidelines(tester);
              handle.dispose();
            },
          );
        }
      }

      // 佇列（M2 PR 18b）：寬版是播放頁的佇列分頁，手機是底部面板；隨機開著、標題列的
      // 說明在。
      for (final size in const [Size(400, 800), Size(1000, 700)]) {
        testWidgets('the queue at ${size.width}, shuffle on', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(artworkManager: FakeArtworkManager());
          await h.pumpShell(tester, size: size, brightness: brightness);
          await h.play(tester, [
            for (final id in 'abcd'.split('')) summary(id),
          ]);
          h.controller.setShuffle(true);
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(
            find
                .descendant(
                  of: find.byKey(PlayerBar.titleKey),
                  matching: find.byType(Text),
                )
                .first,
          );
          await tester.pumpAndSettle();
          if (size.width < 840) {
            await tester.tap(find.byKey(PlayerPage.queueKey));
          } else {
            await tester.tap(find.widgetWithText(Tab, 'Queue'));
          }
          await tester.pumpAndSettle();
          expect(find.byType(QueueView), findsOneWidget);
          expect(find.textContaining('shuffle order'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // 分 P 曲目的佇列（M3 PR 20）：顯示「影片標題 · P2 分 P 標題」。
        testWidgets('the queue with multi-part tracks at ${size.width}', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(artworkManager: FakeArtworkManager());
          await h.pumpShell(tester, size: size, brightness: brightness);
          expect(
            h.controller.addToQueue([
              for (var i = 1; i <= 3; i++)
                TrackInfo(
                  sourceTypeId: 'fmp-test',
                  sourceId: 'v',
                  cid: i,
                  title: 'Part $i',
                  uploader: 'Uploader',
                  partIndex: i,
                  parentTitle: 'The video',
                ),
            ]),
            isTrue,
          );
          unawaited(h.controller.jumpTo(0));
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(
            find
                .descendant(
                  of: find.byKey(PlayerBar.titleKey),
                  matching: find.byType(Text),
                )
                .first,
          );
          await tester.pumpAndSettle();
          if (size.width < 840) {
            await tester.tap(find.byKey(PlayerPage.queueKey));
          } else {
            await tester.tap(find.widgetWithText(Tab, 'Queue'));
          }
          await tester.pumpAndSettle();
          expect(find.byType(QueueView), findsOneWidget);
          expect(find.text('The video · P2 Part 2'), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });

        // Mix 的佇列（M3 PR 19）：標題列說這是哪個 Mix，隨機鈕停用並附說明。
        testWidgets('the queue of a mix at ${size.width}', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness(
            mix: true,
            registryOfSources: true,
            artworkManager: FakeArtworkManager(),
          );
          h.plugin.onMix = (query) => MixBatch(
            mixId: 'm1',
            title: 'Late night mix',
            tracks: [for (final id in 'abcd'.split('')) summary(id)],
            cursor: 'c2',
          );
          await h.pumpShell(tester, size: size, brightness: brightness);
          unawaited(h.controller.startMix(summary('seed').toTrackInfo()));
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(
            find
                .descendant(
                  of: find.byKey(PlayerBar.titleKey),
                  matching: find.byType(Text),
                )
                .first,
          );
          await tester.pumpAndSettle();
          if (size.width < 840) {
            await tester.tap(find.byKey(PlayerPage.queueKey));
          } else {
            await tester.tap(find.widgetWithText(Tab, 'Queue'));
          }
          await tester.pumpAndSettle();
          expect(find.byType(QueueView), findsOneWidget);
          expect(find.byKey(QueueView.mixNoteKey), findsOneWidget);
          expect(find.text('Mix: Late night mix'), findsOneWidget);
          expect(
            find.byTooltip('Shuffle is unavailable in a Mix'),
            findsWidgets,
          );

          await expectGuidelines(tester);
          handle.dispose();
        });
      }
    });
  }
}

List<TrackArtwork> _trackArtwork(TestArtwork artwork) => [
  for (final image in artwork.artwork)
    TrackArtwork(url: image.url, width: image.width),
];

/// 收聽一個直播間（有封面、主播與人數），佇列裡另有一首。
Future<ShellHarness> _listening(
  WidgetTester tester,
  Size size,
  Brightness brightness,
) async {
  final h = ShellHarness(live: true, artworkManager: FakeArtworkManager());
  h.plugin
    ..onResolveLive = ((request) => [candidate('${request.roomId}.flv')])
    ..onLiveStatus = ((query) => LiveRoom(
      roomId: query.roomId,
      title: 'Late night radio',
      hostName: 'Host r',
      status: LiveRoomStatus.live,
      online: 12345,
    ));
  await h.pumpShell(tester, size: size, brightness: brightness);
  await h.play(tester, [summary('a')]);
  await tester.pump(const Duration(milliseconds: 200));
  unawaited(
    h.controller.playLive(
      LiveTarget(
        pluginId: 'fmp-test',
        roomId: 'r',
        title: 'Late night radio',
        hostName: 'Host r',
        artwork: _trackArtwork(TestArtwork.darkest),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await h.liveInfoJob!();
  await tester.pump();
  // 封面的解碼是真的非同步工作。
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump(const Duration(milliseconds: 500));
  return h;
}

const _hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
