import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 電台播放器頁面「跳到最新 / 重新載入」控制列與 AppBar 資訊入口的靜態契約測試。
void main() {
  group('RadioPlayerPage live controls', () {
    String readSource(String relativePath) =>
        File(relativePath).readAsStringSync();

    test('exposes jump-to-latest and reload as control-row buttons', () {
      final radio = readSource('lib/ui/pages/radio/radio_player_page.dart');

      // 跳到最新：Icons.sync -> controller.sync()（seekToLive，失敗則重連）。
      expect(radio, contains('Icons.sync'));
      expect(radio, contains('controller.sync()'));
      // 重新載入：Icons.refresh -> controller.reload()（無條件重連）。
      expect(radio, contains('Icons.refresh'));
      expect(radio, contains('controller.reload()'));
      // 兩顆按鈕共用同一停用條件（與既有 reload 選單、mini sync 一致）。
      expect(
        radio,
        contains(
          'state.isBuffering || state.isLoading || !state.isPlaying',
        ),
      );
    });

    test('control row keeps play/pause via the shared button', () {
      final radio = readSource('lib/ui/pages/radio/radio_player_page.dart');
      expect(radio, contains('PlayerPlayPauseButton('));
    });

    test('promotes live info to an AppBar icon and drops the overflow menu', () {
      final radio = readSource('lib/ui/pages/radio/radio_player_page.dart');

      expect(radio, contains('Icons.info_outline'));
      expect(radio, contains('tooltip: t.radio.info'));

      // reload / info 不再藏在 overflow 選單。
      expect(radio, isNot(contains("value: 'reload'")));
      expect(radio, isNot(contains("value: 'info'")));
    });
  });
}
