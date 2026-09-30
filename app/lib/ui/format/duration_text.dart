/// 曲目時長與播放位置的文字：不到一小時是 `m:ss`，否則 `h:mm:ss`。
///
/// 不經翻譯：三種介面語言的播放器都寫成這樣（CLDR 沒有「時長」的格式）。
String formatDuration(Duration duration) {
  final totalSeconds = duration.isNegative ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = totalSeconds ~/ 60 % 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}
