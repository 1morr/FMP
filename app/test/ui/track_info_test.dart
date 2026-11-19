import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/focus_ring.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/shell/detail_content.dart';
import 'package:material_ui/material_ui.dart';

/// 曲目資訊（票 17，`docs/design/player.html`〈曲目資訊〉）：從音源膠囊、⋮、
/// 兩欄頂列的資訊鈕與 ⌘I 打開；缺的欄位不顯示；無障礙。以及桌面詳情面板
/// （`docs/design/shell.html` 的 `.detail`）的內容與它什麼時候查曲目資訊。
///
/// 曲目資訊換成記下查詢次數的假的（`trackInfoProvider`），播放與佇列換成
/// 測試設定的，不聯網、不跑引擎。背景一直在動，不用 `pumpAndSettle`。
void main() {
  const phone = Size(390, 844);
  const desktop = Size(1280, 800);

  late Directory logDir;
  late Log log;
  late PluginHost host;
  late _FakePlayback playback;
  late _FakeQueue queue;

  /// 每首被查曲目資訊的次數。
  late Map<TrackRef, int> asked;

  /// 查曲目資訊的回答；預設全部欄位都有。
  late Future<TrackInfo?> Function(TrackRef track) answer;

  const fullInfo = TrackInfo(
    album: 'Night Train',
    publishedAt: null,
    playCount: 376272,
    likeCount: 3122,
    commentCount: 110,
    description: '收錄於專輯。',
  );

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    logDir = Directory.systemTemp.createTempSync('fmp_track_info_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    host = PluginHost(
      bundles: [
        PluginBundle(
          manifest: jsonEncode({
            'id': 'demo',
            'name': 'Demo Source',
            'version': '1.0.0',
            'capabilities': ['search', 'resolveStream', 'trackInfo'],
            'domains': ['api.example.com'],
          }),
          code: '',
        ),
      ],
      log: log,
    );
    asked = {};
    answer = (_) async => TrackInfo(
      album: fullInfo.album,
      publishedAt: DateTime.utc(2026, 3, 14, 12),
      playCount: fullInfo.playCount,
      likeCount: fullInfo.likeCount,
      commentCount: fullInfo.commentCount,
      description: fullInfo.description,
    );
  });
  tearDown(() async {
    LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale);
    await host.close();
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  Track song(int n, {bool url = true}) => Track(
    ref: TrackRef(pluginId: 'demo', trackId: 's$n'),
    title: 'Song $n',
    author: 'Artist $n',
    duration: const Duration(minutes: 4, seconds: 9),
    url: url ? 'https://example.com/v/$n' : null,
  );

  Queue queueOf({int current = 1, int count = 8}) => Queue.empty
      .add([for (var i = 1; i <= count; i++) song(i)])
      .jumpTo(current - 1);

  Future<void> pumpFor(WidgetTester tester, Duration duration) async {
    final steps = duration.inMilliseconds ~/ 50;
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> settle(WidgetTester tester) =>
      pumpFor(tester, const Duration(milliseconds: 800));

  void infoTest(
    String name,
    Future<void> Function(WidgetTester tester) body, {
    Size size = phone,
    TargetPlatform platform = TargetPlatform.iOS,
    bool reduceMotion = false,
    Queue? initialQueue,
    bool nothingPlaying = false,
  }) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        if (reduceMotion) {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(disableAnimations: true);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
        }
        const channel = MethodChannel('fmp/window');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => null);
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final q = initialQueue ?? queueOf();
        playback = _FakePlayback(
          nothingPlaying ? null : _playing(q.current!.track),
        );
        queue = _FakeQueue(q);
        await tester.pumpWidget(
          buildRoot(
            overrides: [
              pluginHostProvider.overrideWith((_) => host),
              playbackProvider.overrideWith(() => playback),
              queueProvider.overrideWith(() => queue),
              trackInfoProvider.overrideWith((ref, track) {
                asked[track] = (asked[track] ?? 0) + 1;
                return answer(track);
              }),
              coverImageLoaderProvider.overrideWithValue(
                (_) => MemoryImage(_transparentPng),
              ),
            ],
          ),
        );
        await settle(tester);
        await body(tester);
        // 收掉詳情面板等著查的計時器。
        await pumpFor(tester, const Duration(seconds: 2));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> openPlayer(WidgetTester tester, {bool desktop = false}) async {
    await tester.tap(
      find.byKey(Key(desktop ? 'transport-open' : 'mini-player')),
    );
    await settle(tester);
    expect(find.byType(PlayerPage), findsOneWidget);
  }

  /// 曲目資訊開著時，標籤為 [label] 的那一列在不在。
  Finder row(String label) => find.descendant(
    of: find.bySemanticsLabel('曲目資訊'),
    matching: find.text(label),
  );

  group('opening', () {
    infoTest('phone: the source capsule opens a sheet with the track, its '
        'source, length and what the plugin gives', (tester) async {
      await openPlayer(tester);

      await tester.tap(find.byKey(const Key('player-signature')));
      await tester.pump();
      expect(find.byKey(const Key('track-info-slide')), findsOneWidget);
      await settle(tester);

      expect(row('Song 1'), findsOneWidget);
      expect(row('Demo Source'), findsOneWidget);
      expect(row('4:09'), findsOneWidget);
      expect(row('Night Train'), findsOneWidget);
      expect(row('2026-03-14'), findsOneWidget);
      expect(row('376,272'), findsOneWidget);
      expect(row('3,122'), findsOneWidget);
      expect(row('110'), findsOneWidget);
      expect(row('收錄於專輯。'), findsOneWidget);
      expect(row('在 Demo Source 打開'), findsOneWidget);
      expect(row('複製連結'), findsOneWidget);
    });

    infoTest('phone: ⋮ lists track info first and opens it', (tester) async {
      await openPlayer(tester);

      await tester.tap(find.byKey(const Key('player-more')));
      await settle(tester);
      expect(find.text('曲目資訊'), findsOneWidget);
      expect(find.text('複製連結'), findsOneWidget);
      await tester.tap(find.text('曲目資訊'));
      await settle(tester);

      expect(row('Night Train'), findsOneWidget);
    });

    infoTest(
      'desktop: the info button in the top bar opens a centred dialog, '
      'Esc closes it',
      (tester) async {
        await openPlayer(tester, desktop: true);

        expect(find.byTooltip('曲目資訊（⌘I）'), findsOneWidget);
        await tester.tap(find.byKey(const Key('player-info')));
        await tester.pump();
        expect(find.byKey(const Key('track-info-fade')), findsOneWidget);
        expect(find.byKey(const Key('track-info-slide')), findsNothing);
        await settle(tester);
        expect(row('Night Train'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(row('Night Train'), findsNothing);
        expect(find.byType(PlayerPage), findsOneWidget);
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );

    for (final (name, platform, modifier) in [
      ('⌘I on macOS', TargetPlatform.macOS, LogicalKeyboardKey.metaLeft),
      (
        'Ctrl+I on Windows',
        TargetPlatform.windows,
        LogicalKeyboardKey.controlLeft,
      ),
    ]) {
      infoTest(
        '$name opens the track info from any page',
        (tester) async {
          expect(find.byType(PlayerPage), findsNothing);

          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
          await tester.sendKeyUpEvent(modifier);
          await settle(tester);

          expect(row('Song 1'), findsOneWidget);
          expect(row('Night Train'), findsOneWidget);
        },
        size: desktop,
        platform: platform,
      );
    }

    infoTest(
      '⌘I does nothing when nothing is playing',
      (tester) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await settle(tester);

        expect(find.bySemanticsLabel('曲目資訊'), findsNothing);
      },
      size: desktop,
      platform: TargetPlatform.macOS,
      nothingPlaying: true,
    );
  });

  group('missing fields', () {
    infoTest('fields the plugin does not give are not shown', (tester) async {
      answer = (_) async => const TrackInfo(playCount: 12, description: 'D');
      await openPlayer(tester);
      await tester.tap(find.byKey(const Key('player-signature')));
      await settle(tester);

      expect(row('播放數'), findsOneWidget);
      expect(row('簡介'), findsOneWidget);
      for (final label in ['專輯', '發佈日期', '點讚', '評論']) {
        expect(row(label), findsNothing, reason: label);
      }
    });

    infoTest('a source without track info shows only what the track has, '
        'without a link row for a track without a url', (tester) async {
      answer = (_) async => null;
      await openPlayer(tester);
      await tester.tap(find.byKey(const Key('player-signature')));
      await settle(tester);

      expect(row('音源'), findsOneWidget);
      expect(row('時長'), findsOneWidget);
      expect(find.byKey(const Key('track-info-loading')), findsNothing);
      expect(find.byKey(const Key('track-info-failed')), findsNothing);
      expect(find.byKey(const Key('track-info-open')), findsNothing);
    }, initialQueue: Queue.empty.add([song(1, url: false)]).jumpTo(0));

    infoTest('a failed lookup says so and can be retried', (tester) async {
      answer = (_) async => throw const NetworkError();
      await openPlayer(tester);
      await tester.tap(find.byKey(const Key('player-signature')));
      await settle(tester);
      expect(find.byKey(const Key('track-info-failed')), findsOneWidget);
      expect(row('時長'), findsOneWidget);
      // 手機的點擊區補到 44（`DESIGN.md`〈稿內不一致與實作注意〉第 2 點）。
      expect(
        tester.getSize(find.byKey(const Key('track-info-retry'))).height,
        greaterThanOrEqualTo(44),
      );

      answer = (_) async => const TrackInfo(album: 'Back');
      await tester.tap(find.text('重試'));
      await settle(tester);

      expect(row('Back'), findsOneWidget);
      expect(asked[song(1).ref], 2);
    });
  });

  group('accessibility', () {
    infoTest(
      'the source capsule can be reached with the keyboard: accent '
      'focus ring, Enter opens the track info',
      (tester) async {
        await openPlayer(tester, desktop: true);
        final capsule = find.byKey(const Key('player-signature'));
        Focus.of(
          tester.element(
            find.descendant(of: capsule, matching: find.byType(FocusRing)),
          ),
        ).requestFocus();
        // 焦點外框只在鍵盤操作時畫。
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        await tester.pump();

        expect(
          tester
              .widget<FocusRing>(
                find.descendant(of: capsule, matching: find.byType(FocusRing)),
              )
              .visible,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settle(tester);
        expect(row('Night Train'), findsOneWidget);
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic;
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );

    infoTest('on a phone the capsule answers taps up to 44 high', (
      tester,
    ) async {
      await openPlayer(tester);
      final capsule = find.byKey(const Key('player-signature'));
      final box = tester.getRect(capsule);

      expect(box.height, greaterThanOrEqualTo(44));
      // 看得到的膠囊上方 10 的地方也打得開。
      await tester.tapAt(Offset(box.center.dx, box.top + 4));
      await settle(tester);
      expect(row('Night Train'), findsOneWidget);
    });

    infoTest('with reduced motion the sheet fades in instead of sliding up', (
      tester,
    ) async {
      await openPlayer(tester);

      await tester.tap(find.byKey(const Key('player-signature')));
      await tester.pump();

      expect(find.byKey(const Key('track-info-fade')), findsOneWidget);
      expect(find.byKey(const Key('track-info-slide')), findsNothing);
    }, reduceMotion: true);

    infoTest(
      'the close button and links are reachable with the keyboard',
      (tester) async {
        await openPlayer(tester, desktop: true);
        await tester.tap(find.byKey(const Key('player-info')));
        await settle(tester);

        for (final key in [
          'track-info-close',
          'track-info-open',
          'track-info-copy',
        ]) {
          expect(
            find.descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(FocusRing),
            ),
            findsOneWidget,
            reason: key,
          );
        }
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );
  });

  group('shared button keyboard', () {
    infoTest(
      'a focused text button is pressed with Enter; Space still plays and '
      'pauses',
      (tester) async {
        answer = (_) async => throw const NetworkError();
        await pumpFor(tester, trackInfoSettleDelay * 1.5);
        final retry = find.byKey(const Key('detail-retry'));
        expect(retry, findsOneWidget);
        expect(asked[song(1).ref], 1);

        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        Focus.of(
          tester.element(
            find.descendant(of: retry, matching: find.byType(FocusRing)),
          ),
        ).requestFocus();
        await tester.pump();
        await tester.pump();
        expect(
          tester
              .widget<FocusRing>(
                find.descendant(of: retry, matching: find.byType(FocusRing)),
              )
              .visible,
          isTrue,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(playback.playPauses, 1);
        expect(asked[song(1).ref], 1);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settle(tester);
        expect(asked[song(1).ref], 2);
        expect(playback.playPauses, 1);
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic;
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );
  });

  infoTest(
    'Space on the focused source capsule plays and pauses without opening '
    'the track info',
    (tester) async {
      await openPlayer(tester, desktop: true);
      final capsule = find.byKey(const Key('player-signature'));
      Focus.of(
        tester.element(
          find.descendant(of: capsule, matching: find.byType(FocusRing)),
        ),
      ).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);

      expect(playback.playPauses, 1);
      expect(row('Song 1'), findsNothing);
    },
    size: desktop,
    platform: TargetPlatform.macOS,
  );

  group('detail panel', () {
    infoTest(
      'shows the playing track, its source, the next three and, after a '
      'moment, the description',
      (tester) async {
        final panel = find.byType(DetailContent);
        Finder inPanel(String text) =>
            find.descendant(of: panel, matching: find.text(text));

        expect(inPanel('Song 1'), findsOneWidget);
        expect(inPanel('Demo Source'), findsOneWidget);
        expect(inPanel('Song 2'), findsOneWidget);
        expect(inPanel('Song 4'), findsOneWidget);
        expect(inPanel('Song 5'), findsNothing);
        expect(
          find.descendant(of: panel, matching: find.byType(Cover)),
          findsWidgets,
        );

        await pumpFor(tester, trackInfoSettleDelay * 1.2);
        expect(inPanel('收錄於專輯。'), findsOneWidget);
        expect(
          find.descendant(of: panel, matching: find.textContaining('376,272')),
          findsOneWidget,
        );

        await tester.tap(inPanel('Song 3'));
        await tester.pump();
        expect(queue.calls, ['playAt 2']);
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );

    infoTest(
      'says nothing is playing when there is no track',
      (tester) async {
        expect(find.byKey(const Key('detail-empty')), findsOneWidget);
        expect(find.text('目前沒有播放的曲目'), findsOneWidget);
      },
      size: desktop,
      platform: TargetPlatform.macOS,
      nothingPlaying: true,
    );

    infoTest(
      'a collapsed panel does not look the track up',
      (tester) async {
        await tester.tap(find.byTooltip('收起面板'));
        await pumpFor(tester, trackInfoSettleDelay * 2);

        expect(find.byType(DetailContent), findsNothing);
        expect(asked, isEmpty);
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );

    infoTest(
      'a narrow window without the floating panel does not look the track up',
      (tester) async {
        await pumpFor(tester, trackInfoSettleDelay * 2);

        expect(find.byType(DetailContent), findsNothing);
        expect(asked, isEmpty);
      },
      size: const Size(960, 720),
      platform: TargetPlatform.macOS,
    );

    infoTest(
      'the floating panel of a narrow window closes with Esc',
      (tester) async {
        await tester.tap(find.byTooltip('顯示詳情面板'));
        await settle(tester);
        expect(find.byType(DetailContent), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);

        expect(find.byType(DetailContent), findsNothing);
      },
      size: const Size(960, 720),
      platform: TargetPlatform.macOS,
    );

    infoTest(
      'the panel under the full-screen player does not look tracks up',
      (tester) async {
        await openPlayer(tester, desktop: true);
        playback.show(song(2));
        await pumpFor(tester, trackInfoSettleDelay * 2);

        expect(asked.containsKey(song(2).ref), isFalse);

        // 收起播放頁、面板又看得到時才查。
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await pumpFor(tester, trackInfoSettleDelay * 1.5);
        expect(asked[song(2).ref], 1);
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );

    infoTest(
      'quickly skipping through tracks only looks up the one it stays on',
      (tester) async {
        for (final n in [2, 3, 4]) {
          playback.show(song(n));
          await pumpFor(tester, const Duration(milliseconds: 300));
        }
        await pumpFor(tester, trackInfoSettleDelay * 1.2);

        expect(asked.keys, [song(4).ref]);
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );

    infoTest(
      'a track already looked up is not asked again in this run',
      (tester) async {
        await pumpFor(tester, trackInfoSettleDelay * 1.2);
        playback.show(song(2));
        await pumpFor(tester, trackInfoSettleDelay * 1.2);
        playback.show(song(1));
        await pumpFor(tester, const Duration(milliseconds: 100));

        expect(asked, {song(1).ref: 1, song(2).ref: 1});
        // 回到查過的那首，簡介馬上就在，不用再等。
        expect(find.text('收錄於專輯。'), findsOneWidget);
      },
      size: desktop,
      platform: TargetPlatform.macOS,
    );
  });
}

PlaybackState _playing(Track track) => PlaybackState(
  track: track,
  status: PlaybackStatus.playing,
  position: const Duration(minutes: 1),
  duration: track.duration,
);

/// 狀態由測試設定的播放。
class _FakePlayback extends Playback {
  _FakePlayback(this._initial);

  final PlaybackState? _initial;

  @override
  PlaybackState? build() => _initial;

  int playPauses = 0;

  /// 換成正在播 [track]。
  void show(Track track) => state = _playing(track);

  @override
  Future<void> playPause() async => playPauses++;

  @override
  Future<void> seek(Duration position) async {}

  @override
  void preloadNext(Track? track) {}
}

/// 佇列由測試給定；記下按了什麼。
class _FakeQueue extends QueueController {
  _FakeQueue(this._initial);

  final Queue _initial;
  final calls = <String>[];

  @override
  Queue build() => _initial;

  @override
  Future<void> playAt(int index) async => calls.add('playAt $index');
}

/// 1×1 透明的 PNG：測試不載入真的封面。
final _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==',
);
