import 'package:material_ui/material_ui.dart';

import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 從插件給的多尺寸封面挑一張（ADR 0016 §決定 4）：寬度不小於 [pixels] 的
/// 裡面最小的；都比它小時，先取沒標寬度的（插件多半只給原圖，例如 B 站），
/// 再來才是最大的那張。沒有封面就是 `null`。
Artwork? pickArtwork(List<Artwork> artwork, double pixels) {
  Artwork? smallestEnough;
  Artwork? largest;
  Artwork? unknown;
  for (final candidate in artwork) {
    final width = candidate.width;
    if (width == null) {
      unknown ??= candidate;
    } else if (width >= pixels) {
      if (smallestEnough == null || width < smallestEnough.width!) {
        smallestEnough = candidate;
      }
    } else if (largest == null || width > largest.width!) {
      largest = candidate;
    }
  }
  return smallestEnough ?? unknown ?? largest;
}

/// 方形的封面縮圖；沒有封面、載入中與載入失敗時是同一個佔位圖。
///
/// 網址已在 DTO 解碼時經插件的 `allowedHosts` 檢查（`Artwork`），這裡直接以
/// `Image.network` 讀，不帶 header：B 站的 hdslb 不帶 `Referer` 可以讀，帶了
/// 別的網域反而被擋（2026-09-30 實測）。只有 Flutter 記憶體裡的 `ImageCache`；
/// 磁碟快取與經媒體 client 讀圖在 M6（ADR 0016 §決定 4、ADR 0012）。
class ArtworkImage extends StatelessWidget {
  const ArtworkImage({super.key, required this.artwork, required this.size});

  final List<Artwork> artwork;

  /// 邊長（dp）。
  final double size;

  @override
  Widget build(BuildContext context) {
    final pixels = size * MediaQuery.devicePixelRatioOf(context);
    final chosen = pickArtwork(artwork, pixels);
    final placeholder = _Placeholder(size: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.of(context).radius.small),
      child: SizedBox.square(
        dimension: size,
        child: chosen == null
            ? placeholder
            : Image.network(
                chosen.url.toString(),
                width: size,
                height: size,
                fit: BoxFit.cover,
                // 以高解碼：封面多半是橫的（影片封面 16:9），裁成方形時高是
                // 短邊；以寬解碼會讓高不夠、放大後模糊。
                cacheHeight: pixels.round(),
                // 封面是裝飾，曲名在旁邊。
                excludeFromSemantics: true,
                frameBuilder: (context, child, frame, synchronous) =>
                    frame == null && !synchronous ? placeholder : child,
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.music_note,
          size: size / 2,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
