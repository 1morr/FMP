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
    this.segmentBase,
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

  /// 串流是單檔 fragmented MP4 時，它的 init 與 sidx 在哪（ADR 0040）；插件
  /// 不知道時是 null。
  final SegmentBase? segmentBase;

  @override
  bool operator ==(Object other) =>
      other is AudioStream &&
      other.url == url &&
      _sameHeaders(other.headers, headers) &&
      other.expiresAt == expiresAt &&
      other.codec == codec &&
      other.bitrate == bitrate &&
      other.segmentBase == segmentBase;

  static bool _sameHeaders(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    url,
    Object.hashAllUnordered(headers.entries.map((e) => (e.key, e.value))),
    expiresAt,
    codec,
    bitrate,
    segmentBase,
  );

  /// 不印網址與 header：網址是簽名過的，這裡不知道呼叫端會不會先遮。
  @override
  String toString() => 'AudioStream(expiresAt: $expiresAt, $codec, $bitrate)';
}

/// 單檔 fragmented MP4 的索引位置，命名照 MPEG-DASH 的 `SegmentBase`
/// （`Initialization@range`、`@indexRange`；ADR 0040）。
class SegmentBase {
  const SegmentBase({required this.initialization, required this.index});

  /// ftyp 與 moov 所在的位元組範圍。
  final ByteRange initialization;

  /// sidx 所在的位元組範圍。
  final ByteRange index;

  @override
  bool operator ==(Object other) =>
      other is SegmentBase &&
      other.initialization == initialization &&
      other.index == index;

  @override
  int get hashCode => Object.hash(initialization, index);

  @override
  String toString() => 'SegmentBase($initialization, index: $index)';
}

/// 含頭尾的位元組範圍，同 HTTP 的 `Range: bytes=<first>-<last>`。
class ByteRange {
  const ByteRange(this.first, this.last)
    : assert(first >= 0 && last >= first, 'not a byte range: $first-$last');

  /// `"<first>-<last>"`（DASH 與 HTTP 的寫法）。格式不對或範圍不合理時丟
  /// [FormatException]。
  factory ByteRange.parse(String text) {
    final match = RegExp(r'^(\d+)-(\d+)$').firstMatch(text);
    final first = int.tryParse(match?[1] ?? '');
    final last = int.tryParse(match?[2] ?? '');
    if (first == null || last == null || last < first) {
      throw FormatException('not a byte range: $text');
    }
    return ByteRange(first, last);
  }

  final int first;
  final int last;

  int get length => last - first + 1;

  @override
  bool operator ==(Object other) =>
      other is ByteRange && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => '$first-$last';
}
