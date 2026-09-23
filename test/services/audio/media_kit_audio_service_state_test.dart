import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/media_kit_audio_service.dart';
import 'package:media_kit/media_kit.dart';

import '../../support/pump_until.dart';

/// 桌面後端的暫停與緩衝狀態，跑在真的 [MediaKitAudioService] 上。
///
/// `flutter test` 裡沒有 libmpv，所以把 media_kit 的 [PlatformPlayer] 換成
/// [_FakePlatformPlayer]：服務本身的狀態合成與開流流程照樣執行，只有引擎是假的。
void main() {
  late _FakePlatformPlayer engine;
  late MediaKitAudioService service;

  setUp(() async {
    engine = _FakePlatformPlayer();
    service = MediaKitAudioService(platformPlayer: engine);
    await service.initialize();
  });

  tearDown(() => service.dispose());

  group('a pause pressed while the stream is opening', () {
    test('holds while the engine is still filling its cache', () async {
      final opening = service.playUrl('https://example.com/a.m4a');
      await pumpUntil(
        () => engine.opened,
        reason: 'playUrl has handed the medium to the engine',
      );
      engine
        ..emitDuration(const Duration(minutes: 3))
        ..emitBuffering(true);
      await pumpUntil(
        () => service.processingState == FmpAudioProcessingState.buffering,
        reason: 'the engine is still filling its cache after open()',
      );

      // 媒體鍵按兩下：第一下把 `play: false` 開的流叫起來，第二下暫停。
      await service.togglePlayPause();
      await service.togglePlayPause();
      engine.emitBuffering(false);
      await opening;

      expect(engine.state.playing, isFalse);
      expect(service.isPlaying, isFalse);
    });

    test('holds when it lands before the duration arrives', () async {
      final opening = service.playUrl('https://example.com/a.m4a');
      await pumpUntil(
        () => engine.opened,
        reason: 'playUrl has handed the medium to the engine',
      );

      // 還在等時長，`_ensurePlayback` 根本還沒開始。
      await service.togglePlayPause();
      await service.togglePlayPause();
      engine.emitDuration(const Duration(minutes: 3));
      await opening;

      expect(engine.state.playing, isFalse);
      expect(service.isPlaying, isFalse);
    });

    test('an untouched open still starts playing', () async {
      final opening = service.playUrl('https://example.com/a.m4a');
      await pumpUntil(
        () => engine.opened,
        reason: 'playUrl has handed the medium to the engine',
      );
      engine.emitDuration(const Duration(minutes: 3));
      await opening;

      expect(engine.state.playing, isTrue);
    });
  });

  group('processing state while playing', () {
    test('mpv buffering mid-playback reports buffering, not ready', () async {
      engine
        ..emitDuration(const Duration(minutes: 3))
        ..emitPlaying(true);
      await pumpUntil(
        () => service.processingState == FmpAudioProcessingState.ready,
        reason: 'playing with a known duration is ready',
      );

      // mpv 的 `paused-for-cache`：還在「播放」，但沒有聲音。
      engine.emitBuffering(true);
      await pumpUntil(
        () => service.processingState == FmpAudioProcessingState.buffering,
        reason: 'the cache ran dry while playing',
      );
      expect(service.isPlaying, isTrue);

      engine.emitBuffering(false);
      await pumpUntil(
        () => service.processingState == FmpAudioProcessingState.ready,
        reason: 'the cache refilled',
      );
    });
  });
}

/// 只做開流與播放控制，其餘由測試直接推事件，就像 libmpv 回報屬性變化。
class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer() : super(configuration: const PlayerConfiguration());

  bool opened = false;

  void emitPlaying(bool playing) {
    state = state.copyWith(playing: playing);
    playingController.add(playing);
  }

  void emitBuffering(bool buffering) {
    state = state.copyWith(buffering: buffering);
    bufferingController.add(buffering);
  }

  void emitDuration(Duration duration) {
    state = state.copyWith(duration: duration);
    durationController.add(duration);
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final playlist = playable is Playlist
        ? playable
        : Playlist([playable as Media]);
    state = state.copyWith(playlist: playlist);
    playlistController.add(playlist);
    opened = true;
    if (play) emitPlaying(true);
  }

  @override
  Future<void> stop() async {
    if (state.playing) emitPlaying(false);
  }

  @override
  Future<void> play() async => emitPlaying(true);

  @override
  Future<void> pause() async => emitPlaying(false);

  @override
  Future<void> playOrPause() => state.playing ? pause() : play();
}
