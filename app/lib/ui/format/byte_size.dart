/// 位元組數的顯示文字：`0 B`、`512 KB`、`12.3 MB`（1024 進位，單位各語言相同）。
String formatByteSize(int bytes) {
  const kibi = 1024;
  if (bytes < kibi) return '$bytes B';
  // 先四捨五入再選單位：1023.5 KB 起顯示成 1.0 MB，不是「1024 KB」。
  final kibibytes = (bytes / kibi).round();
  if (kibibytes < kibi) return '$kibibytes KB';
  return '${(bytes / (kibi * kibi)).toStringAsFixed(1)} MB';
}
