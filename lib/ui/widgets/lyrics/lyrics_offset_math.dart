/// 純邏輯：歌詞偏移量（offset）的計算與格式化（C1d）。
///
/// 從 `lyrics_window.dart` 的 `_calibrateOffsetToLine` 校正計算與 `_formatOffset`
/// 抽出，讓這兩段無副作用數學可單獨測試。IPC 編排（`_channel.invokeMethod` +
/// `setState`）仍留在 State，屬 C1f bridge 範疇；本類別只負責數值推導與呈現字串。
class LyricsOffsetMath {
  LyricsOffsetMath._();

  /// 把 [lineTimestamp] 校正到當前播放位置所需的偏移量（毫秒）。
  ///
  /// 即「讓該行剛好對齊現在」的 offset = 行時間戳 - 當前位置。caller 收到後
  /// 經 `_updateOffset` 送出 adjustOffset IPC 並鏡像到本地狀態。
  static int calibrationOffsetForLine(Duration lineTimestamp, int positionMs) {
    return lineTimestamp.inMilliseconds - positionMs;
  }

  /// 把毫秒偏移格式化為 '+1.2s' / '-0.5s' / '0.0s'（offset bar 顯示用）。
  static String format(int offsetMs) {
    if (offsetMs == 0) return '0.0s';
    final seconds = offsetMs / 1000;
    return '${seconds >= 0 ? '+' : ''}${seconds.toStringAsFixed(1)}s';
  }
}
