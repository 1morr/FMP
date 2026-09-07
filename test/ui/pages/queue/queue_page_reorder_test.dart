import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/services/audio/queue_state.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:fmp/ui/pages/queue/queue_page.dart';
import 'package:isar_community/isar.dart';

import 'package:fmp/providers/audio/playback_settings_provider.dart';

import '../../../support/fakes/fake_audio_service.dart';
import '../../../support/isar_test_harness.dart';
import '../../../support/now_playing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeIsarForTests();
  });

  testWidgets('QueuePage keeps drag reorder available while shuffle is enabled', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_QueuePageHarness.create))!;
    addTearDown(() => tester.runAsync(() => harness.dispose()));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.binding.setSurfaceSize(const Size(400, 900));
    LocaleSettings.setLocale(AppLocale.en);

    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: [
            audioControllerProvider.overrideWith(() => harness.controller),
            queueStateProvider.overrideWith(
              () => _FixedQueueState(harness.queueState),
            ),
            autoScrollToCurrentTrackProvider.overrideWith((ref) => false),
          ],
          child: const MaterialApp(home: QueuePage()),
        ),
      ),
    );

    await tester.pump();

    expect(_queueOrder(tester), ['Alpha', 'Bravo', 'Charlie']);
    expect(
      find.byWidgetPredicate((widget) => widget is LongPressDraggable<int>),
      findsNWidgets(3),
      reason: 'shuffle mode should still show queue drag affordances',
    );
    expect(
      _queueOrder(tester),
      ['Alpha', 'Bravo', 'Charlie'],
      reason:
          'showing drag affordances should not change the rendered queue order',
    );
    expect(harness.controller.moveInQueueCallCount, 0);
  });
}

class _QueuePageHarness {
  _QueuePageHarness({
    required this.isar,
    required this.controller,
    required this.queueState,
    required this.sourceManager,
    required this.streamResolutionService,
  });

  final Isar isar;
  final _QueuePageTestAudioController controller;

  /// 佇列的形狀住在 `QueueState`，不在 `PlayerState`。頁面讀的是
  /// `queueStateProvider`，所以測試也從這裡餵。
  final QueueState queueState;
  final SourceManager sourceManager;
  final DefaultStreamResolutionService streamResolutionService;

  static Future<_QueuePageHarness> create() async {
    final isar = await Isar.open(
      [TrackSchema, PlayQueueSchema, SettingsSchema],
      directory: '${Directory.current.path}/.dart_tool',
      name: 'queue_page_reorder_lockout_test',
    );

    final queueRepository = QueueRepository(isar);
    final trackRepository = TrackRepository(isar);
    final settingsRepository = SettingsRepository(isar);
    final queuePersistenceManager = QueuePersistenceManager(
      queueRepository: queueRepository,
      trackRepository: trackRepository,
      settingsRepository: settingsRepository,
    );
    final sourceManager = SourceManager();
    final sourceAuthContext = _FakeSourceAuthContext();
    final streamResolutionService = DefaultStreamResolutionService(
      trackRepository: trackRepository,
      settingsRepository: settingsRepository,
      sourceManager: sourceManager,
      sourceAuthContext: sourceAuthContext,
    );
    final audioStreamManager = AudioStreamManager(
      streamResolutionService: streamResolutionService,
      sourceAuthContext: sourceAuthContext,
    );
    final queueManager = QueueManager(
      queueRepository: queueRepository,
      trackRepository: trackRepository,
      queuePersistenceManager: queuePersistenceManager,
    );

    final controller = _QueuePageTestAudioController();

    final queue = [
      _buildTrack(id: 1, sourceId: 'alpha', title: 'Alpha'),
      _buildTrack(id: 2, sourceId: 'bravo', title: 'Bravo'),
      _buildTrack(id: 3, sourceId: 'charlie', title: 'Charlie'),
    ];

    return _QueuePageHarness(
      isar: isar,
      controller: controller,
      queueState: QueueState(
        queue: queue,
        currentIndex: 0,
        queueTrack: queue.first,
        isShuffleEnabled: true,
        queueVersion: 1,
      ),
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

/// `queueStateProvider` 是 `NotifierProvider`，override 要給 notifier 工廠而
/// 不是一個值 —— 這個子類就是「build() 直接回傳固定投影」。
class _FixedQueueState extends QueueStateNotifier {
  _FixedQueueState(this._value);

  final QueueState _value;

  @override
  QueueState build() => _value;
}

/// 不呼叫 `super.build()`：這一頁只讀被覆寫掉的 `queueStateProvider`，
/// 真的那個 `build()` 會把整條播放鏈拉起來。
class _QueuePageTestAudioController extends AudioController {
  int moveInQueueCallCount = 0;

  @override
  PlayerState build() => const PlayerState();

  @override
  Future<void> moveInQueue(int oldIndex, int newIndex) async {
    moveInQueueCallCount++;
  }
}

class _FakeSourceAuthContext implements SourceAuthContext {
  @override
  Future<Map<String, String>?> authForPlay(String sourceType) async => null;

  @override
  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  ) async {
    return PlaybackNetworkRequest(
      url: url,
      headers: SourceHttpPolicy.mediaHeaders(track.sourceType),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Track _buildTrack({
  required int id,
  required String sourceId,
  required String title,
}) {
  return Track()
    ..id = id
    ..sourceId = sourceId
    ..sourceType = SourceIds.bilibili
    ..title = title
    ..artist = '$title Artist'
    ..durationMs = 180000;
}

List<String> _queueOrder(WidgetTester tester) {
  final titles = ['Alpha', 'Bravo', 'Charlie'];
  final positions = <String, double>{
    for (final title in titles) title: tester.getTopLeft(find.text(title)).dy,
  };
  final ordered = positions.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  return ordered.map((entry) => entry.key).toList();
}
