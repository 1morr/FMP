import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/temporary_play.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/focus_ring.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/player/player_background.dart';
import 'package:fmp/ui/player/player_controls.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/player/player_queue.dart';
import 'package:fmp/ui/queue/queue_rows.dart';
import 'package:material_ui/material_ui.dart';

/// 全螢幕播放頁（票 16，`docs/design/player.html`）：從迷你播放器或播放膠囊
/// 打開，進度、控制、播放來源、佇列、⋮、安全區、紅綠燈與無障礙。播放與佇列
/// 換成記下呼叫的假的，不聯網（曲目沒有封面網址）。
///
/// 背景色場與等化器一直在動，所以不用 `pumpAndSettle`，改成一段一段 `pump`。
void main() {
  const phone = Size(390, 844);
  const desktop = Size(1280, 800);

  late Directory logDir;
  late Log log;
  late PluginHost host;
  late _FakePlayback playback;
  late _FakeQueue queue;
  late List<MethodCall> windowCalls;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    logDir = Directory.systemTemp.createTempSync('fmp_player_page_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    host = PluginHost(
      bundles: [
        PluginBundle(
          manifest: jsonEncode({
            'id': 'demo',
            'name': 'Demo Source',
            'version': '1.0.0',
            'capabilities': ['search', 'resolveStream'],
            'domains': ['api.example.com'],
            'mark': {
              'short': 'Dm',
              'color': '#FB7299',
              'paths': [
                {'pathData': 'M1 1h14v14H1z', 'fillColor': '#FB7299'},
              ],
            },
          }),
          code: '',
        ),
      ],
      log: log,
    );
  });
  tearDown(() async {
    LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale);
    await host.close();
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  /// 封面載入器被要過的網址。
  final requestedCovers = <String>[];

  /// 第 [n] 首（從 1 數）：四分零九秒，有網址。[covers] 時有縮圖與大封面。
  Track song(int n, {bool url = true, bool covers = false}) => Track(
    ref: TrackRef(pluginId: 'demo', trackId: 's$n'),
    title: 'Song $n',
    author: 'Artist $n',
    duration: const Duration(minutes: 4, seconds: 9),
    url: url ? 'https://example.com/v/$n' : null,
    coverUrl: covers ? 'https://example.com/c/$n/small' : null,
    coverLargeUrl: covers ? 'https://example.com/c/$n/large' : null,
  );

  /// 照稿：64 首、正在播第 6 首、不循環。
  Queue queueOf({int current = 6, int count = 64}) => Queue.empty
      .add([for (var i = 1; i <= count; i++) song(i)])
      .jumpTo(current - 1);

  PlaybackState playing(Track track) => PlaybackState(
    track: track,
    status: PlaybackStatus.playing,
    position: const Duration(minutes: 1, seconds: 36),
    duration: track.duration,
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 在 [platform]、[size] 的視窗裡打開 App（首頁、有目前曲目），跑 [body]。
  /// 平台要在測試結束前設回去，不然框架的檢查會擋。
  void playerTest(
    String name,
    Future<void> Function(WidgetTester tester) body, {
    Size size = phone,
    TargetPlatform platform = TargetPlatform.iOS,
    bool reduceMotion = false,
    Queue? initialQueue,
    PlaybackState? initial,
    TemporaryPlay? temporary,
    EdgeInsets padding = EdgeInsets.zero,
    bool semantics = false,
  }) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final handle = semantics ? tester.ensureSemantics() : null;
      try {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1
          ..padding = FakeViewPadding(top: padding.top, bottom: padding.bottom)
          ..viewPadding = FakeViewPadding(
            top: padding.top,
            bottom: padding.bottom,
          );
        addTearDown(tester.view.reset);
        if (reduceMotion) {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(disableAnimations: true);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
        }
        windowCalls = [];
        const channel = MethodChannel('fmp/window');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              windowCalls.add(call);
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        requestedCovers.clear();
        final q = initialQueue ?? queueOf();
        playback = _FakePlayback(initial ?? playing(q.current!.track));
        queue = _FakeQueue(q);
        await tester.pumpWidget(
          buildRoot(
            overrides: [
              pluginHostProvider.overrideWith((_) => host),
              playbackProvider.overrideWith(() => playback),
              queueProvider.overrideWith(() => queue),
              temporaryPlayProvider.overrideWith(
                () => _FixedTemporary(temporary),
              ),
              coverImageLoaderProvider.overrideWithValue((url) {
                requestedCovers.add(url);
                return MemoryImage(_transparentPng);
              }),
            ],
          ),
        );
        await settle(tester);
        await body(tester);
      } finally {
        handle?.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  /// 手機從迷你播放器、桌面從播放膠囊打開播放頁。
  Future<void> openPlayer(WidgetTester tester, {bool desktop = false}) async {
    await tester.tap(
      find.byKey(Key(desktop ? 'transport-open' : 'mini-player')),
    );
    await settle(tester);
    expect(find.byType(PlayerPage), findsOneWidget);
  }

  Future<void> closeByButton(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player-collapse')));
    await settle(tester);
  }

  /// 條在畫面上的範圍（點擊區）。
  Rect barRect(WidgetTester tester) => tester.getRect(
    find.descendant(
      of: find.byType(PlayerProgress),
      matching: find.byType(GestureDetector),
    ),
  );

  group('opening and closing', () {
    playerTest('phone: the mini player opens the player on the cover pane, '
        'the collapse button closes it', (tester) async {
      final semantics = tester.ensureSemantics();
      await openPlayer(tester);

      // 打開在封面：封面那頁在畫面上、佇列那頁沒有。
      expect(find.byType(PlayerCover), findsOneWidget);
      expect(find.byType(PlayerQueue), findsNothing);
      expect(
        tester.getSemantics(find.byKey(const Key('player-dot-cover'))),
        isSemantics(label: '畫面：封面，第 2 頁，共 2 頁', isSelected: true),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('player-dot-queue'))),
        isSemantics(isSelected: false),
      );

      await closeByButton(tester);
      expect(find.byType(PlayerPage), findsNothing);
      semantics.dispose();
    });

    playerTest(
      'desktop: the capsule opens the player, Esc closes it',
      (tester) async {
        await openPlayer(tester, desktop: true);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(find.byType(PlayerPage), findsNothing);
        expect(find.byKey(const Key('transport-open')), findsOneWidget);
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );

    playerTest('the player closes when playback ends while it is open', (
      tester,
    ) async {
      await openPlayer(tester);

      playback.clear();
      await settle(tester);

      expect(find.byType(PlayerPage), findsNothing);
    });
  });

  group('progress', () {
    playerTest('tapping the bar seeks to that fraction of the duration', (
      tester,
    ) async {
      await openPlayer(tester);

      final bar = barRect(tester);
      await tester.tapAt(Offset(bar.left + bar.width * .25, bar.top + 22));
      await tester.pump();

      expect(playback.seeks, [const Duration(microseconds: 62250000)]);
    });

    playerTest('dragging shows the time under the finger and seeks once, on '
        'release', (tester) async {
      await openPlayer(tester);
      expect(find.text('1:36'), findsOneWidget);

      final bar = barRect(tester);
      final gesture = await tester.startGesture(
        Offset(bar.left + bar.width * .25, bar.top + 22),
      );
      await gesture.moveBy(Offset(bar.width * .125, 0));
      await gesture.moveBy(Offset(bar.width * .125, 0));
      await tester.pump();

      // 拖到一半：時間是 2:04（249 秒的一半），還沒有 seek。
      expect(
        find.text(formatDuration(const Duration(milliseconds: 124500))),
        findsOneWidget,
      );
      expect(find.text('1:36'), findsNothing);
      expect(playback.seeks, isEmpty);

      await gesture.up();
      await tester.pump();
      expect(playback.seeks, [const Duration(milliseconds: 124500)]);
    });
  });

  group('controls', () {
    playerTest('previous and next call the queue', (tester) async {
      await openPlayer(tester);

      await tester.tap(find.byKey(const Key('player-previous')));
      await tester.tap(find.byKey(const Key('player-next')));

      expect(queue.calls, ['previous', 'next']);
    });

    playerTest('previous does nothing on the first track with repeat off', (
      tester,
    ) async {
      await openPlayer(tester);

      await tester.tap(
        find.byKey(const Key('player-previous')),
        warnIfMissed: false,
      );
      expect(queue.calls, isEmpty);

      await tester.tap(find.byKey(const Key('player-next')));
      expect(queue.calls, ['next']);
    }, initialQueue: queueOf(current: 1));

    playerTest('next does nothing on the last track with repeat off', (
      tester,
    ) async {
      await openPlayer(tester);

      await tester.tap(
        find.byKey(const Key('player-next')),
        warnIfMissed: false,
      );
      expect(queue.calls, isEmpty);
    }, initialQueue: queueOf(current: 64));

    playerTest('shuffle and repeat toggle, and read as toggled when on', (
      tester,
    ) async {
      await openPlayer(tester);
      Finder button(String key) => find.byKey(Key(key));
      expect(
        tester.getSemantics(button('player-shuffle')),
        isSemantics(hasToggledState: true, isToggled: false),
      );
      expect(
        tester.getSemantics(button('player-repeat')),
        isSemantics(hasToggledState: true, isToggled: false),
      );

      await tester.tap(button('player-shuffle'));
      await tester.pump();
      expect(queue.calls, ['toggleShuffle']);
      expect(
        tester.getSemantics(button('player-shuffle')),
        isSemantics(hasToggledState: true, isToggled: true),
      );

      await tester.tap(button('player-repeat'));
      await tester.pump();
      expect(queue.calls, ['toggleShuffle', 'cycleRepeat']);
      expect(
        tester.getSemantics(button('player-repeat')),
        isSemantics(hasToggledState: true, isToggled: true),
      );
    }, semantics: true);
  });

  group('context line', () {
    playerTest('queue mode shows the position and the next track', (
      tester,
    ) async {
      await openPlayer(tester);

      expect(find.text('佇列 · 第 6 / 64 首'), findsOneWidget);
      expect(find.text('下一首：Song 7'), findsOneWidget);
    });

    final from = queueOf();
    const other = Track(
      ref: TrackRef(pluginId: 'demo', trackId: 'tmp'),
      title: 'Temp song',
      author: 'Someone',
      duration: Duration(minutes: 2),
      url: 'https://example.com/v/tmp',
    );
    playerTest(
      'temporary play shows 臨時播放 and where it returns to',
      (tester) async {
        await openPlayer(tester);

        expect(find.text('臨時播放'), findsOneWidget);
        expect(find.text('播完回到佇列第 6 首'), findsOneWidget);
        expect(find.text('佇列 · 第 6 / 64 首'), findsNothing);
      },
      initialQueue: from,
      initial: playing(other),
      temporary: TemporaryPlay.start(
        [other],
        previous: null,
        leaving: from.current,
        position: Duration.zero,
      ),
    );
  });

  group('queue', () {
    playerTest('phone: the queue dot shows the upcoming tracks and a row '
        'plays from there', (tester) async {
      await openPlayer(tester);

      await tester.tap(find.byKey(const Key('player-dot-queue')));
      await settle(tester);

      expect(find.byType(PlayerQueue), findsOneWidget);
      expect(find.text('Song 7'), findsOneWidget);
      expect(find.text('Song 8'), findsOneWidget);
      // 播過的與正在播的不在「接下來」裡（正在播的在上面的小卡）。
      expect(find.text('Song 5'), findsNothing);

      await tester.tap(find.text('Song 8'));
      await tester.pump();
      // 目前第 6 首（index 5）：接下來的第 2 列（i = 1）是 index 7。
      expect(queue.calls, ['playAt 7']);
    });

    playerTest(
      'desktop: the queue toggle hides and shows the right column',
      (tester) async {
        await openPlayer(tester, desktop: true);
        expect(find.byType(PlayerQueue), findsOneWidget);

        await tester.tap(find.byKey(const Key('player-queue-toggle')));
        await settle(tester);
        expect(find.byType(PlayerQueue), findsNothing);

        await tester.tap(find.byKey(const Key('player-queue-toggle')));
        await settle(tester);
        expect(find.byType(PlayerQueue), findsOneWidget);
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );
  });

  group('more menu', () {
    for (final (name, size, platform) in [
      ('phone', phone, TargetPlatform.iOS),
      ('desktop', desktop, TargetPlatform.macOS),
    ]) {
      playerTest(
        '$name: ⋮ lists only copy link and open in browser',
        (tester) async {
          await openPlayer(tester, desktop: size == desktop);

          await tester.tap(find.byKey(const Key('player-more')));
          await settle(tester);

          expect(find.text('複製連結'), findsOneWidget);
          expect(find.text('在瀏覽器開啟'), findsOneWidget);
          expect(find.text('下一首播放'), findsNothing);
          expect(find.text('加入佇列'), findsNothing);
        },
        size: size,
        platform: platform,
      );
    }

    playerTest('a track without a url has no ⋮', (tester) async {
      await openPlayer(tester);

      expect(find.byKey(const Key('player-collapse')), findsOneWidget);
      expect(find.byKey(const Key('player-more')), findsNothing);
    }, initial: playing(song(6, url: false)));
  });

  group('review follow-ups', () {
    playerTest(
      'the player shows the large cover and takes its colours from it',
      (tester) async {
        await openPlayer(tester);

        expect(requestedCovers, contains('https://example.com/c/6/large'));
        final big = tester.widgetList<Cover>(
          find.descendant(
            of: find.byType(PlayerCover),
            matching: find.byType(Cover),
          ),
        );
        expect(big.single.url, 'https://example.com/c/6/large');
      },
      initial: playing(song(6, covers: true)),
    );

    playerTest(
      'the queue toggle stays off after closing and reopening',
      (tester) async {
        await openPlayer(tester, desktop: true);
        await tester.tap(find.byKey(const Key('player-queue-toggle')));
        await settle(tester);
        expect(find.byType(PlayerQueue), findsNothing);

        await closeByButton(tester);
        await openPlayer(tester, desktop: true);
        expect(find.byType(PlayerQueue), findsNothing);
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );

    playerTest('pulling the cover pane down closes the player', (tester) async {
      await openPlayer(tester);
      await tester.drag(find.byType(PlayerCover), const Offset(0, 300));
      await settle(tester);

      expect(find.byType(PlayerPage), findsNothing);
    });

    playerTest('a short pull springs back and keeps the player open', (
      tester,
    ) async {
      await openPlayer(tester);
      await tester.timedDrag(
        find.byType(PlayerCover),
        const Offset(0, 60),
        const Duration(seconds: 1),
      );
      await settle(tester);

      expect(find.byType(PlayerPage), findsOneWidget);
    });

    playerTest('dragging an upcoming row by its handle reorders the queue', (
      tester,
    ) async {
      await openPlayer(tester);
      await tester.tap(find.byKey(const Key('player-dot-queue')));
      await settle(tester);
      final handle = find.descendant(
        of: find.byType(PlayerQueue),
        matching: find.byType(QueueDragHandle),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle.first));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await settle(tester);

      // 第 7 首（接下來的第一首）拖過兩列，排到第 9 首的位置。
      expect(queue.calls, contains('move 6 8'));
    }, semantics: true);

    playerTest('copying the link shows the toast on the player', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await openPlayer(tester);
      await tester.tap(find.byKey(const Key('player-more')));
      await settle(tester);
      await tester.tap(find.text(t.search.actions.copyLink));
      await settle(tester);

      expect(find.byType(PlayerPage), findsOneWidget);
      expect(find.text(t.search.actions.linkCopied), findsOneWidget);
    });
  });

  group('safe area', () {
    playerTest('the status bar icons turn light over the cover field', (
      tester,
    ) async {
      await openPlayer(tester);

      expect(
        SystemChrome.latestStyle?.statusBarIconBrightness,
        Brightness.light,
      );
    }, padding: const EdgeInsets.only(top: 59, bottom: 34));

    playerTest(
      'the background fills the screen while the controls stay inside the '
      'safe area',
      (tester) async {
        await openPlayer(tester);

        expect(
          tester.getRect(find.byType(PlayerBackground)),
          const Rect.fromLTWH(0, 0, 390, 844),
        );
        expect(
          tester.getTopLeft(find.byKey(const Key('player-collapse'))).dy,
          greaterThanOrEqualTo(59),
        );
        expect(
          tester.getBottomLeft(find.byKey(const Key('player-dot-cover'))).dy,
          lessThanOrEqualTo(844 - 34),
        );
      },
      padding: const EdgeInsets.only(top: 59, bottom: 34),
    );
  });

  group('macOS traffic lights', () {
    Map<Object?, Object?>? lastSpot() =>
        windowCalls
                .lastWhere((call) => call.method == 'setTrafficLights')
                .arguments
            as Map<Object?, Object?>?;

    playerTest(
      'the player takes the spot at its top left and gives it back on close',
      (tester) async {
        final shell = lastSpot();
        expect(shell, isNotNull);

        await openPlayer(tester, desktop: true);
        expect(lastSpot(), {'x': 14.0, 'y': 18.0, 'minX': 6.0, 'maxX': 86.0});

        await closeByButton(tester);
        expect(lastSpot(), isNotNull);
        expect(lastSpot(), shell);
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );
  });

  group('accessibility', () {
    playerTest(
      'keyboard: Tab shows a focus ring and Enter presses the button',
      (tester) async {
        await openPlayer(tester, desktop: true);
        final visibleRing = find.byWidgetPredicate(
          (w) => w is FocusRing && w.visible,
        );
        expect(visibleRing, findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(visibleRing, findsOneWidget);

        // 往後選到「下一首」，Enter 按下。
        final onNext = find.descendant(
          of: find.byKey(const Key('player-next')),
          matching: visibleRing,
        );
        for (var i = 0; i < 30 && onNext.evaluate().isEmpty; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(onNext, findsOneWidget);
        expect(queue.calls, isEmpty);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(queue.calls, ['next']);
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );

    playerTest(
      'phone: the top buttons, the five controls and the progress bar are at '
      'least 44 x 44',
      (tester) async {
        await openPlayer(tester);

        // 進度條的點擊區：高 44，寬是整條。
        expect(barRect(tester).height, greaterThanOrEqualTo(44));
        expect(barRect(tester).width, greaterThanOrEqualTo(44));
        for (final key in [
          'player-collapse',
          'player-more',
          'player-shuffle',
          'player-previous',
          'player-play',
          'player-next',
          'player-repeat',
        ]) {
          final size = tester.getSize(find.byKey(Key(key)));
          expect(size.width, greaterThanOrEqualTo(44), reason: key);
          expect(size.height, greaterThanOrEqualTo(44), reason: key);
        }
      },
    );

    playerTest('phone: both page dots are at least 44 x 44', (tester) async {
      await openPlayer(tester);

      for (final key in ['player-dot-queue', 'player-dot-cover']) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.width, greaterThanOrEqualTo(44), reason: key);
        expect(size.height, greaterThanOrEqualTo(44), reason: key);
      }
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    }, semantics: true);

    playerTest(
      'reduced motion: the panes cross-fade instead of sliding, and the route '
      'fades in',
      (tester) async {
        await tester.tap(find.byKey(const Key('mini-player')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.ancestor(
            of: find.byType(PlayerPage),
            matching: find.byType(FadeTransition),
          ),
          findsWidgets,
        );
        expect(
          find.ancestor(
            of: find.byType(PlayerPage),
            matching: find.byType(SlideTransition),
          ),
          findsNothing,
        );
        await settle(tester);

        expect(find.byKey(const Key('player-pages')), findsNothing);
        expect(find.byType(PlayerCover), findsOneWidget);

        await tester.tap(find.byKey(const Key('player-dot-queue')));
        await tester.pump(const Duration(milliseconds: 100));
        // 淡入淡出到一半：兩個畫面同時在。
        expect(find.byType(PlayerCover), findsOneWidget);
        expect(find.byType(PlayerQueue), findsOneWidget);
        await settle(tester);
        expect(find.byType(PlayerCover), findsNothing);
        expect(find.byType(PlayerQueue), findsOneWidget);
        expect(find.byKey(const Key('player-panes-fade')), findsOneWidget);
      },
      reduceMotion: true,
    );

    playerTest('with motion on, the route slides up and the panes are a '
        'PageView', (tester) async {
      await tester.tap(find.byKey(const Key('mini-player')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.ancestor(
          of: find.byType(PlayerPage),
          matching: find.byType(SlideTransition),
        ),
        findsWidgets,
      );
      await settle(tester);
      expect(find.byKey(const Key('player-pages')), findsOneWidget);
    });
  });
}

/// 狀態由測試設定的播放；記下 seek 與播放鍵。
class _FakePlayback extends Playback {
  _FakePlayback(this._initial);

  final PlaybackState? _initial;
  final seeks = <Duration>[];
  int playPauses = 0;

  @override
  PlaybackState? build() => _initial;

  void clear() => state = null;

  @override
  Future<void> playPause() async => playPauses++;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  void preloadNext(Track? track) {}
}

/// 佇列由測試給定；記下按了什麼，隨機與循環照真的改佇列。
class _FakeQueue extends QueueController {
  _FakeQueue(this._initial);

  final Queue _initial;
  final calls = <String>[];

  @override
  Queue build() => _initial;

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> previous() async => calls.add('previous');

  @override
  Future<void> playAt(int index) async => calls.add('playAt $index');

  @override
  void move(int from, int to) => calls.add('move $from $to');

  @override
  void toggleShuffle() {
    calls.add('toggleShuffle');
    super.toggleShuffle();
  }

  @override
  void cycleRepeat() {
    calls.add('cycleRepeat');
    super.cycleRepeat();
  }
}

/// 1×1 透明的 PNG：測試不載入真的封面。
final _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==',
);

/// 臨時播放由測試給定。
class _FixedTemporary extends TemporaryPlayHolder {
  _FixedTemporary(this._initial);

  final TemporaryPlay? _initial;

  @override
  TemporaryPlay? build() => _initial;
}
