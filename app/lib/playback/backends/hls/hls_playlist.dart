import 'dart:typed_data';

import 'package:fmp/domain/audio_stream.dart';

/// 單檔 fragmented MP4 裡的一段媒體（moof＋mdat）。
class MediaSegment {
  const MediaSegment(this.range, this.duration);

  final ByteRange range;
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is MediaSegment &&
      other.range == range &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(range, duration);

  @override
  String toString() => 'MediaSegment($range, $duration)';
}

/// 讀 sidx box（ISO/IEC 14496-12 §8.16.3），列出它指到的每一段媒體。
/// [bytes] 是整個 sidx box，[indexOffset] 是它在檔案裡的位置：第一段從
/// sidx 結尾加 `first_offset` 開始。
///
/// 只收直接指到媒體的索引（`reference_type` 0）；指到下一層 sidx 的、
/// 截斷的或不是 sidx 的都丟 [FormatException]。
List<MediaSegment> readSegmentIndex(
  Uint8List bytes, {
  required int indexOffset,
}) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 8) throw const FormatException('index is too short');
  final size = data.getUint32(0);
  if (String.fromCharCodes(bytes, 4, 8) != 'sidx') {
    throw const FormatException('index is not a sidx box');
  }
  if (size < 8 || size > bytes.length) {
    throw const FormatException('sidx box is truncated');
  }
  var p = 8;
  int read32() {
    if (p + 4 > size) throw const FormatException('sidx box is truncated');
    final v = data.getUint32(p);
    p += 4;
    return v;
  }

  int read64() => read32() << 32 | read32();

  final version = read32() >> 24;
  read32(); // reference_ID
  final timescale = read32();
  if (timescale == 0) throw const FormatException('sidx timescale is zero');
  final int firstOffset;
  if (version == 0) {
    read32(); // earliest_presentation_time
    firstOffset = read32();
  } else {
    read64();
    firstOffset = read64();
  }
  final count = read32() & 0xffff; // reserved(16) + reference_count(16)
  if (count == 0) throw const FormatException('sidx lists no segments');
  var offset = indexOffset + size + firstOffset;
  return [
    for (var i = 0; i < count; i++)
      () {
        final reference = read32();
        final duration = read32();
        read32(); // SAP
        if (reference >> 31 != 0) {
          throw const FormatException('sidx points to another sidx');
        }
        final length = reference & 0x7fffffff;
        final segment = MediaSegment(
          ByteRange(offset, offset + length - 1),
          Duration(microseconds: duration * 1000000 ~/ timescale),
        );
        offset += length;
        return segment;
      }(),
  ];
}

/// 把單檔 fragmented MP4 寫成 VOD 的 HLS 清單（RFC 8216）：每段一個
/// `EXT-X-BYTERANGE`，init 用 `EXT-X-MAP`，全部指同一個 [url]（ADR 0040）。
String hlsPlaylist({
  required Uri url,
  required ByteRange initialization,
  required List<MediaSegment> segments,
}) {
  final longest = segments
      .map((s) => s.duration.inMicroseconds)
      .fold(0, (a, b) => a > b ? a : b);
  final out = StringBuffer()
    ..writeln('#EXTM3U')
    // EXT-X-MAP 用在不是只有 I-frame 的清單要第 6 版，fMP4 寫 7（§4.3.2.5、§7）。
    ..writeln('#EXT-X-VERSION:7')
    ..writeln('#EXT-X-TARGETDURATION:${(longest / 1000000).round()}')
    ..writeln('#EXT-X-PLAYLIST-TYPE:VOD')
    ..writeln('#EXT-X-INDEPENDENT-SEGMENTS')
    ..writeln(
      '#EXT-X-MAP:URI="$url",'
      'BYTERANGE="${initialization.length}@${initialization.first}"',
    );
  for (final s in segments) {
    out
      ..writeln(
        '#EXTINF:${(s.duration.inMicroseconds / 1000000).toStringAsFixed(6)},',
      )
      ..writeln('#EXT-X-BYTERANGE:${s.range.length}@${s.range.first}')
      ..writeln('$url');
  }
  out.writeln('#EXT-X-ENDLIST');
  return out.toString();
}
