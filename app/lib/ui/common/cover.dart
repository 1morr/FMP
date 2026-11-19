import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/cover_image.dart';
import 'package:material_ui/material_ui.dart';

/// 封面網址換成圖：預設是磁碟快取的 [coverImage]；測試與不聯網的實跑情境
/// 換成記憶體裡的圖。
final coverImageLoaderProvider = Provider<ImageProvider Function(String url)>(
  (_) => coverImage,
);

/// 封面（`.cover`）：圓角方塊，沒有封面、載入中或載入失敗時是 `--cell-2`
/// 的底；外緣一圈 0.5 的細線（`--cover-ring`）。
class Cover extends ConsumerWidget {
  const Cover({
    super.key,
    required this.url,
    required this.size,
    required this.radius,
  });

  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.fmpColors;
    final load = ref.watch(coverImageLoaderProvider);
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: colors.coverRing, width: .5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: ColoredBox(
            color: colors.cell2,
            child: switch (url) {
              null => null,
              final url => Image(
                image: ResizeImage(
                  load(url),
                  width: pixels,
                  height: pixels,
                  policy: ResizeImagePolicy.fit,
                ),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                excludeFromSemantics: true,
                // 有 errorBuilder 時失敗不報成 Flutter 錯誤；留著底色。
                errorBuilder: (_, _, _) => const SizedBox.expand(),
              ),
            },
          ),
        ),
      ),
    );
  }
}
