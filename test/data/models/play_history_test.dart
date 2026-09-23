import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_history.dart';

void main() {
  test('formattedDuration matches the rest of the app', () {
    // 以前這裡手寫補零，播放紀錄顯示 `03:05`，其他頁面顯示 `3:05`。
    expect((PlayHistory()..durationMs = 185000).formattedDuration, '3:05');
    expect((PlayHistory()..durationMs = 3725000).formattedDuration, '1:02:05');
    expect(PlayHistory().formattedDuration, '--:--');
  });
}
