import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 電台 reload 按鈕搬移契約：
/// Detail Panel 的電台詳情改為資訊取向（無 reload 按鈕，host 行顯示開播時間，
/// 鏡像音樂側 artist 行的發布時間），reload 操作改由 radio mini player 提供。
void main() {
  group('Radio reload button relocation', () {
    String readSource(String relativePath) =>
        File(relativePath).readAsStringSync();

    test('Detail Panel radio content is info-only (no reload button)', () {
      final panel = readSource('lib/ui/widgets/panels/track_detail_panel.dart');

      // 原本內嵌的 reload 按鈕（_buildSyncButton，tooltip reloadLive）已移除。
      expect(panel, isNot(contains('_buildSyncButton')));
      expect(panel, isNot(contains('reloadLive')));
      // host 行改顯示開播時間（鏡像音樂側 artist 行的發布時間）。
      expect(panel, contains('t.radio.startedBroadcast'));
    });

    test('Radio mini player exposes a reload button alongside sync', () {
      final mini = readSource('lib/ui/widgets/radio/radio_mini_player.dart');

      expect(mini, contains('_buildReloadButton'));
      expect(mini, contains('controller.reload()'));
      expect(mini, contains('t.radio.reloadLive'));
      // 既有的 sync 按鈕仍在（跳到直播邊緣）。
      expect(mini, contains('controller.sync()'));
    });
  });
}
