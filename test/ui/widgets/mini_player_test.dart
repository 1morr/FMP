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

    test('both mini players delegate desktop controls to shared widgets', () {
      final music = readSource('lib/ui/widgets/player/mini_player.dart');
      final radio = readSource('lib/ui/widgets/radio/radio_mini_player.dart');
      final shared =
          readSource('lib/ui/widgets/player/mini_player_volume_control.dart');

      expect(shared, contains('class MiniPlayerVolumeControl'));

      for (final source in [music, radio]) {
        expect(source, contains('MiniPlayerVolumeControl('));
        expect(source, contains('FmpAudioDeviceSelector('));
        expect(source, contains('desktopAudioDeviceStateProvider'));
        // 逐字重複的私有實作已移除。
        expect(source, isNot(contains('_buildCompactVolumeControl')));
        expect(source, isNot(contains('_buildFullVolumeControl')));
        expect(source, isNot(contains('_buildVolumeControl')));
        expect(source, isNot(contains('_buildFmpAudioDeviceSelector')));
        expect(source, isNot(contains('_formatDeviceName')));
      }
    });
  });
}
