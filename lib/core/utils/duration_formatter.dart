import 'package:fmp/i18n/strings.g.dart';

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
      return t.time.hoursMinutes(hours: hours, minutes: minutes);
    }
    return t.time.minutesOnly(minutes: minutes);
  }

  /// 格式化秒数为 "mm:ss"
  static String formatSeconds(int seconds) {
    return formatMs(seconds * 1000);
  }

  /// 解析冒號時長字串（如 "4:39" 或 "1:23:45"）為毫秒；無法解析時回傳 0。
  static int parseColonDurationToMs(String? text) {
    if (text == null || text.isEmpty) return 0;
    try {
      final parts = text.split(':').map(int.parse).toList();
      if (parts.length == 2) {
        return (parts[0] * 60 + parts[1]) * 1000;
      } else if (parts.length == 3) {
        return (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000;
      }
    } catch (_) {}
    return 0;
  }
}
