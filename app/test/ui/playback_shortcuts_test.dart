import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
import 'package:fmp/ui/player/player_page.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell.dart';

/// 播放的全域快捷鍵（`docs/design/DESIGN.md`〈無障礙〉的鍵盤）：Space 播放／
/// 暫停、←／→ 倒退與快轉 5 秒、⌘／Ctrl＋←／→ 上一首與下一首；焦點在輸入框
/// 或對話框、選單裡時不攔。播放與佇列換成記下呼叫的假的。
void main() {
  const desktop = Size(1280, 800);

  late Directory logDir;
  late Log log;
  late PluginHost host;
  late _FakePlayback playback;
  late _FakeQueue queue;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    logDir = Directory.systemTemp.createTempSync('fmp_shortcuts_');
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

  Track song(int n) => Track(
    ref: TrackRef(pluginId: 'demo', trackId: 's$n'),
    title: 'Song $n',
    author: 'Artist $n',
    duration: const Duration(minutes: 4, seconds: 9),
    url: 'https://example.com/v/$n',
  );

  /// 第 6 首正在播的 64 首佇列：上一首、下一首都有。
  final queueOf = Queue.empty
      .add([for (var i = 1; i <= 64; i++) song(i)])
      .jumpTo(5);

  PlaybackState state({Duration position = const Duration(seconds: 96)}) =>
      PlaybackState(
        track: queueOf.current!.track,
        status: PlaybackStatus.playing,
        position: position,
        duration: queueOf.current!.track.duration,
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 在 [platform] 的桌面視窗打開 App；平台要在測試結束前設回去。
  void shortcutsTest(
    String name,
    Future<void> Function(WidgetTester tester) body, {
    TargetPlatform platform = TargetPlatform.macOS,
  }) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view
          ..physicalSize = desktop
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
        playback = _FakePlayback(state());
        queue = _FakeQueue(queueOf);
        await tester.pumpWidget(
          buildRoot(
            overrides: [
              logProvider.overrideWithValue(log),
              pluginHostProvider.overrideWith((_) => host),
              playbackProvider.overrideWith(() => playback),
              queueProvider.overrideWith(() => queue),
            ],
          ),
        );
        await settle(tester);
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> openPlayer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('transport-open')));
    await settle(tester);
    expect(find.byType(PlayerPage), findsOneWidget);
  }

  /// 按住 [modifier] 的時候按 [key]。
  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
  }

  group('Space', () {
    shortcutsTest('plays and pauses from the home page', (tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(playback.playPauses, 1);
    });

    shortcutsTest('plays and pauses from the player page', (tester) async {
      await openPlayer(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(playback.playPauses, 1);
    });

    shortcutsTest('is left to a text field that has focus', (tester) async {
      await openSearch(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>(),
        isNotNull,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(playback.playPauses, 0);
    });

    shortcutsTest('is left to a dialog that is open', (tester) async {
      final context = tester.element(find.byType(Scaffold).first);
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('hello')),
        ),
      );
      await settle(tester);
      expect(find.text('hello'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(playback.playPauses, 0);
    });

    shortcutsTest('is left to the ⋮ menu of the player', (tester) async {
      await openPlayer(tester);
      await tester.tap(find.byKey(const Key('player-more')));
      await settle(tester);
      expect(find.text('複製連結'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(playback.playPauses, 0);
    });
  });

  group('arrow keys', () {
    shortcutsTest('← and → seek 5 seconds back and forward', (tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

      expect(playback.seeks, [
        const Duration(seconds: 91),
        const Duration(seconds: 101),
      ]);
    });

    shortcutsTest('seeking stops at the start and at the end', (tester) async {
      playback.set(state(position: const Duration(seconds: 3)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);

      playback.set(state(position: const Duration(seconds: 247)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

      expect(playback.seeks, [
        Duration.zero,
        const Duration(minutes: 4, seconds: 9),
      ]);
    });
  });

  group('previous and next', () {
    shortcutsTest('⌘← and ⌘→ on macOS', (tester) async {
      await chord(
        tester,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.arrowLeft,
      );
      await chord(
        tester,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.arrowRight,
      );

      expect(queue.calls, ['previous', 'next']);
      // 加了修飾鍵就不是倒退、快轉。
      expect(playback.seeks, isEmpty);
    });

    shortcutsTest('Ctrl← and Ctrl→ on Windows', (tester) async {
      await chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.arrowLeft,
      );
      await chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.arrowRight,
      );

      expect(queue.calls, ['previous', 'next']);
      expect(playback.seeks, isEmpty);
    }, platform: TargetPlatform.windows);
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

  void set(PlaybackState next) => state = next;

  @override
  Future<void> playPause() async => playPauses++;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  void preloadNext(Track? track) {}
}

/// 佇列由測試給定；記下上一首、下一首。
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
