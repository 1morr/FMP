import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 4 Task 1 player source contract', () {
    late String repoRoot;

    setUp(() {
      repoRoot = Directory.current.path;
    });

    String readSource(String relativePath) {
      return File('$repoRoot/$relativePath').readAsStringSync();
    }

    test('audio selector providers file defines shared player selectors', () {
      final selectorFile = File(
        '$repoRoot/lib/providers/audio_player_selectors.dart',
      );

      expect(selectorFile.existsSync(), isTrue);

      final source = selectorFile.readAsStringSync();
      expect(source, contains('playbackSpeedProvider'));
      expect(source, contains('desktopAudioDeviceStateProvider'));
      expect(source, contains('currentStreamMetadataProvider'));
    });

    test('PlayerPage selector does not capture the whole PlayerState object', () {
      final source = readSource('lib/ui/pages/player/player_page.dart');

      expect(source, isNot(contains('state: state')));
    });

    test('PlayerPage uses shared selectors instead of broad controller watch', () {
      final source = readSource('lib/ui/pages/player/player_page.dart');

      expect(source, isNot(contains('ref.watch(audioControllerProvider)')));
      expect(source, contains('ref.watch(playbackSpeedProvider)'));
      expect(source, contains('ref.watch(desktopAudioDeviceStateProvider)'));
      expect(source, contains('ref.watch(currentStreamMetadataProvider)'));
    });

    test('TrackDetailPanel uses shared stream selector without broad watch', () {
      final source = readSource('lib/ui/widgets/track_detail_panel.dart');

      expect(source, isNot(contains('ref.watch(audioControllerProvider)')));
      expect(source, contains('ref.watch(currentStreamMetadataProvider)'));
    });
  });
}
