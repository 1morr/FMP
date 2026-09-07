import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/source_ids.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/audio_handler.dart';
import 'package:fmp/services/audio/audio_runtime_platform.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/now_playing_publisher.dart';
import 'package:fmp/services/audio/playback_capabilities.dart';

import '../../support/now_playing.dart';

/// `NowPlayingPublisher` 是 Phase 4 步驟 B 從 `AudioController` 抽出來的第二個
/// 協作者。它負責的是「現在在播什麼、現在能做什麼」的平台分流與擁有權仲裁。
///
/// 這裡的斷言全部走 Android 側，因為 `FmpAudioHandler` 繼承 `BaseAudioHandler`，
/// `playbackState` / `mediaItem` 是真的 `BehaviorSubject`，看得見。
/// **Windows 那半看不見** —— `WindowsSmtcHandler` 沒有 `initialize()` 就 `_smtc
/// == null`，每個方法都早退。真正的 `SMTCWindows` 呼叫需要 Windows 媒體工作
/// 階段，只能靠實機驗收（WinRT 探針），這裡刻意不為了可測而加一層介面。
void main() {
  group('NowPlayingPublisher', () {
    late FmpAudioHandler handler;
    late NowPlayingPublisher publisher;

    setUp(() {
      handler = FmpAudioHandler();
      publisher = testNowPlayingPublisher(
        platform: AudioRuntimePlatform.mobile,
        audioHandler: handler,
      );
    });

    test('music claims every control', () {
      publisher.claim(
        NowPlayingOwner.music,
        commands: _musicCommands(),
        capabilities: PlaybackCapabilities.music,
      );

      final state = handler.playbackState.value;
      expect(state.controls, [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ]);
      expect(
        state.systemActions,
        containsAll([
          MediaAction.seek,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.setRepeatMode,
          MediaAction.setShuffleMode,
        ]),
      );
      expect(handler.onSkipToNext, isNotNull);
      expect(handler.onSetLoopMode, isNotNull);
    });

    test('radio withdraws the controls it cannot serve', () {
      publisher.claim(
        NowPlayingOwner.radio,
        commands: _radioCommands(),
        capabilities: PlaybackCapabilities.liveRadio,
      );

      final state = handler.playbackState.value;
      // issue #40 症狀一：過去這裡會有三顆按鈕，其中兩顆按下去打進 null。
      expect(state.controls, [MediaControl.play]);
      expect(state.systemActions, isEmpty);
      expect(handler.onSkipToNext, isNull);
      expect(handler.onSkipToPrevious, isNull);
      expect(handler.onSeek, isNull);
      expect(handler.onSetLoopMode, isNull);
      expect(handler.onSetShuffleEnabled, isNull);
    });

    test('compact action indices stay unset so android can size them', () {
      publisher.claim(
        NowPlayingOwner.radio,
        commands: _radioCommands(),
        capabilities: PlaybackCapabilities.liveRadio,
      );

      // 寫死 [0,1,2] 時，按鈕縮到 1 顆就越界。留 null 讓 audio_service 的
      // Android 端自己算 [0..min(3, 按鈕數))（AudioService.java:614-617）。
      expect(handler.playbackState.value.androidCompactActionIndices, isNull);
      expect(handler.playbackState.value.controls, hasLength(1));
    });

    test('a claim from music while radio owns it still wins', () {
      publisher.claim(
        NowPlayingOwner.radio,
        commands: _radioCommands(),
        capabilities: PlaybackCapabilities.liveRadio,
      );
      publisher.claim(
        NowPlayingOwner.music,
        commands: _musicCommands(),
        capabilities: PlaybackCapabilities.music,
      );

      expect(publisher.owner, NowPlayingOwner.music);
      expect(handler.playbackState.value.controls, hasLength(3));
    });

    test('publishing from a stale owner is dropped', () {
      publisher.claim(
        NowPlayingOwner.music,
        commands: _musicCommands(),
        capabilities: PlaybackCapabilities.music,
      );
      publisher.claim(
        NowPlayingOwner.radio,
        commands: _radioCommands(),
        capabilities: PlaybackCapabilities.liveRadio,
      );
      publisher.publishRadioStation(NowPlayingOwner.radio, _station());

      // 點歌之後立刻點電台：那個還在解析的音樂請求完成時會走到這裡。
      publisher.publishTrack(NowPlayingOwner.music, _track());

      expect(handler.mediaItem.value?.title, 'Test Station');
      expect(handler.playbackState.value.controls, hasLength(1));
    });

    test('releasing radio restores music without asking anyone', () {
      publisher.claim(
        NowPlayingOwner.music,
        commands: _musicCommands(),
        capabilities: PlaybackCapabilities.music,
      );
      publisher.claim(
        NowPlayingOwner.radio,
        commands: _radioCommands(),
        capabilities: PlaybackCapabilities.liveRadio,
      );

      publisher.release(NowPlayingOwner.radio);

      expect(publisher.owner, NowPlayingOwner.music);
      expect(publisher.capabilities, PlaybackCapabilities.music);
      expect(handler.onSkipToNext, isNotNull);
      expect(handler.playbackState.value.controls, hasLength(3));
    });

    test(
      'releasing radio after music is gone unbinds instead of restoring',
      () {
        publisher.claim(
          NowPlayingOwner.music,
          commands: _musicCommands(),
          capabilities: PlaybackCapabilities.music,
        );
        publisher.claim(
          NowPlayingOwner.radio,
          commands: _radioCommands(),
          capabilities: PlaybackCapabilities.liveRadio,
        );

        // controller 先被釋放（provider 重建），電台之後才停。
        publisher.release(NowPlayingOwner.music);
        publisher.release(NowPlayingOwner.radio);

        expect(publisher.capabilities, PlaybackCapabilities.none);
        expect(handler.onPlay, isNull);
        expect(handler.onSkipToNext, isNull);
      },
    );

    test('releasing music while radio owns it leaves radio alone', () {
      publisher.claim(
        NowPlayingOwner.music,
        commands: _musicCommands(),
        capabilities: PlaybackCapabilities.music,
      );
      publisher.claim(
        NowPlayingOwner.radio,
        commands: _radioCommands(),
        capabilities: PlaybackCapabilities.liveRadio,
      );

      publisher.release(NowPlayingOwner.music);

      expect(publisher.owner, NowPlayingOwner.radio);
      expect(handler.playbackState.value.controls, hasLength(1));
    });

    test('play modes reach the notification', () {
      publisher.claim(
        NowPlayingOwner.music,
        commands: _musicCommands(),
        capabilities: PlaybackCapabilities.music,
      );
      publisher.publishPlayModes(
        NowPlayingOwner.music,
        loopMode: LoopMode.one,
        shuffleEnabled: true,
      );

      expect(
        handler.playbackState.value.repeatMode,
        AudioServiceRepeatMode.one,
      );
      expect(
        handler.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.all,
      );
    });

    test('desktop never touches the android handler', () {
      final desktop = testNowPlayingPublisher(
        platform: AudioRuntimePlatform.desktop,
        audioHandler: handler,
      );

      desktop.claim(
        NowPlayingOwner.music,
        commands: _musicCommands(),
        capabilities: PlaybackCapabilities.music,
      );
      desktop.publishTrack(NowPlayingOwner.music, _track());
      desktop.publishPlaybackState(
        NowPlayingOwner.music,
        isPlaying: true,
        position: const Duration(seconds: 3),
        bufferedPosition: Duration.zero,
        processingState: FmpAudioProcessingState.ready,
      );

      expect(handler.mediaItem.value, isNull);
      expect(handler.playbackState.value.controls, isEmpty);
      expect(handler.onPlay, isNull);
    });
  });

  group('FmpAudioHandler play mode callbacks', () {
    test('repeat and shuffle requests arrive as FMP types', () async {
      final handler = FmpAudioHandler();
      LoopMode? loopMode;
      bool? shuffleEnabled;
      handler
        ..onSetLoopMode = ((mode) async => loopMode = mode)
        ..onSetShuffleEnabled = ((enabled) async => shuffleEnabled = enabled);

      await handler.setRepeatMode(AudioServiceRepeatMode.group);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);

      // group 是 audio_service 的分組循環，FMP 沒有這個概念。
      expect(loopMode, LoopMode.all);
      expect(shuffleEnabled, isTrue);
    });
  });
}

MediaControlCommands _musicCommands() => MediaControlCommands(
  play: () async {},
  pause: () async {},
  stop: () async {},
  skipToNext: () async {},
  skipToPrevious: () async {},
  seek: (_) async {},
  setLoopMode: (_) async {},
  setShuffleEnabled: (_) async {},
);

MediaControlCommands _radioCommands() => MediaControlCommands(
  play: () async {},
  pause: () async {},
  stop: () async {},
);

Track _track() => Track()
  ..sourceId = 'track-1'
  ..sourceType = SourceIds.bilibili
  ..title = 'Test Track';

RadioStation _station() => RadioStation()
  ..url = 'https://live.bilibili.com/1'
  ..title = 'Test Station'
  ..sourceType = SourceIds.bilibili
  ..sourceId = '1';
