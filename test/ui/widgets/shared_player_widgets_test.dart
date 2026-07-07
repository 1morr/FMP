import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 音樂/電台全螢幕播放器共用控制項的靜態契約測試。
///
/// 這兩個頁面原本各自維護逐字相同的音量、音訊裝置、播放/暫停、封面容器實作；
/// 重構後必須統一使用共享元件，避免未來再次漂移。此測試鎖定該去重契約。
void main() {
  group('Shared player widgets (music + radio consistency)', () {
    String readSource(String relativePath) =>
        File(relativePath).readAsStringSync();

    test('shared widget files define the extracted controls', () {
      expect(readSource('lib/ui/widgets/player/compact_volume_control.dart'),
          contains('class CompactVolumeControl'));
      expect(readSource('lib/ui/widgets/player/fmp_audio_device_selector.dart'),
          contains('class FmpAudioDeviceSelector'));
      expect(
          readSource('lib/ui/widgets/player/player_play_pause_button.dart'),
          contains('class PlayerPlayPauseButton'));
      expect(readSource('lib/ui/widgets/player/cover_art_container.dart'),
          contains('class CoverArtContainer'));
    });

    test('device name formatter is owned by the shared selector', () {
      final selector =
          readSource('lib/ui/widgets/player/fmp_audio_device_selector.dart');
      expect(selector, contains('static String formatDeviceName'));
      expect(selector, contains('喇叭'));
    });

    test('PlayerPage delegates duplicated controls to shared widgets', () {
      final player = readSource('lib/ui/pages/player/player_page.dart');

      expect(player, contains('CompactVolumeControl('));
      expect(player, contains('FmpAudioDeviceSelector('));
      expect(player, contains('PlayerPlayPauseButton('));
      expect(player, contains('CoverArtContainer('));

      // 逐字重複的私有實作已移除。
      expect(player, isNot(contains('_buildCompactVolumeControl')));
      expect(player, isNot(contains('_buildFmpAudioDeviceSelector')));
      expect(player, isNot(contains('_buildPlayPauseButton')));
      expect(player, isNot(contains('_formatDeviceName')));
    });

    test('RadioPlayerPage delegates duplicated controls to shared widgets', () {
      final radio = readSource('lib/ui/pages/radio/radio_player_page.dart');

      expect(radio, contains('CompactVolumeControl('));
      expect(radio, contains('FmpAudioDeviceSelector('));
      expect(radio, contains('PlayerPlayPauseButton('));
      expect(radio, contains('CoverArtContainer('));

      expect(radio, isNot(contains('_buildCompactVolumeControl')));
      expect(radio, isNot(contains('_buildFmpAudioDeviceSelector')));
      expect(radio, isNot(contains('_formatDeviceName')));
    });

    test('both fullscreen players use the shared immersive scaffold', () {
      final player = readSource('lib/ui/pages/player/player_page.dart');
      final radio = readSource('lib/ui/pages/radio/radio_player_page.dart');
      final scaffold =
          readSource('lib/ui/widgets/layout/immersive_player_scaffold.dart');

      expect(scaffold, contains('class ImmersivePlayerScaffold'));
      expect(player, contains('ImmersivePlayerScaffold('));
      expect(radio, contains('ImmersivePlayerScaffold('));
      // 兩頁都不再自帶沉浸式骨架私方法（去重契約）。
      expect(player, isNot(contains('_buildImmersivePlayerLayout')));
      expect(radio, isNot(contains('_buildImmersiveRadioLayout')));
    });
  });
}
