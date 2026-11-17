import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/now_playing/mini_player.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';
import 'package:fmp/ui/shell/phone_dock.dart';
import 'package:material_ui/material_ui.dart';

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
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    playback = _FakePlayback(initial);
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          pluginHostProvider.overrideWith((_) => host),
          playbackProvider.overrideWith(() => playback),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> set(WidgetTester tester, PlaybackState next) async {
    playback.set(next);
    await tester.pumpAndSettle();
  }

  /// 照 manifest 畫出來的音源標識，螢幕閱讀器讀音源名稱。
  final sourceMark = find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Demo Source',
  );

  /// 書脊的已播放段寬度佔膠囊的比例。
  double played(WidgetTester tester, Finder capsule) =>
      tester.getSize(find.byKey(const Key('spine-played'))).width /
      tester.getSize(capsule).width;

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

    testWidgets('pauses and resumes', (tester) async {
      await start(tester, phone, initial: state(PlaybackStatus.playing));

      await tester.tap(find.byTooltip('暫停'));
      expect(playback.playPauses, 1);
      await set(tester, state(PlaybackStatus.paused));
      expect(find.byTooltip('暫停'), findsNothing);
      await tester.tap(find.byTooltip('播放'));
      expect(playback.playPauses, 2);
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
    }

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

  group('toast', () {
    for (final (name, size) in [('phone', phone), ('desktop', desktop)]) {
      testWidgets('$name: a playback failure without a network says so and '
          'offers a retry', (tester) async {
        await start(tester, size, initial: state(PlaybackStatus.playing));

        await set(
          tester,
          state(PlaybackStatus.failed, error: const NetworkError()),
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
      await set(tester, state(PlaybackStatus.failed, error: const NotFound()));
      expect(find.textContaining('找不到「晴天」'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.textContaining('找不到「晴天」'), findsNothing);
    });
  });
}

/// 狀態由測試設定的播放；記下按了幾次播放鈕、要求播了哪些曲目。
class _FakePlayback extends Playback {
  _FakePlayback(this._initial);

  final PlaybackState? _initial;
  int playPauses = 0;
  final played = <Track>[];

  @override
  PlaybackState? build() => _initial;

  void set(PlaybackState next) => state = next;

  @override
  Future<void> playPause() async => playPauses++;

  @override
  Future<void> play(Track track) async => played.add(track);
}
