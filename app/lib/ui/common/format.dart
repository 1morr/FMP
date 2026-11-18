/// `m:ss`，一小時以上 `h:mm:ss`。
String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final seconds = two(d.inSeconds % 60);
  return d.inHours > 0
      ? '${d.inHours}:${two(d.inMinutes % 60)}:$seconds'
      : '${d.inMinutes}:$seconds';
}

/// 播放數的短寫法，照 B 站與 YouTube 在各語言的寫法：中文以萬、億為單位
/// （[chineseUnits] 給這兩個字，例如 8.4萬、1.2億），英文（null）用 K、M、B；
/// 小數最多一位、無條件捨去，`.0` 省略。
String formatCount(int count, {(String, String)? chineseUnits}) {
  String short(double value, String unit) {
    final tenths = (value * 10).floor();
    final text = tenths % 10 == 0 || value >= 100
        ? '${value.floor()}'
        : (tenths / 10).toStringAsFixed(1);
    return '$text$unit';
  }

  if (chineseUnits case (final wan, final yi)) {
    if (count < 10000) return '$count';
    if (count < 100000000) return short(count / 10000, wan);
    return short(count / 100000000, yi);
  }
  if (count < 1000) return '$count';
  if (count < 1000000) return short(count / 1000, 'K');
  if (count < 1000000000) return short(count / 1000000, 'M');
  return short(count / 1000000000, 'B');
}
