import '../../i18n/strings.g.dart';

/// 格式化相對時間：N 天/小時/分鐘前，未滿一分鐘顯示「剛剛」。
///
/// Detail Panel 與直播資訊彈窗共用（原本各自私有重複實作）。
String formatRelativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);

  if (diff.inDays > 0) {
    return t.radio.daysAgo(n: diff.inDays);
  } else if (diff.inHours > 0) {
    return t.radio.hoursAgo(n: diff.inHours);
  } else if (diff.inMinutes > 0) {
    return t.radio.minutesAgo(n: diff.inMinutes);
  } else {
    return t.radio.justNow;
  }
}
