/// 音訊層三條「介面收窄」規則，只有讀源碼驗得到。
///
/// 三條原本各自藏在一支行為測試裡。共同點是：把收窄的介面放寬回去不會有編譯
/// 錯誤，也不會有任何測試變紅 —— 只會讓上一次拆分想擋掉的東西悄悄回來。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('audio seam static rules', () {
    test('PlayerState declares none of the queue fields', () {
      // 這兩個型別曾經各存一份同樣的 12 個欄位，靠 controller 每次逐欄位抄過去
      // 維持一致。抄漏一個就是一個看不見的 bug，而消費端會因為問了不同的
      // provider 拿到不同的答案。長回來的話這條會先掛。
      final source = File(
        'lib/services/audio/player_state.dart',
      ).readAsStringSync();

      for (final field in const [
        'queue',
        'upcomingTracks',
        'currentIndex',
        'queueTrack',
        'canPlayPrevious',
        'canPlayNext',
        'isShuffleEnabled',
        'loopMode',
        'queueVersion',
        'isMixMode',
        'mixTitle',
        'isLoadingMoreMix',
      ]) {
        expect(
          source.contains(
            RegExp(
              '^'
              r'\s+final .* '
              '$field;',
              multiLine: true,
            ),
          ),
          isFalse,
          reason: 'PlayerState.$field belongs to QueueState',
        );
      }
    });

    test(
      'PlaybackRequestStreamAccess exposes only session-level operations',
      () {
        final source = File(
          'lib/services/audio/audio_stream_manager.dart',
        ).readAsStringSync();
        final interfaceMatch = RegExp(
          r'abstract class PlaybackRequestStreamAccess \{([\s\S]*?)\n\}',
        ).firstMatch(source);

        expect(interfaceMatch, isNotNull);
        final interfaceBody = interfaceMatch!.group(1)!;

        expect(interfaceBody, contains('selectPlayback'));
        expect(interfaceBody, contains('selectFallbackPlayback'));
        expect(interfaceBody, contains('prefetchTrack'));
        expect(interfaceBody, isNot(contains('ensureAudioStream')));
        expect(interfaceBody, isNot(contains('prepareNetworkPlayback')));
      },
    );

    test('PlaybackRequestSession opens typed media, not raw URL methods', () {
      final source = File(
        'lib/services/audio/playback_request_session.dart',
      ).readAsStringSync();

      expect(source, contains('_audioService.playMedia('));
      expect(source, contains('_audioService.setMedia('));
      expect(source, isNot(contains('_audioService.playUrl(')));
      expect(source, isNot(contains('_audioService.setUrl(')));
      expect(source, isNot(contains('_audioService.playFile(')));
      expect(source, isNot(contains('_audioService.setFile(')));
      expect(source, isNot(contains('headers: selection.headers')));
      expect(source, isNot(contains('headers: networkRequest.headers')));
    });

    test('production modules depend on purpose-specific auth interfaces', () {
      final authContextSource = File(
        'lib/services/account/source_auth_context.dart',
      ).readAsStringSync();
      final streamResolutionSource = File(
        'lib/services/audio/stream_resolution_service.dart',
      ).readAsStringSync();
      final audioStreamManagerSource = File(
        'lib/services/audio/audio_stream_manager.dart',
      ).readAsStringSync();
      final downloadServiceSource = File(
        'lib/services/download/download_service.dart',
      ).readAsStringSync();
      final importServiceSource = File(
        'lib/services/import/import_service.dart',
      ).readAsStringSync();
      final trackDetailSource = File(
        'lib/providers/library/track_detail_provider.dart',
      ).readAsStringSync();

      expect(
        authContextSource,
        contains('abstract interface class SourcePlaybackAuthContext'),
      );
      expect(
        authContextSource,
        contains('abstract interface class PlaybackMediaRequestContext'),
      );
      expect(
        authContextSource,
        contains('abstract interface class DownloadSourceAuthContext'),
      );
      expect(
        authContextSource,
        contains('abstract interface class PlaylistAuthContext'),
      );
      expect(
        streamResolutionSource,
        contains('required SourcePlaybackAuthContext sourceAuthContext'),
      );
      expect(
        audioStreamManagerSource,
        contains('required PlaybackMediaRequestContext sourceAuthContext'),
      );
      expect(
        downloadServiceSource,
        contains('DownloadSourceAuthContext? sourceAuthContext'),
      );
      expect(
        importServiceSource,
        contains('final PlaylistAuthContext _sourceAuthContext'),
      );
      expect(
        trackDetailSource,
        contains('late SourcePlaybackAuthContext _sourceAuthContext'),
      );
    });
  });
}
