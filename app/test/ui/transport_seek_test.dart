import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:material_ui/material_ui.dart';

/// 桌面播放膠囊的進度（`docs/design/DESIGN.md`〈桌面〉）：滑鼠版可以點或拖
/// 膠囊的空白處改進度，移上去時浮出那個位置的時間；平板照手機只顯示。
void main() {
  const desktop = Size(1280, 800);

  late Directory logDir;
  late Log log;
  late PluginHost host;
  late _FakePlayback playback;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    logDir = Directory.systemTemp.createTempSync('fmp_transport_seek_');
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

  /// 長四分鐘：位置換成時間整齊（25% 是 1:00、50% 是 2:00、75% 是 3:00）。
  const track = Track(
    ref: TrackRef(pluginId: 'demo', trackId: 't1'),
    title: '晴天',
    author: '某 UP 主',
    duration: Duration(minutes: 4),
  );

  /// 在 [platform]、[size] 的視窗打開 App，正在播 [track]；平台要在測試
  /// 結束前設回去。
  void transportTest(
    String name,
    Future<void> Function(WidgetTester tester) body, {
    Size size = desktop,
    TargetPlatform platform = TargetPlatform.macOS,
  }) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const channel = MethodChannel('fmp/window');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => null);
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        playback = _FakePlayback(
          const PlaybackState(
            track: track,
            status: PlaybackStatus.playing,
            position: Duration(seconds: 96),
            duration: Duration(minutes: 4),
          ),
        );
        await tester.pumpWidget(
          buildRoot(
            overrides: [
              pluginHostProvider.overrideWith((_) => host),
              playbackProvider.overrideWith(() => playback),
              queueProvider.overrideWith(
                () => _FakeQueue(Queue.empty.add([track])),
              ),
            ],
          ),
        );
        for (var i = 0; i < 16; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  /// 膠囊上 [fraction]（0–1）處、垂直置中的點：在控制鈕與時間之間的空白。
  Offset onCapsule(WidgetTester tester, double fraction) {
    final rect = tester.getRect(find.byKey(const Key('transport-seek')));
    return Offset(rect.left + rect.width * fraction, rect.center.dy);
  }

  /// 這次 seek 的位置離 [expected] 在 1 毫秒內（比例換算有浮點誤差）。
  Matcher seekedTo(Duration expected) => predicate<List<Duration>>(
    (seeks) =>
        seeks.length == 1 &&
        (seeks.single - expected).inMilliseconds.abs() <= 1,
    'one seek to $expected',
  );

  group('desktop', () {
    transportTest('tapping the empty part of the capsule seeks to that '
        'fraction', (tester) async {
      await tester.tapAt(onCapsule(tester, .75));
      await tester.pump();

      expect(playback.seeks, seekedTo(const Duration(minutes: 3)));
    });

    transportTest('dragging seeks once, on release, to where it is dropped', (
      tester,
    ) async {
      final gesture = await tester.startGesture(onCapsule(tester, .25));
      await gesture.moveBy(
        Offset(
          tester.getSize(find.byKey(const Key('transport-seek'))).width * .125,
          0,
        ),
      );
      await gesture.moveBy(
        Offset(
          tester.getSize(find.byKey(const Key('transport-seek'))).width * .125,
          0,
        ),
      );
      await tester.pump();

      // 拖的時候泡泡寫手指的位置，還沒有 seek。
      expect(
        find.descendant(
          of: find.byKey(const Key('transport-seek-time')),
          matching: find.text('2:00'),
        ),
        findsOneWidget,
      );
      expect(playback.seeks, isEmpty);

      await gesture.up();
      await tester.pump();
      expect(playback.seeks, seekedTo(const Duration(minutes: 2)));
      expect(find.byKey(const Key('transport-seek-time')), findsNothing);
    });

    transportTest('hovering shows the time at the pointer and a hint line, '
        'and leaving removes them', (tester) async {
      expect(find.byKey(const Key('transport-seek-time')), findsNothing);
      expect(find.byKey(const Key('spine-hint')), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(600, 300));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(onCapsule(tester, .75));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('transport-seek-time')),
          matching: find.text('3:00'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('spine-hint')), findsOneWidget);
      // 只是移上去，沒有 seek。
      expect(playback.seeks, isEmpty);

      await mouse.moveTo(onCapsule(tester, .25));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const Key('transport-seek-time')),
          matching: find.text('1:00'),
        ),
        findsOneWidget,
      );

      await mouse.moveTo(const Offset(600, 300));
      await tester.pump();
      expect(find.byKey(const Key('transport-seek-time')), findsNothing);
      expect(find.byKey(const Key('spine-hint')), findsNothing);
    });
  });

  group('tablet', () {
    for (final size in [const Size(820, 1180), const Size(1180, 820)]) {
      transportTest(
        '${size.width.toInt()} x ${size.height.toInt()}: the capsule has no '
        'seek layer',
        (tester) async {
          expect(find.byKey(const Key('transport-open')), findsOneWidget);
          expect(find.byKey(const Key('transport-seek')), findsNothing);
        },
        size: size,
        platform: TargetPlatform.iOS,
      );
    }
  });
}

/// 狀態由測試設定的播放；記下 seek。
class _FakePlayback extends Playback {
  _FakePlayback(this._initial);

  final PlaybackState? _initial;
  final seeks = <Duration>[];

  @override
  PlaybackState? build() => _initial;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  void preloadNext(Track? track) {}
}

class _FakeQueue extends QueueController {
  _FakeQueue(this._initial);

  final Queue _initial;

  @override
  Queue build() => _initial;
}
