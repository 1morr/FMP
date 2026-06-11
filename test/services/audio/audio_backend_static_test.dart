import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('audio backend typed media dispatch', () {
    test('FmpAudioService exposes typed media methods', () {
      final source = File('lib/services/audio/audio_service.dart')
          .readAsStringSync();

      expect(source, contains('playMedia(PreparedPlaybackMedia media)'));
      expect(source, contains('setMedia(PreparedPlaybackMedia media)'));
    });

    test('JustAudioService dispatches typed media internally', () {
      final source = File('lib/services/audio/just_audio_service.dart')
          .readAsStringSync();

      expect(source, contains('Future<Duration?> playMedia('));
      expect(source, contains('Future<Duration?> setMedia('));
      expect(source, contains('LocalPlaybackMedia'));
      expect(source, contains('RemotePlaybackMedia'));
      expect(source, contains('playFile(path, track: track)'));
      expect(source,
          contains('playUrl(url.toString(), headers: headers, track: track)'));
    });

    test('MediaKitAudioService dispatches typed media internally', () {
      final source = File('lib/services/audio/media_kit_audio_service.dart')
          .readAsStringSync();

      expect(source, contains('Future<Duration?> playMedia('));
      expect(source, contains('Future<Duration?> setMedia('));
      expect(source, contains('LocalPlaybackMedia'));
      expect(source, contains('RemotePlaybackMedia'));
      expect(source, contains('playFile(path, track: track)'));
      expect(source,
          contains('playUrl(url.toString(), headers: headers, track: track)'));
    });
  });
}
