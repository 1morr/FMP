/// 串流（`GLOSSARY.md`）：插件為一首曲目解析出的音訊網址，可以直接播放，
/// 會過期。類別不叫 `Stream`，免得和 `dart:async` 的 `Stream` 撞名。
///
/// 欄位命名參考 Spotube 插件的音訊來源（`url`、`codec`、`bitrate`）。
class AudioStream {
  const AudioStream({
    required this.url,
    this.headers = const {},
    this.expiresAt,
    this.codec,
    this.bitrate,
  });

  /// 簽名過的網址：顯示與寫 log 前要經過遮蔽函式。
  final Uri url;

  /// 播放時請求 [url] 要帶的 header。
  final Map<String, String> headers;

  /// 網址失效的時間（UTC）；插件不知道時是 null。
  final DateTime? expiresAt;

  /// RFC 6381 的 codec 字串，例如 AAC-LC 的 `mp4a.40.2`。
  final String? codec;

  /// 位元率（bit/s）。
  final int? bitrate;

  @override
  bool operator ==(Object other) =>
      other is AudioStream &&
      other.url == url &&
      _sameHeaders(other.headers, headers) &&
      other.expiresAt == expiresAt &&
      other.codec == codec &&
      other.bitrate == bitrate;

  static bool _sameHeaders(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    url,
    Object.hashAllUnordered(headers.entries.map((e) => (e.key, e.value))),
    expiresAt,
    codec,
    bitrate,
  );

  /// 不印網址與 header：網址是簽名過的，這裡不知道呼叫端會不會先遮。
  @override
  String toString() => 'AudioStream(expiresAt: $expiresAt, $codec, $bitrate)';
}
