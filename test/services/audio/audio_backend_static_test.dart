import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('audio backend typed media dispatch', () {
    test('FmpAudioService exposes typed media methods', () {
      final source = File(
        'lib/services/audio/audio_service.dart',
      ).readAsStringSync();

      expect(source, contains('playMedia(PreparedPlaybackMedia media)'));
      expect(source, contains('setMedia(PreparedPlaybackMedia media)'));
    });

    test('JustAudioService dispatches typed media internally', () {
      final source = File(
        'lib/services/audio/just_audio_service.dart',
      ).readAsStringSync();

      expect(source, contains('Future<Duration?> playMedia('));
      expect(source, contains('Future<Duration?> setMedia('));
      expect(source, contains('LocalPlaybackMedia'));
      expect(source, contains('RemotePlaybackMedia'));
      expect(
        source,
        contains('LocalPlaybackMedia(:final path, :final track) => playFile('),
      );
      expect(
        source,
        contains(
          'RemotePlaybackMedia(:final url, :final headers, :final track) => playUrl(',
        ),
      );
    });

    test('MediaKitAudioService dispatches typed media internally', () {
      final source = File(
        'lib/services/audio/media_kit_audio_service.dart',
      ).readAsStringSync();

      expect(source, contains('Future<Duration?> playMedia('));
      expect(source, contains('Future<Duration?> setMedia('));
      expect(source, contains('LocalPlaybackMedia'));
      expect(source, contains('RemotePlaybackMedia'));
      expect(
        source,
        contains('LocalPlaybackMedia(:final path, :final track) => playFile('),
      );
      expect(
        source,
        contains(
          'RemotePlaybackMedia(:final url, :final headers, :final track) => playUrl(',
        ),
      );
    });
  });

  group('audio backend next-medium capability', () {
    test('FmpAudioService exposes the next-medium pair', () {
      final source = File(
        'lib/services/audio/audio_service.dart',
      ).readAsStringSync();

      expect(source, contains('setNextMedia(PreparedPlaybackMedia? media)'));
      expect(
        source,
        contains('Stream<PreparedPlaybackMedia> get advancedToNext'),
      );
    });

    test('JustAudioService keeps the media inside a playlist', () {
      // 換回單一 `AudioSource.uri` 的話 `setNextMedia` 會變成沒有東西可以接的
      // no-op —— 不會有編譯錯誤，也不會有執行期錯誤，只是再也不 gapless。
      final source = File(
        'lib/services/audio/just_audio_service.dart',
      ).readAsStringSync();

      expect(source, contains('ja.ConcatenatingAudioSource('));
      expect(source, contains('useLazyPreparation: false'));
      expect(source, contains('_player.currentIndexStream.listen'));
    });

    test('following a boundary goes through the shared track-change path', () {
      // `_bufferStarvationTrackKey`（「這首歌已經救過一次」）與 handoff gate 的
      // `currentTrackKey` 都只在 `_updatePlayingTrack` 換曲目時跟上。跟隨路徑
      // 繞過它就會拿上一首的身分去擋新一首的救援與 seek —— 兩者都不會報錯。
      final source = File(
        'lib/services/audio/audio_provider.dart',
      ).readAsStringSync();
      final follow = source.substring(
        source.indexOf('void _onBackendAdvanced('),
        source.indexOf('Future<void> _prefetchAndArmAfterAdvance('),
      );

      expect(
        follow,
        contains('_updatePlayingTrack(track, countsAsNewPlay: true)'),
      );
      expect(follow, contains('_queueManager.moveToNext()'));
      expect(
        follow,
        isNot(contains('_playbackRequestSession')),
        reason: 'there is no new request at a gapless boundary',
      );
      expect(
        follow,
        isNot(contains('_audioService.stop()')),
        reason: 'stopping the backend is exactly what this avoids',
      );
    });

    test('MediaKitAudioService asks mpv to prefetch the next entry', () {
      // mpv 的 `prefetch-playlist` 預設是 `no`，media_kit 從不設它。少了這一行
      // 第二個項目要等交界才開流，gapless 的說法就不成立 —— 同樣不會有任何錯誤。
      final source = File(
        'lib/services/audio/media_kit_audio_service.dart',
      ).readAsStringSync();

      expect(source, contains("setProperty('prefetch-playlist', 'yes')"));
      expect(source, contains('_player.stream.playlist.listen'));
    });
  });
}
