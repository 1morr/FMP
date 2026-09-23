/// 兩個真後端的 gapless 前置條件，只有源碼層面驗得到。
///
/// 這裡刻意只剩 mpv 那一條。just_audio 那一條（媒體要放在播放清單裡）是
/// 子字串比對，換個寫法就繞過，已改成 `_setSingleSource` 旁的註解。原本還斷言 `playMedia` / `setMedia` / `setNextMedia` 的
/// 方法簽名與 `LocalPlaybackMedia` / `RemotePlaybackMedia` 的 pattern 分派 ——
/// 那些拿掉就編不過，測試沒有加任何保障；跟隨路徑的斷言則由
/// `audio_controller_next_medium_test.dart` 用行為蓋掉（佇列只前進一步、不發
/// 新的播放請求、不呼叫 stop）。
///
/// 剩下的這條不一樣：拿掉之後既不會編譯錯誤也不會執行期錯誤，只是靜靜地不再
/// gapless，而真後端的行為只有實機驗得到。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('audio backend gapless preconditions', () {
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
