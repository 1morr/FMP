import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/source_ids.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/services/audio/audio_handler.dart';
import 'package:fmp/services/audio/audio_runtime_platform.dart';
import 'package:fmp/services/audio/now_playing_publisher.dart';
import 'package:fmp/services/audio/playback_capabilities.dart';
import 'package:fmp/services/radio/radio_controller.dart';
import 'package:fmp/services/radio/radio_refresh_service.dart';
import 'package:fmp/services/radio/radio_source.dart';

import '../../support/fakes/fake_audio_service.dart';
import '../../support/now_playing.dart';
import '../../support/riverpod_test_ref.dart';

/// issue #40 症狀一的回歸測試。
///
/// bug 住在 `RadioController`：它過去只把 `onSkipToNext` / `onSkipToPrevious`
/// 設成 null，卻沒有辦法收回已經宣告出去的按鈕，所以系統照樣畫出上／下一首，
/// 按下去打進 null。這裡測的是它真的傳了 [PlaybackCapabilities.liveRadio]，
/// 以及停止之後音樂的能力有回來。
void main() {
  setUpAll(() {
    RadioRefreshService.instance = RadioRefreshService(
      radioSource: _LiveRadioSource(),
      refreshInterval: const Duration(days: 1),
    );
  });

  tearDownAll(() {
    RadioRefreshService.instance.dispose();
  });

  test('radio withdraws skip controls and hands them back on stop', () async {
    final handler = FmpAudioHandler();
    final publisher = testNowPlayingPublisher(
      platform: AudioRuntimePlatform.mobile,
      audioHandler: handler,
    );
    final handle = createTestRef(overrides: [
      nowPlayingPublisherProvider.overrideWithValue(publisher),
    ]);
    addTearDown(handle.dispose);

    // 音樂先接管，就像 app 啟動之後那樣。
    publisher.claim(
      NowPlayingOwner.music,
      commands: MediaControlCommands(
        play: () async {},
        pause: () async {},
        stop: () async {},
        skipToNext: () async {},
        skipToPrevious: () async {},
        seek: (_) async {},
        setLoopMode: (_) async {},
        setShuffleEnabled: (_) async {},
      ),
      capabilities: PlaybackCapabilities.music,
    );
    expect(handler.playbackState.value.controls, hasLength(3));

    final controller = RadioController(
      handle.ref,
      _FakeRadioRepository(),
      _LiveRadioSource(),
      FakeAudioService(),
    );
    addTearDown(controller.dispose);

    await controller.play(_station());

    expect(publisher.owner, NowPlayingOwner.radio);
    expect(publisher.capabilities, PlaybackCapabilities.liveRadio);
    expect(handler.playbackState.value.controls, hasLength(1));
    expect(handler.playbackState.value.systemActions, isEmpty);
    expect(handler.onSkipToNext, isNull);
    expect(handler.onSkipToPrevious, isNull);
    expect(handler.mediaItem.value?.title, 'Test Station');

    await controller.stop();

    expect(publisher.owner, NowPlayingOwner.music);
    expect(publisher.capabilities, PlaybackCapabilities.music);
    expect(handler.playbackState.value.controls, hasLength(3));
    expect(handler.onSkipToNext, isNotNull);
  });
}


class _LiveRadioSource extends RadioSource {
  @override
  Future<LiveStreamInfo> getStreamUrl(RadioStation station) async {
    return const LiveStreamInfo(url: 'https://example.com/live.flv');
  }

  @override
  Future<LiveRoomInfo> getLiveInfo(RadioStation station) async {
    return LiveRoomInfo(title: station.title, isLive: true);
  }

  @override
  Future<int?> getHighEnergyUserCount(RadioStation station) async => null;
}

class _FakeRadioRepository extends Fake implements RadioRepository {
  @override
  Future<List<RadioStation>> getAll() async => [];

  @override
  Stream<List<RadioStation>> watchAll() => const Stream.empty();

  @override
  Future<void> updateLastPlayed(int id) async {}
}

RadioStation _station() => RadioStation()
  ..id = 1
  ..url = 'https://live.bilibili.com/1'
  ..title = 'Test Station'
  ..sourceType = SourceIds.bilibili
  ..sourceId = '1';
