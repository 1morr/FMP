/// 时长格式化工具类
class DurationFormatter {
  DurationFormatter._();

  /// 格式化毫秒为 "mm:ss" 或 "h:mm:ss"
  static String formatMs(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 格式化 Duration 为 "X 小时 Y 分钟"
  static String formatLong(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '$hours 小时 $minutes 分钟';
    }
    return '$minutes 分钟';
  }

  /// 格式化秒数为 "mm:ss"
  static String formatSeconds(int seconds) {
    return formatMs(seconds * 1000);
  }
}
