import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/platform/cover_image.dart';
import 'package:material_ui/material_ui.dart';

/// 播放頁背景的三個封面色（`docs/design/DESIGN.md`〈封面色只用在播放頁背景〉
/// 的 `FMP.ambient`）：[base] 鋪底，[second]、[third] 是模糊色團。
@immutable
class AmbientColors {
  const AmbientColors(this.base, this.second, this.third);

  /// 取不到封面色時（沒有封面、載入失敗）：照稿播放頁主畫面那首的封面色
  /// （`player.html` 的 `PL_T`）。
  static const fallback = AmbientColors(
    Color(0xFFE0AFA0),
    Color(0xFF463F3A),
    Color(0xFFF4F3EE),
  );

  final Color base;
  final Color second;
  final Color third;

  /// 換曲時從 [a] 漸變到 [b]。
  static AmbientColors lerp(AmbientColors a, AmbientColors b, double t) =>
      AmbientColors(
        Color.lerp(a.base, b.base, t)!,
        Color.lerp(a.second, b.second, t)!,
        Color.lerp(a.third, b.third, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is AmbientColors &&
      other.base == base &&
      other.second == second &&
      other.third == third;

  @override
  int get hashCode => Object.hash(base, second, third);

  @override
  String toString() => 'AmbientColors($base, $second, $third)';
}

/// 從封面的 RGBA 像素取三色：每個色版取前 4 位元分桶，依像素數排序；最多的
/// 那桶的平均色鋪底，接著挑和已選的色差夠大的兩桶。顏色不夠多時（單色封面）
/// 用底色調亮、調暗補上。透明的像素不算；一個像素都沒有時回 [AmbientColors.fallback]。
AmbientColors ambientColorsFromRgba(Uint8List rgba) {
  final counts = <int, int>{};
  final sums = <int, List<int>>{};
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
    counts[key] = (counts[key] ?? 0) + 1;
    final sum = sums.putIfAbsent(key, () => [0, 0, 0]);
    sum[0] += r;
    sum[1] += g;
    sum[2] += b;
  }
  if (counts.isEmpty) return AmbientColors.fallback;
  final buckets = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  Color average(int key) {
    final sum = sums[key]!, n = counts[key]!;
    return Color.fromARGB(255, sum[0] ~/ n, sum[1] ~/ n, sum[2] ~/ n);
  }

  final picked = <Color>[average(buckets.first)];
  for (final key in buckets.skip(1)) {
    if (picked.length == 3) break;
    final color = average(key);
    if (picked.every((p) => _distance(p, color) >= _minDistance)) {
      picked.add(color);
    }
  }
  final base = picked.first;
  final second = picked.length > 1 ? picked[1] : _shift(base, .18);
  final third = picked.length > 2 ? picked[2] : _shift(base, -.18);
  return AmbientColors(base, second, third);
}

/// 兩個色要差這麼多（RGB 的歐氏距離，0–441）才算不同的色。
const _minDistance = 48.0;

double _distance(Color a, Color b) {
  final dr = (a.r - b.r) * 255, dg = (a.g - b.g) * 255, db = (a.b - b.b) * 255;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

/// [color] 的明度加 [amount]（往另一邊折回，免得白的調不亮、黑的調不暗）。
Color _shift(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  var lightness = hsl.lightness + amount;
  if (lightness > 1 || lightness < 0) lightness = hsl.lightness - amount;
  return hsl.withLightness(lightness.clamp(0, 1)).toColor();
}

/// 封面網址換成圖：預設是磁碟快取的 [coverImage]，測試換成記憶體裡的圖。
final coverImageLoaderProvider = Provider<ImageProvider Function(String url)>(
  (_) => coverImage,
);

/// `url` 這張封面的三色；沒有封面或載入失敗時是 [AmbientColors.fallback]。
/// 縮到 32 見方再取，夠分出主色。
final ambientColorsProvider = FutureProvider.family<AmbientColors, String?>((
  ref,
  url,
) async {
  if (url == null) return AmbientColors.fallback;
  final provider = ResizeImage(
    ref.read(coverImageLoaderProvider)(url),
    width: _sampleSize,
    height: _sampleSize,
  );
  try {
    final image = await _load(provider);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (bytes == null) return AmbientColors.fallback;
    return ambientColorsFromRgba(bytes.buffer.asUint8List());
  } on Object {
    // 載入失敗（網路、格式）照稿的預設，不當成錯誤。
    return AmbientColors.fallback;
  }
});

const _sampleSize = 32;

/// 解出 [provider] 的圖（呼叫的人負責 dispose）。
Future<ui.Image> _load(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info.image.clone());
      info.dispose();
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
