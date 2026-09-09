import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:fmp/ui/widgets/player/mini_player.dart';
import 'package:isar_community/isar.dart';

import '../../support/fakes/fake_source_auth_context.dart';
import '../../support/isar_test_harness.dart';

/// 迷你播放器的無障礙契約。
///
/// 這是本 repo 第一條真的渲染語意樹的測試 —— 在它之前 `lib/ui` 全樹只有 4 個
/// `Semantics(`，而進度條是一個裸的 `GestureDetector`：讀屏軟體看不到它存在，
/// 也沒有任何替代輸入路徑可以調整播放位置。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeIsarForTests();
  });

  Future<void> pumpMiniPlayer(WidgetTester tester, _Harness harness) async {
    // 測試主機是 Windows，`isDesktopPlatform` 為真，所以迷你播放器會多渲染
    // 桌面音量與裝置控制列 —— 400dp 放不下。
    await tester.binding.setSurfaceSize(const Size(900, 800));
    LocaleSettings.setLocale(AppLocale.en);
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: [
            audioControllerProvider.overrideWith(() => harness.controller),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: MiniPlayer(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the progress bar is a slider that reads out a time position', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_Harness.create))!;
    addTearDown(() => tester.runAsync(() => harness.dispose()));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final handle = tester.ensureSemantics();
    await pumpMiniPlayer(tester, harness);

    // 90 秒 / 共 240 秒。讀屏軟體念的必須是時間位置，不是「37%」—— 沒有人能
    // 從百分比知道會跳到哪裡（播放頁的 Slider 用 semanticFormatterCallback
    // 做同一件事）。
    expect(
      tester.getSemantics(find.bySemanticsLabel(t.player.progressBar)),
      isSemantics(
        isSlider: true,
        label: t.player.progressBar,
        value: '1:30',
        increasedValue: '1:35',
        decreasedValue: '1:25',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );

    handle.dispose();
  });

  testWidgets('the mini player itself announces where tapping it goes', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_Harness.create))!;
    addTearDown(() => tester.runAsync(() => harness.dispose()));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final handle = tester.ensureSemantics();
    await pumpMiniPlayer(tester, harness);

    expect(
      tester.getSemantics(find.bySemanticsLabel(t.player.openPlayer)),
      isSemantics(label: t.player.openPlayer, isButton: true),
    );

    handle.dispose();
  });

  testWidgets('every tappable node is labelled and big enough', (tester) async {
    final harness = (await tester.runAsync(_Harness.create))!;
    addTearDown(() => tester.runAsync(() => harness.dispose()));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final handle = tester.ensureSemantics();
    await pumpMiniPlayer(tester, harness);

    // 進度條在觸控裝置上永遠只有 2dp 高，所以它**不能**是一個可點節點 ——
    // 它以 slider 語意存在，而 increase / decrease 不受尺寸規範約束。這條
    // guideline 會抓到任何人把那兩個 excludeFromSemantics 拿掉。
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    handle.dispose();
  });
}

class _Harness {
  _Harness({
    required this.isar,
    required this.controller,
    required this.sourceManager,
    required this.streamResolutionService,
  });

  final Isar isar;
  final _TestAudioController controller;
  final SourceManager sourceManager;
  final DefaultStreamResolutionService streamResolutionService;

  static Future<_Harness> create() async {
    final isar = await Isar.open(
      [TrackSchema, PlayQueueSchema, SettingsSchema],
      directory: '${Directory.current.path}/.dart_tool',
      name: 'mini_player_accessibility_test',
    );

    final trackRepository = TrackRepository(isar);
    final settingsRepository = SettingsRepository(isar);
    final sourceManager = SourceManager();
    final sourceAuthContext = FakeSourceAuthContext();
    final streamResolutionService = DefaultStreamResolutionService(
      trackRepository: trackRepository,
      settingsRepository: settingsRepository,
      sourceManager: sourceManager,
      sourceAuthContext: sourceAuthContext,
    );

    final controller = _TestAudioController(
      PlayerState(
        isPlaying: true,
        playingTrack: Track()
          ..sourceType = 'bilibili'
          ..sourceId = 'BV1'
          ..title = 'Alpha'
          ..artist = 'Someone',
        position: const Duration(seconds: 90),
        duration: const Duration(seconds: 240),
      ),
    );

    return _Harness(
      isar: isar,
      controller: controller,
      sourceManager: sourceManager,
      streamResolutionService: streamResolutionService,
    );
  }

  Future<void> dispose() async {
    streamResolutionService.dispose();
    sourceManager.dispose();
    await isar.close(deleteFromDisk: true);
  }
}

/// 不呼叫 `super.build()`：這條測試只看迷你播放器怎麼畫一個給定的
/// `PlayerState`，真的那個 `build()` 會把整條播放鏈拉起來。
///
/// 狀態從 `build()` 回傳而不是事後 `state =` —— `Notifier` 要先掛進 container
/// 才碰得到 `state`，而這個實例是在 harness 建立時就要帶著狀態的。
class _TestAudioController extends AudioController {
  _TestAudioController(this._seed);

  final PlayerState _seed;

  @override
  PlayerState build() => _seed;
}
