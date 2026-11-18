import 'dart:convert';
import 'dart:typed_data';

import 'package:fmp/domain/audio_stream.dart';

import 'fragment_template.dart';

/// 像 B 站音訊軌的單檔 fragmented MP4（ftyp、moov、一個 sidx、每 5 秒一段
/// moof＋mdat）：把 `fragmentTemplateBase64` 的那一段複製 `fragments` 次，
/// 改寫每段的序號與起始時間，再補上指到它們的 sidx。
///
/// 每段約 11 KB。
class FragmentedMp4 {
  factory FragmentedMp4({required int fragments}) {
    final template = base64Decode(fragmentTemplateBase64);
    final boxes = _topLevelBoxes(template);
    final init = BytesBuilder(copy: false);
    late Uint8List fragment;
    late int timescale;
    late int fragmentTicks;
    for (final (kind, start, end) in boxes) {
      final box = Uint8List.sublistView(template, start, end);
      switch (kind) {
        case 'ftyp' || 'moov':
          init.add(box);
        case 'sidx':
          final data = ByteData.sublistView(box);
          timescale = data.getUint32(16);
          // 第一筆 reference 的 subsegment_duration（版本 1：從 44 起）。
          fragmentTicks = data.getUint32(box[8] == 0 ? 36 : 44);
        case 'moof':
          final mdatEnd = boxes.firstWhere((b) => b.$2 == end).$3;
          fragment = Uint8List.fromList(template.sublist(start, mdatEnd));
      }
    }
    final initBytes = init.takeBytes();
    final sequence = _find(fragment, ['moof', 'mfhd']) + 12;
    final tfdt = _find(fragment, ['moof', 'traf', 'tfdt']);
    final tfdtVersion = fragment[tfdt + 8];
    final index = sidxBox(
      timescale: timescale,
      sizes: List.filled(fragments, fragment.length),
      durations: List.filled(fragments, fragmentTicks),
    );
    final out = BytesBuilder(copy: false)
      ..add(initBytes)
      ..add(index);
    final data = ByteData.sublistView(fragment);
    for (var i = 0; i < fragments; i++) {
      data.setUint32(sequence, i + 1);
      if (tfdtVersion == 1) {
        data.setUint64(tfdt + 12, i * fragmentTicks);
      } else {
        data.setUint32(tfdt + 12, i * fragmentTicks);
      }
      out.add(Uint8List.fromList(fragment));
    }
    return FragmentedMp4._(
      out.takeBytes(),
      SegmentBase(
        initialization: ByteRange(0, initBytes.length - 1),
        index: ByteRange(initBytes.length, initBytes.length + index.length - 1),
      ),
      Duration(microseconds: fragments * fragmentTicks * 1000000 ~/ timescale),
    );
  }

  FragmentedMp4._(this.bytes, this.segmentBase, this.duration);

  final Uint8List bytes;

  /// init 與 sidx 的位置，像插件從 B 站 playurl 讀到的。
  final SegmentBase segmentBase;

  final Duration duration;
}

/// 一個 sidx box（ISO/IEC 14496-12 §8.16.3）：[sizes] 與 [durations] 一一
/// 對應；[referenceType] 1 表示指到下一層 sidx。
Uint8List sidxBox({
  int version = 1,
  int timescale = 48000,
  int firstOffset = 0,
  required List<int> sizes,
  required List<int> durations,
  int referenceType = 0,
}) {
  final body = BytesBuilder()
    ..add([version, 0, 0, 0])
    ..add(_u32(1)) // reference_ID
    ..add(_u32(timescale));
  if (version == 0) {
    body
      ..add(_u32(0))
      ..add(_u32(firstOffset));
  } else {
    body
      ..add(_u64(0))
      ..add(_u64(firstOffset));
  }
  body.add([0, 0, sizes.length >> 8, sizes.length & 0xff]);
  for (var i = 0; i < sizes.length; i++) {
    body
      ..add(_u32(referenceType << 31 | sizes[i]))
      ..add(_u32(durations[i]))
      ..add(_u32(0x90000000)); // starts_with_SAP、SAP_type 1
  }
  final bytes = body.toBytes();
  return (BytesBuilder()
        ..add(_u32(bytes.length + 8))
        ..add('sidx'.codeUnits)
        ..add(bytes))
      .toBytes();
}

List<int> _u32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();
List<int> _u64(int v) => (ByteData(8)..setUint64(0, v)).buffer.asUint8List();

/// 頂層 box 的（類型、開頭、結尾）。
List<(String, int, int)> _topLevelBoxes(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final boxes = <(String, int, int)>[];
  for (var at = 0; at + 8 <= bytes.length;) {
    final size = data.getUint32(at);
    boxes.add((String.fromCharCodes(bytes, at + 4, at + 8), at, at + size));
    at += size;
  }
  return boxes;
}

/// 沿 [path] 往下找子 box，回傳它在 [bytes] 的開頭。
int _find(Uint8List bytes, List<String> path, [int start = 0, int? end]) {
  final data = ByteData.sublistView(bytes);
  for (var at = start; at + 8 <= (end ?? bytes.length);) {
    final size = data.getUint32(at);
    if (String.fromCharCodes(bytes, at + 4, at + 8) == path.first) {
      return path.length == 1
          ? at
          : _find(bytes, path.sublist(1), at + 8, at + size);
    }
    at += size;
  }
  throw StateError('no ${path.first} box in the fragment template');
}
