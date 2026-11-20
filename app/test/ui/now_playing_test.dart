import 'package:flutter/foundation.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/temporary_play.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/now_playing/mini_player.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/shell/detail_panel.dart';
import 'package:fmp/ui/shell/phone_dock.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:fmp/ui/shell/side_bar.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

import '../support/a11y.dart';
import '../support/motion.dart';
import '../support/shell.dart';

import 'package:fmp/ui/shell/destination.dart';

/// 外殼的播放控制（`docs/design/DESIGN.md`〈手機〉〈桌面〉）：手機的迷你播放器、
/// 桌面與中寬度的播放膠囊，顯示目前曲目與書脊式進度，能暫停、繼續；
/// 播放失敗時跳出依錯誤分類寫的提示（brief〈錯誤、log 與診斷〉）。播放換成
/// [_FakePlayback]，狀態由測試直接設。
void main() {
  const phone = Size(390, 844);
  const tablet = Size(820, 1180);
  const desktop = Size(1280, 800);

  const track = Track(
    ref: TrackRef(pluginId: 'demo', trackId: 't1'),
    title: '晴天',
    author: '某 UP 主',
    duration: Duration(minutes: 4, seconds: 12),
  );

  late Directory logDir;
  late Log log;
  late PluginHost host;
  late _FakePlayback playback;
  late _FakeQueue queue;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    logDir = Directory.systemTemp.createTempSync('fmp_now_playing_');
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

  PlaybackState state(
    PlaybackStatus status, {
    Duration position = const Duration(minutes: 1, seconds: 36),
    AppError? error,
  }) => PlaybackState(
    track: track,
    status: status,
    position: position,
    duration: track.duration,
    error: error,
  );

  Future<void> start(
    WidgetTester tester,
    Size size, {
    PlaybackState? initial,
    Queue initialQueue = Queue.empty,
    TemporaryPlay? temporary,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    playback = _FakePlayback(initial);
    queue = _FakeQueue(initialQueue);
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          pluginHostProvider.overrideWith((_) => host),
          playbackProvider.overrideWith(() => playback),
          queueProvider.overrideWith(() => queue),
          temporaryPlayProvider.overrideWith(() => _FixedTemporary(temporary)),
        ],
      ),
    );
    // 不用 pumpAndSettle：播放中時首頁「繼續聽」的等化器一直在動。
    await _settle(tester);
  }

  /// 臨時播放 [track]，從 [from] 佇列的目前那首離開。
  TemporaryPlay temporaryFrom(Queue from) => TemporaryPlay.start(
    [track],
    previous: null,
    leaving: from.current,
    position: Duration.zero,
  );

  Future<void> set(WidgetTester tester, PlaybackState next) async {
    playback.set(next);
    await tester.pumpAndSettle();
  }

  /// [next] 播不了，佇列的處理是 [outcome]（[playbackFailureProvider]）。
  Future<void> fail(
    WidgetTester tester,
    PlaybackState next,
    FailureOutcome outcome, {
    int streak = 1,
  }) async {
    playback.set(next);
    ProviderScope.containerOf(tester.element(find.byType(AppShell)))
        .read(playbackFailureProvider.notifier)
        .set(PlaybackFailure(next, outcome, streak: streak));
    await tester.pumpAndSettle();
  }

  Track other(String id) => Track(
    ref: TrackRef(pluginId: 'demo', trackId: id),
    title: id,
    author: 'B',
  );

  /// 目前那首在中間：有上一首也有下一首。
  final middle = Queue.empty.add([other('a'), track, other('b')]).jumpTo(1);

  /// 只有一首：沒有上一首、下一首。
  final single = Queue.empty.add([track]);

  /// 照 manifest 畫出來的音源標識，螢幕閱讀器讀音源名稱。
  final sourceMark = find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Demo Source',
  );

  /// 書脊的已播放段寬度佔膠囊的比例。
  double played(WidgetTester tester, Finder capsule) =>
      tester.getSize(find.byKey(const Key('spine-played'))).width /
      tester.getSize(capsule).width;

  /// 外殼的無障礙（`docs/design/DESIGN.md`〈無障礙〉）：開在空狀態的音樂庫，
  /// 畫面上只有外殼的控制，各種寬度一起檢查。
  group('accessibility', () {
    const ipad13 = Size(1376, 1032);

    Future<void> startShell(
      WidgetTester tester,
      Size size, {
      TargetPlatform? platform,
    }) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await start(
        tester,
        size,
        initial: state(PlaybackStatus.paused),
        initialQueue: middle,
      );
      await openDestination(tester, Destination.library);
      await tester.pumpAndSettle();
    }

    for (final (name, size, platform) in [
      ('phone', phone, null),
      ('tablet', tablet, null),
      ('13-inch iPad', ipad13, null),
      ('desktop', desktop, TargetPlatform.macOS),
      ('narrow desktop window', const Size(960, 720), TargetPlatform.macOS),
    ]) {
      testWidgets('$name: every control has a name, takes keyboard focus, and '
          'is at least 44 on touch or 28 with a mouse', (tester) async {
        final semantics = tester.ensureSemantics();
        await startShell(tester, size, platform: platform);

        await expectAccessible(tester, touch: platform == null);
        semantics.dispose();
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('phone: Tab walks the mini player, its buttons, the tabs and '
        'the search orb, one focus ring at a time', (tester) async {
      final semantics = tester.ensureSemantics();
      await startShell(tester, phone);

      final visited = await tabThrough(tester, 9);
      expect(
        visited,
        containsAllInOrder(<Matcher>[
          startsWith('晴天'),
          equals('播放'),
          equals('下一首'),
          equals('首頁'),
          equals('音樂庫'),
          equals('佇列'),
          equals('設定'),
          equals('搜尋'),
        ]),
      );
      semantics.dispose();
    });

    testWidgets('phone: screen readers hear that tapping the mini player '
        'opens the player, on the same node as the tap', (tester) async {
      final semantics = tester.ensureSemantics();
      await startShell(tester, phone);

      final mini = find.semantics.byLabel(RegExp('^晴天')).evaluate().single;
      final data = mini.getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(mini.hintOverrides?.onTapHint, t.player.open);
      semantics.dispose();
    });

    testWidgets('phone: the search orb is a node of its own size for screen '
        'readers, not the whole screen', (tester) async {
      final semantics = tester.ensureSemantics();
      await startShell(tester, phone);

      final orb = find.semantics.byLabel('搜尋').evaluate().single;
      expect(orb.rect.size, const Size(62, 62));
      semantics.dispose();
    });

    testWidgets('desktop: Tab walks the capsule, the sidebar and the panel, '
        'also out of a page with nothing to focus', (tester) async {
      final semantics = tester.ensureSemantics();
      await startShell(tester, desktop, platform: TargetPlatform.macOS);

      final visited = await tabThrough(tester, 14);
      for (final label in [
        '隨機', '上一首', '播放', '下一首', '循環', //
        '首頁', '音樂庫', '佇列', '設定', '收起面板',
      ]) {
        expect(visited, contains(label));
      }
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a mouse click does not draw a focus ring', (tester) async {
      await startShell(tester, desktop, platform: TargetPlatform.macOS);

      await tester.tap(
        find.descendant(of: find.byType(SideBar), matching: find.text('佇列')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(visibleFocusRings(), 0);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('13-inch iPad: sidebar items take 44 tall while their '
        'highlight stays 32', (tester) async {
      await startShell(tester, ipad13);

      final item = find.ancestor(
        of: find.descendant(
          of: find.byType(SideBar),
          matching: find.text('首頁'),
        ),
        matching: find.byType(ShellButton),
      );
      expect(tester.getSize(item).height, 44);
      final highlight = find.descendant(
        of: item,
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(highlight.first).height, 32);
    });

    testWidgets('the capsule reads its empty part as a playback position '
        'slider that steps 5 seconds', (tester) async {
      final semantics = tester.ensureSemantics();
      await startShell(tester, desktop, platform: TargetPlatform.macOS);

      final slider = find.semantics.byLabel('播放進度');
      final data = slider.evaluate().single.getSemanticsData();
      expect(data.flagsCollection.isSlider, isTrue);
      expect(data.value, '1:36');
      expect(data.increasedValue, '1:41');
      tester.semantics.performAction(slider, SemanticsAction.increase);
      expect(playback.seeks, [const Duration(minutes: 1, seconds: 41)]);
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('phone mini player', () {
    testWidgets('is not there without a current track', (tester) async {
      await start(tester, phone);
      expect(find.byType(MiniPlayer), findsNothing);
      expect(
        find.descendant(of: find.byType(PhoneDock), matching: find.text('首頁')),
        findsOneWidget,
      );
    });

    testWidgets('shows the track, its source mark and the time', (
      tester,
    ) async {
      await start(tester, phone, initial: state(PlaybackStatus.playing));

      final mini = find.byType(MiniPlayer);
      Finder inMini(Finder f) => find.descendant(of: mini, matching: f);
      expect(inMini(find.text('晴天')), findsOneWidget);
      expect(inMini(find.text('某 UP 主')), findsOneWidget);
      expect(inMini(find.text('· 1:36 / 4:12')), findsOneWidget);
      expect(inMini(sourceMark), findsOneWidget);
    });

    testWidgets('is one node for screen readers, apart from the page', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await start(tester, phone, initial: state(PlaybackStatus.playing));

      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.bySemanticsLabel(
            RegExp('晴天\nDemo Source\n某 UP 主\n· 1:36 / 4:12'),
          ),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('pauses and resumes', (tester) async {
      await start(tester, phone, initial: state(PlaybackStatus.playing));

      await tester.tap(find.byTooltip('暫停'));
      expect(playback.playPauses, 1);
      await set(tester, state(PlaybackStatus.paused));
      expect(find.byTooltip('暫停'), findsNothing);
      await tester.tap(find.byTooltip('播放'));
      expect(playback.playPauses, 2);
    });

    testWidgets('skips to the next track', (tester) async {
      await start(
        tester,
        phone,
        initial: state(PlaybackStatus.playing),
        initialQueue: middle,
      );

      await tester.tap(find.byTooltip('下一首'));
      expect(queue.calls, ['next']);
      expect(find.byTooltip('上一首'), findsNothing);
    });

    testWidgets('the next button is disabled on the last track', (
      tester,
    ) async {
      await start(
        tester,
        phone,
        initial: state(PlaybackStatus.playing),
        initialQueue: single,
      );

      await tester.tap(find.byTooltip('下一首'), warnIfMissed: false);
      expect(queue.calls, isEmpty);
    });

    testWidgets('a temporary track has the 臨時 tag, and next goes back to '
        'the queue even from its last track', (tester) async {
      await start(
        tester,
        phone,
        initial: state(PlaybackStatus.playing),
        initialQueue: single,
        temporary: temporaryFrom(single),
      );

      final mini = find.byType(MiniPlayer);
      expect(
        find.descendant(of: mini, matching: find.text('臨時')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('下一首'));
      expect(queue.calls, ['next']);
    });

    testWidgets('a queue track has no 臨時 tag', (tester) async {
      await start(tester, phone, initial: state(PlaybackStatus.playing));

      expect(find.text('臨時'), findsNothing);
    });

    testWidgets('with nothing in the queue to go back to, next is disabled', (
      tester,
    ) async {
      await start(
        tester,
        phone,
        initial: state(PlaybackStatus.playing),
        temporary: temporaryFrom(Queue.empty),
      );

      await tester.tap(find.byTooltip('下一首'), warnIfMissed: false);
      expect(queue.calls, isEmpty);
    });

    testWidgets('the spine follows the position', (tester) async {
      await start(
        tester,
        phone,
        initial: state(PlaybackStatus.playing, position: Duration.zero),
      );
      final mini = find.byType(MiniPlayer);
      expect(played(tester, mini), 0);

      await set(
        tester,
        state(PlaybackStatus.playing, position: const Duration(seconds: 63)),
      );
      expect(played(tester, mini), closeTo(.25, .001));

      await set(
        tester,
        state(PlaybackStatus.playing, position: track.duration!),
      );
      expect(played(tester, mini), closeTo(1, .001));
    });
  });

  group('transport', () {
    for (final (name, size) in [('desktop', desktop), ('tablet', tablet)]) {
      testWidgets('$name: is not there without a current track', (
        tester,
      ) async {
        await start(tester, size);
        expect(find.byType(TransportBar), findsNothing);
      });

      testWidgets('$name: shows the track and pauses, and its spine follows '
          'the position', (tester) async {
        await start(tester, size, initial: state(PlaybackStatus.playing));

        final bar = find.byType(TransportBar);
        Finder inBar(Finder f) => find.descendant(of: bar, matching: f);
        expect(inBar(find.text('晴天')), findsOneWidget);
        expect(inBar(find.text('某 UP 主')), findsOneWidget);
        expect(inBar(find.text('1:36 / 4:12')), findsOneWidget);
        expect(inBar(sourceMark), findsOneWidget);
        expect(played(tester, bar), closeTo(96 / 252, .001));

        await tester.tap(inBar(find.byTooltip('暫停')));
        expect(playback.playPauses, 1);
      });

      testWidgets('$name: skips back and forward', (tester) async {
        await start(
          tester,
          size,
          initial: state(PlaybackStatus.playing),
          initialQueue: middle,
        );

        await tester.tap(find.byTooltip('上一首'));
        await tester.tap(find.byTooltip('下一首'));
        expect(queue.calls, ['previous', 'next']);
      });

      testWidgets('$name: a temporary track has the 臨時 tag and both skips '
          'go back to the queue', (tester) async {
        await start(
          tester,
          size,
          initial: state(PlaybackStatus.playing),
          initialQueue: single,
          temporary: temporaryFrom(single),
        );

        final bar = find.byType(TransportBar);
        expect(
          find.descendant(of: bar, matching: find.text('臨時')),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('上一首'));
        await tester.tap(find.byTooltip('下一首'));
        expect(queue.calls, ['previous', 'next']);
      });

      testWidgets('$name: skipping is disabled at the ends', (tester) async {
        await start(
          tester,
          size,
          initial: state(PlaybackStatus.playing),
          initialQueue: single,
        );

        await tester.tap(find.byTooltip('上一首'), warnIfMissed: false);
        await tester.tap(find.byTooltip('下一首'), warnIfMissed: false);
        expect(queue.calls, isEmpty);
      });
    }

    testWidgets('is one node for screen readers, apart from the page', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await start(tester, desktop, initial: state(PlaybackStatus.playing));

      expect(
        find.descendant(
          of: find.byType(TransportBar),
          matching: find.bySemanticsLabel(RegExp('^晴天\nDemo Source\n某 UP 主')),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('a narrow window drops the time', (tester) async {
      await start(
        tester,
        const Size(720, 560),
        initial: state(PlaybackStatus.playing),
      );
      expect(find.text('1:36 / 4:12'), findsNothing);
      expect(find.text('晴天'), findsOneWidget);
    });
  });

  /// 詳情面板叫出與收起（`docs/design/DESIGN.md` §3.4 的 morph）：中寬度從
  /// 右邊滑入並淡入，寬版面板寬度跟著動、內容欄與播放膠囊一起讓；減少動態
  /// 效果時只淡入淡出。
  group('detail panel motion', () {
    const medium = Size(960, 720);
    const halfway = Duration(milliseconds: 260);

    Finder motion() => find.byKey(const Key('detail-panel-motion'));
    Rect panel(WidgetTester tester) => tester.getRect(find.byType(DetailPanel));
    double opacity(WidgetTester tester) =>
        tester.widget<Opacity>(motion()).opacity;
    double capsuleRight(WidgetTester tester) =>
        tester.getRect(find.byType(TransportBar)).right;

    Future<void> desktopStart(WidgetTester tester, Size size) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await start(tester, size, initial: state(PlaybackStatus.paused));
    }

    Future<void> tapHalfway(WidgetTester tester, String tooltip) async {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pump();
      await tester.pump(halfway);
    }

    // 中寬度浮動面板：右邊離視窗 8，寬 320；播放膠囊右端讓到面板左邊 24。
    const openLeft = 960 - 8 - 320.0;
    const capsuleOpen = openLeft - 24;
    const capsuleClosed = 960 - 24.0;

    testWidgets('medium: the floating panel slides in from the right and '
        'fades in, the capsule giving way along with it; hiding reverses it', (
      tester,
    ) async {
      await desktopStart(tester, medium);
      await tapHalfway(tester, '顯示詳情面板');
      expect(panel(tester).left, inExclusiveRange(openLeft, 960));
      expect(opacity(tester), inExclusiveRange(0, 1));
      expect(
        capsuleRight(tester),
        inExclusiveRange(capsuleOpen, capsuleClosed),
      );

      await _settle(tester);
      expect(panel(tester).left, openLeft);
      expect(opacity(tester), 1);
      expect(capsuleRight(tester), capsuleOpen);

      await tapHalfway(tester, '收起面板');
      expect(panel(tester).left, inExclusiveRange(openLeft, 960));
      expect(opacity(tester), inExclusiveRange(0, 1));
      expect(
        capsuleRight(tester),
        inExclusiveRange(capsuleOpen, capsuleClosed),
      );

      await _settle(tester);
      expect(find.byType(DetailPanel), findsNothing);
      expect(capsuleRight(tester), capsuleClosed);
      debugDefaultTargetPlatformOverride = null;
    });

    // 寬版常駐面板：寬 320 貼右；內容欄（macOS 上包在拖動區的閘裡）右緣是
    // 面板左緣，播放膠囊離它 24。
    const wideOpenLeft = 1280 - 320.0;
    double contentRight(WidgetTester tester) =>
        tester.getRect(find.byType(ShellTopStripGate)).right;

    testWidgets('wide: hiding the docked panel narrows it away while the '
        'content and the capsule widen with it; showing reverses it', (
      tester,
    ) async {
      await desktopStart(tester, desktop);
      expect(panel(tester).left, wideOpenLeft);
      expect(contentRight(tester), wideOpenLeft);
      expect(capsuleRight(tester), wideOpenLeft - 24);

      await tapHalfway(tester, '收起面板');
      expect(panel(tester).left, inExclusiveRange(wideOpenLeft, 1280));
      expect(contentRight(tester), panel(tester).left);
      expect(
        capsuleRight(tester),
        inExclusiveRange(wideOpenLeft - 24, 1280 - 24),
      );

      await _settle(tester);
      expect(find.byType(DetailPanel), findsNothing);
      expect(contentRight(tester), 1280);
      expect(capsuleRight(tester), 1280 - 24);

      await tapHalfway(tester, '顯示詳情面板');
      expect(panel(tester).left, inExclusiveRange(wideOpenLeft, 1280));
      expect(contentRight(tester), panel(tester).left);

      await _settle(tester);
      expect(panel(tester).left, wideOpenLeft);
      expect(contentRight(tester), wideOpenLeft);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('switching to settings, which starts collapsed, does not '
        'animate the panel', (tester) async {
      await desktopStart(tester, desktop);
      await tester.tap(
        find.descendant(of: find.byType(SideBar), matching: find.text('設定')),
      );
      await tester.pump();
      await tester.pump(halfway);
      expect(find.byType(DetailPanel), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('with reduced motion the panel only fades, in both layouts', (
      tester,
    ) async {
      reduceMotion(tester);
      await desktopStart(tester, medium);
      await tapHalfway(tester, '顯示詳情面板');
      expect(panel(tester).left, openLeft);
      expect(opacity(tester), inExclusiveRange(0, 1));
      await _settle(tester);
      await tapHalfway(tester, '收起面板');
      expect(panel(tester).left, openLeft);
      expect(opacity(tester), inExclusiveRange(0, 1));
      await _settle(tester);
      expect(find.byType(DetailPanel), findsNothing);

      await desktopStart(tester, desktop);
      await tapHalfway(tester, '收起面板');
      expect(panel(tester).left, wideOpenLeft);
      expect(opacity(tester), inExclusiveRange(0, 1));
      await _settle(tester);
      expect(find.byType(DetailPanel), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  /// 小元件出現（`docs/design/DESIGN.md`〈狀態變化對照〉）：out 280 淡入並
  /// 從下面滑上來不超過 20；減少動態效果時只淡入，照樣 280。
  group('appearing', () {
    const halfway = Duration(milliseconds: 100);

    double opacityAbove(WidgetTester tester, Finder finder) => tester
        .widgetList<FadeTransition>(
          find.ancestor(of: finder, matching: find.byType(FadeTransition)),
        )
        .fold(1.0, (value, fade) => value * fade.opacity.value);

    /// 出現到一半時 [finder] 的位置比到位時低多少、透明度多少。
    Future<({double drop, double opacity})> halfwayIn(
      WidgetTester tester,
      Finder finder,
      Future<void> Function() show,
    ) async {
      await show();
      await tester.pump();
      await tester.pump(halfway);
      final top = tester.getRect(finder).top;
      final opacity = opacityAbove(tester, finder);
      await _settle(tester);
      return (drop: top - tester.getRect(finder).top, opacity: opacity);
    }

    for (final (name, size, widget) in [
      ('phone mini player', phone, MiniPlayer),
      ('medium capsule', const Size(960, 720), TransportBar),
      ('desktop capsule', desktop, TransportBar),
    ]) {
      testWidgets('$name: fades in rising from below when a track starts', (
        tester,
      ) async {
        await start(tester, size);
        final at = await halfwayIn(
          tester,
          find.byType(widget),
          () async => playback.set(state(PlaybackStatus.playing)),
        );
        expect(at.opacity, inExclusiveRange(0, 1));
        expect(at.drop, inExclusiveRange(0, 20));
      });

      testWidgets('$name: with reduced motion only fades in, over its full '
          'duration', (tester) async {
        reduceMotion(tester);
        await start(tester, size);
        final at = await halfwayIn(
          tester,
          find.byType(widget),
          () async => playback.set(state(PlaybackStatus.playing)),
        );
        expect(at.opacity, inExclusiveRange(0, 1));
        expect(at.drop, 0);
      });
    }

    for (final reduced in [false, true]) {
      testWidgets(
        'toast: fades in${reduced ? ' without moving, with reduced '
                  'motion' : ' rising from below'}',
        (tester) async {
          if (reduced) reduceMotion(tester);
          await start(tester, phone, initial: state(PlaybackStatus.playing));
          final message = find.textContaining('找不到「晴天」');
          final at = await halfwayIn(tester, message, () async {
            playback.set(state(PlaybackStatus.failed, error: const NotFound()));
            ProviderScope.containerOf(tester.element(find.byType(AppShell)))
                .read(playbackFailureProvider.notifier)
                .set(
                  PlaybackFailure(
                    state(PlaybackStatus.failed, error: const NotFound()),
                    FailureOutcome.skipped,
                    streak: 1,
                  ),
                );
          });
          expect(at.opacity, inExclusiveRange(0, 1));
          expect(at.drop, reduced ? 0 : inExclusiveRange(0, 20));
        },
      );
    }
  });

  group('toast', () {
    for (final (name, size) in [('phone', phone), ('desktop', desktop)]) {
      testWidgets('$name: a playback failure without a network says so and '
          'offers a retry', (tester) async {
        await start(tester, size, initial: state(PlaybackStatus.playing));

        await fail(
          tester,
          state(PlaybackStatus.failed, error: const NetworkError()),
          FailureOutcome.stayed,
        );
        expect(find.text('沒有網路，「晴天」無法播放。音樂庫與佇列照常可用。'), findsOneWidget);
        await tester.tap(find.text('重試'));
        await tester.pumpAndSettle();
        expect(playback.played, [track]);
        expect(find.text('重試'), findsNothing);
      });
    }

    testWidgets('goes away by itself', (tester) async {
      await start(tester, phone, initial: state(PlaybackStatus.playing));
      await fail(
        tester,
        state(PlaybackStatus.failed, error: const NotFound()),
        FailureOutcome.skipped,
      );
      expect(find.text('找不到「晴天」，可能已被刪除。已跳下一首。'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.textContaining('找不到「晴天」'), findsNothing);
    });

    for (final (name, size) in [('phone', phone), ('desktop', desktop)]) {
      testWidgets('$name: stopping after three failures says so; 看佇列 opens '
          'the queue page', (tester) async {
        await start(tester, size, initial: state(PlaybackStatus.playing));

        await fail(
          tester,
          state(PlaybackStatus.failed, error: const NotFound()),
          FailureOutcome.stopped,
          streak: 3,
        );
        expect(find.text('連續 3 首都無法播放，已停止。找不到「晴天」，可能已被刪除。'), findsOneWidget);
        await tester.tap(find.text('看佇列'));
        await tester.pumpAndSettle();
        expect(find.byType(QueuePage), findsOneWidget);
      });
    }
  });
}

/// 狀態由測試設定的播放；記下按了幾次播放鈕、要求播了哪些曲目、跳到哪裡。
class _FakePlayback extends Playback {
  _FakePlayback(this._initial);

  final PlaybackState? _initial;
  int playPauses = 0;
  final played = <Track>[];
  final seeks = <Duration>[];

  @override
  PlaybackState? build() => _initial;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  void set(PlaybackState next) => state = next;

  @override
  Future<void> playPause() async => playPauses++;

  @override
  Future<void> play(Track track, {Duration from = Duration.zero}) async =>
      played.add(track);
}

/// 佇列由測試給定；記下按了上一首、下一首。
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
}

/// 臨時播放由測試給定。
class _FixedTemporary extends TemporaryPlayHolder {
  _FixedTemporary(this._initial);

  final TemporaryPlay? _initial;

  @override
  TemporaryPlay? build() => _initial;
}

/// 等畫面上的過場跑完（1 秒）；不等一直在動的等化器。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
