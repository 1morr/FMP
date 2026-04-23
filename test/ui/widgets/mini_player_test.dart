import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 4 Task 1 mini player selectors', () {
    late String repoRoot;

    setUp(() {
      repoRoot = Directory.current.path;
    });

    String readSource(String relativePath) {
      return File('$repoRoot/$relativePath').readAsStringSync();
    }

    test('MiniPlayer uses shared desktop audio device selector', () {
      final source = readSource('lib/ui/widgets/player/mini_player.dart');

      expect(source, contains('ref.watch(desktopAudioDeviceStateProvider)'));
      expect(
        source,
        isNot(contains("ref.watch(audioControllerProvider.select((s) => s.audioDevices))")),
      );
      expect(
        source,
        isNot(contains("ref.watch(audioControllerProvider.select((s) => s.currentAudioDevice))")),
      );
    });
  });
}
