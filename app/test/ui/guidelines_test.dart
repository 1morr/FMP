import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/endpoints.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/shell/now_playing_panel.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/player/queue_view.dart';
import 'package:fmp/ui/settings/appearance_controls.dart';
import 'package:fmp/ui/settings/network_controls.dart';
import 'package:fmp/ui/settings/playback_controls.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:material_ui/material_ui.dart';

import '../playback/fake_audio_backend.dart';
import '../support/memory_database.dart';
import 'support/fake_artwork.dart';
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
          await tester.tap(find.text('History'));
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
          await tester.tap(find.text('History'));
          await tester.pump();
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
      }
    });
  }
}

const _hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
