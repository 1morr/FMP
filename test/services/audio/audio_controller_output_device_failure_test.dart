import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:isar_community/isar.dart';

import '../../support/audio_controller_harness.dart';
import '../../support/fakes/fake_audio_service.dart';
import '../../support/fakes/fake_source_auth_context.dart';
import '../../support/isar_test_harness.dart';
import '../../support/now_playing.dart';
import '../../support/pump_until.dart';

/// issue #106 的回歸守門。
///
/// 播放中停用選定的輸出裝置之後，AO 失敗正確地出了 toast，但**同一次失敗**又走
/// 了一次 premature-end 路徑 ——
///
/// ```
/// [W] Track ended before its natural end; scheduling retry: at=0:00:13.3, expected=0:03:58.9
/// [I] Retrying playback for: …, savedPosition: 0:00:13.3
/// [E] media_kit ao error: Failed to initialize audio driver 'wasapi'
/// [I] Retry playback succeeded for: …
/// ```
///
/// 重試撞上同一個壞掉的裝置，最後留下一行「成功」而完全沒有聲音。
///
/// **兩條訊息誰先到是量出來的。** 2026-09-15 的 Windows 實測（停用正在輸出的
/// Realtek(R) Audio，系統預設是另一個裝置）：
///
/// ```
/// 23:20:56.224 [D] Track completed: EndedPrematurely(at: 0:01:33.4, expected: 0:05:40.8)
/// 23:20:56.225 [W] Track ended before its natural end; scheduling retry
/// 23:20:56.228 [E] media_kit ao error: Failed to initialize audio driver 'wasapi'
/// ```
///
/// completed 比第一條 `ao` 錯誤早 4ms，所以光「裝置失敗之後不再排重試」擋不住；
/// 裝置失敗還得回頭收掉已經排好的那一次。兩個順序這裡各有一條測試。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('output device failure and premature end', () {
    /// Windows 日誌裡的那首歌：3:58.9 的時長，13.3 秒時裝置掛掉。
    const trackDuration = Duration(minutes: 3, seconds: 58, milliseconds: 900);
    const failurePosition = Duration(seconds: 13, milliseconds: 300);

    /// mpv 在 `ao` 前綴吐的那一條（media_kit 的 errorStream 收不到它）。
    const aoFailure = "Failed to initialize audio driver 'wasapi'";

    late Directory tempDir;
    late Isar isar;
    late FakeAudioService audioService;
    late ToastService toastService;
    late DefaultStreamResolutionService streamResolutionService;
    late AudioController controller;
    late List<ToastMessage> toasts;
    late List<String> logLines;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'audio_controller_output_device_failure_',
      );
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'audio_controller_output_device_failure_test',
      );

      final queueRepository = QueueRepository(isar);
      final trackRepository = TrackRepository(isar);
      final settingsRepository = SettingsRepository(isar);
      final queuePersistenceManager = QueuePersistenceManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
      );
      streamResolutionService = DefaultStreamResolutionService(
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: _StubSourceManager(),
        sourceAuthContext: FakeSourceAuthContext(),
      );
      audioService = FakeAudioService();
      toastService = ToastService();
      controller = buildTestAudioController(
        audioService: audioService,
        queueManager: QueueManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          queuePersistenceManager: queuePersistenceManager,
        ),
        audioStreamManager: AudioStreamManager(
          streamResolutionService: streamResolutionService,
          sourceAuthContext: FakeSourceAuthContext(),
        ),
        toastService: toastService,
        nowPlayingPublisher: testNowPlayingPublisher(),
        settingsRepository: settingsRepository,
      );

      await controller.initialize();
    });

    tearDown(() async {
      streamResolutionService.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    /// 讓一首歌真的播起來，並從這一刻開始收 toast 與日誌。
    Future<Track> startPlaying(String sourceId) async {
      final track = _track(sourceId);
      await controller.playTrack(track);
      await pumpUntil(
        () => controller.state.isPlaying,
        reason: 'the track should be playing before the device fails',
      );

      toasts = [];
      logLines = [];
      final toastSubscription = toastService.messageStream.listen(toasts.add);
      final logSubscription = AppLogger.logStream.listen(
        (entry) => logLines.add(entry.message),
      );
      addTearDown(toastSubscription.cancel);
      addTearDown(logSubscription.cancel);

      audioService.playUrlCalls.clear();
      audioService.setUrlCalls.clear();
      audioService.playMediaCalls.clear();
      audioService.setMediaCalls.clear();
      audioService.setDurationValue(trackDuration);
      audioService.emitPosition(failurePosition);
      return track;
    }

    // 實機順序：mpv 先宣告 completed，4ms 後才吐 ao 錯誤。
    test('premature end then device failure cancels the retry', () async {
      await startPlaying('output-device-cancels-retry');

      audioService.emitCompleted();
      audioService.emitOutputDeviceFailure(aoFailure);

      await pumpUntil(
        () => toasts.isNotEmpty,
        reason: 'the output device failure should reach the toast stream',
      );
      // 重試排在 1 秒後的計時器上，但 isRetrying 是排定當下同步翻真的；推完事件
      // 佇列它還是 false，就代表那次重試已經被收回，而不是還沒開始。
      await drainEventQueue(
        reason: 'the scheduled retry would still be pending here if kept',
      );

      expect(controller.state.isRetrying, isFalse);
      expect(controller.state.isNetworkError, isFalse);
      expect(controller.state.nextRetryAt, isNull);
      expect(
        logLines,
        contains(contains('cancelling the premature-end retry')),
      );

      // 重試的計時器本來就在 1 秒後才動；睡過它才有資格說它沒有跑。
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      await drainEventQueue(reason: 'the retry timer has now passed its due');

      expect(audioService.playMediaCalls, isEmpty);
      expect(audioService.setMediaCalls, isEmpty);
      expect(audioService.playUrlCalls, isEmpty);
      expect(logLines, isNot(contains(contains('Retrying playback for'))));
      expect(logLines, isNot(contains(contains('Retry playback succeeded'))));
      expect(toasts, hasLength(1));
      expect(toasts.single.type, ToastType.error);
    });

    test('device failure then premature end schedules no retry', () async {
      await startPlaying('output-device-premature-end');

      audioService.emitOutputDeviceFailure(aoFailure);
      audioService.emitCompleted();

      await pumpUntil(
        () => toasts.isNotEmpty,
        reason: 'the output device failure should reach the toast stream',
      );
      // 重試是同步排的（`scheduleRetry` 當場回 retryScheduled 事件），所以推完
      // 事件佇列還沒有重試狀態，就代表這次不會有重試。
      await drainEventQueue(
        reason: 'a premature-end retry would have been scheduled by now',
      );

      // 一次裝置失敗只講一次。
      expect(toasts, hasLength(1));
      expect(toasts.single.type, ToastType.error);
      expect(
        toasts.single.message,
        anyOf(
          contains('Audio output device'),
          contains('音訊輸出裝置'),
          contains('音频输出设备'),
        ),
      );

      // 沒有重試：沒有重新開串流，也沒有進重試狀態。
      expect(audioService.playMediaCalls, isEmpty);
      expect(audioService.setMediaCalls, isEmpty);
      expect(audioService.playUrlCalls, isEmpty);
      expect(audioService.setUrlCalls, isEmpty);
      expect(controller.state.isRetrying, isFalse);
      expect(controller.state.isNetworkError, isFalse);
      expect(controller.state.nextRetryAt, isNull);

      // 日誌不能再出現 issue #106 裡那三行。
      expect(logLines, contains(contains('Audio output device failed')));
      expect(logLines, isNot(contains(contains('scheduling retry'))));
      expect(logLines, isNot(contains(contains('Retrying playback for'))));
      expect(logLines, isNot(contains(contains('Retry playback succeeded'))));

      // 媒體本身沒問題，所以不去怪那首歌。
      expect(controller.state.error, isNull);
    });

    test('a later request is not covered by the suppression', () async {
      final track = await startPlaying('output-device-generation');

      audioService.emitOutputDeviceFailure(aoFailure);
      audioService.emitCompleted();
      await pumpUntil(
        () => toasts.isNotEmpty,
        reason: 'the output device failure should reach the toast stream',
      );

      // 使用者修好裝置後重按播放 —— 換一個請求世代，抑制就該失效。
      //
      // 這裡刻意不等 `isPlaying`：裝置失敗後的 5 秒保護窗會把剛翻真的 playing
      // 收回去（issue #41 的既有行為），而抑制該不該失效與那個窗無關。串流重新
      // 開過就是新世代已經生效。
      audioService.playUrlCalls.clear();
      await controller.playTrack(track);
      expect(
        audioService.playUrlCalls,
        hasLength(1),
        reason: 'the manual replay should open the stream again',
      );

      audioService.setDurationValue(trackDuration);
      audioService.emitPosition(failurePosition);
      audioService.emitCompleted();

      await pumpUntil(
        () => controller.state.isRetrying,
        reason: 'a premature end in a newer request should still retry',
      );
      expect(controller.state.isRetrying, isTrue);
    });
  });
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceIds.youtube
    ..title = 'Track $sourceId'
    ..artist = 'Tester';
}

class _StubSourceManager extends SourceManager {
  _StubSourceManager() : super(sources: const []);

  final _source = _StubAudioStreamSource();

  @override
  AudioStreamSource? audioStreamSource(String type) => _source;

  @override
  void dispose() {}
}

class _StubAudioStreamSource implements AudioStreamSource {
  @override
  String get sourceType => SourceIds.youtube;

  @override
  Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
    return AudioStreamResult(
      url: 'https://example.com/${request.sourceId}.m4a',
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
    );
  }

  @override
  Future<AudioStreamResult?> getAlternativeAudioStream(
    AudioStreamRequest request,
  ) async => null;
}
