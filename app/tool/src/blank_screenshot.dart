import 'dart:io';
import 'dart:typed_data';

/// [dir] 裡每張截圖是不是幾乎同一色（[blankScreenshotReason]）；回傳不行的那
/// 幾張與原因，讀不懂的也算。
List<String> blankScreenshots(Directory dir) {
  final shots =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in shots)
      if (_blank(file) case final reason?)
        '${file.uri.pathSegments.last}: $reason',
  ];
}

String? _blank(File png) {
  try {
    return blankScreenshotReason(png.readAsBytesSync());
  } on FormatException catch (e) {
    return 'unreadable PNG (${e.message})';
  }
}

/// 實跑的截圖是不是一整張幾乎同一色（例如 `winpc` 螢幕睡著時 `PrintWindow`
/// 截到的白圖，票 06b）：是的話回傳說明，否則回傳 null。
///
/// 兩種情況都算：整張不到 [minColours] 種顏色（白圖外圍一圈黑框只有 2 種，
/// 正常的畫面有文字的反鋸齒，實測最少 754 種），或 99.5% 以上的像素和最多的
/// 那個顏色每個通道差不到 8。讀不懂的 PNG（不是
/// 8 位元 RGB／RGBA、交錯式）丟 [FormatException]，不當成通過。
String? blankScreenshotReason(Uint8List png) {
  final image = _decode(png);
  final counts = <int, int>{};
  for (final color in image.pixels) {
    counts[color] = (counts[color] ?? 0) + 1;
  }
  if (counts.length < minColours) {
    return 'only ${counts.length} colours in ${image.width}x${image.height} '
        'pixels';
  }
  final dominant = counts.entries
      .reduce((a, b) => a.value >= b.value ? a : b)
      .key;
  var near = 0;
  for (final MapEntry(key: color, value: n) in counts.entries) {
    if (_close(color, dominant)) near += n;
  }
  final share = near / image.pixels.length;
  if (share < 0.995) return null;
  final hex = dominant.toRadixString(16).padLeft(6, '0');
  return '${(share * 100).toStringAsFixed(1)}% of ${image.width}x'
      '${image.height} pixels are #$hex';
}

/// 少於這麼多種顏色就算沒畫出東西。
const minColours = 32;

bool _close(int a, int b) {
  for (final shift in [16, 8, 0]) {
    if (((a >> shift & 0xff) - (b >> shift & 0xff)).abs() > 8) return false;
  }
  return true;
}

/// 每個像素是 0xRRGGBB（忽略 alpha）。
({int width, int height, Uint32List pixels}) _decode(Uint8List png) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (png.length < 8 ||
      !List.generate(8, (i) => png[i] == signature[i]).every((ok) => ok)) {
    throw const FormatException('not a PNG');
  }
  final data = ByteData.sublistView(png);
  var width = 0, height = 0, channels = 0;
  final compressed = BytesBuilder(copy: false);
  for (var at = 8; at + 8 <= png.length;) {
    final length = data.getUint32(at);
    final type = String.fromCharCodes(png, at + 4, at + 8);
    final body = Uint8List.sublistView(png, at + 8, at + 8 + length);
    switch (type) {
      case 'IHDR':
        width = data.getUint32(at + 8);
        height = data.getUint32(at + 12);
        final bitDepth = body[8], colorType = body[9], interlace = body[12];
        if (bitDepth != 8 || interlace != 0) {
          throw FormatException(
            'unsupported PNG: depth $bitDepth, interlace $interlace',
          );
        }
        channels = switch (colorType) {
          2 => 3,
          6 => 4,
          _ => throw FormatException('unsupported PNG colour type $colorType'),
        };
      case 'IDAT':
        compressed.add(body);
      case 'IEND':
        at = png.length;
        continue;
    }
    at += 12 + length;
  }
  if (width == 0 || height == 0) {
    throw const FormatException('PNG without IHDR');
  }
  final raw = Uint8List.fromList(ZLibDecoder().convert(compressed.takeBytes()));
  final stride = width * channels;
  if (raw.length < height * (stride + 1)) {
    throw const FormatException('PNG image data is truncated');
  }
  final pixels = Uint32List(width * height);
  var previous = Uint8List(stride);
  for (var y = 0; y < height; y++) {
    final start = y * (stride + 1);
    final filter = raw[start];
    final row = Uint8List.fromList(raw.sublist(start + 1, start + 1 + stride));
    for (var i = 0; i < stride; i++) {
      final left = i >= channels ? row[i - channels] : 0;
      final up = previous[i];
      final upLeft = i >= channels ? previous[i - channels] : 0;
      row[i] =
          (row[i] +
              switch (filter) {
                0 => 0,
                1 => left,
                2 => up,
                3 => (left + up) >> 1,
                4 => _paeth(left, up, upLeft),
                _ => throw FormatException('unknown PNG filter $filter'),
              }) &
          0xff;
    }
    for (var x = 0; x < width; x++) {
      final p = x * channels;
      pixels[y * width + x] = row[p] << 16 | row[p + 1] << 8 | row[p + 2];
    }
    previous = row;
  }
  return (width: width, height: height, pixels: pixels);
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}
