import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/plugin_artwork.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 方形的封面縮圖；沒有封面、載入中與載入失敗時是同一個佔位圖。
///
/// 圖片經 [pluginId] 的 cache manager（`artworkCacheManagerProvider`）讀：先看
/// 統一快取庫，沒有才經那個插件的媒體 client 下載（每跳檢查允許網域、不帶憑證
/// 與 header、有大小上限；ADR 0016 §決定 4、ADR 0012 §決定 1）。B 站的 hdslb 不帶
/// `Referer` 讀得到，帶了別的網域反而被擋（2026-09-30 實測），所以不給 header。
/// cache manager 還沒有（快取庫開啟中、插件不在清單上）時顯示佔位圖。
class ArtworkImage extends ConsumerWidget {
  const ArtworkImage({
    super.key,
    required this.pluginId,
    required this.artwork,
    required this.size,
  });

  /// 封面所屬的插件（曲目鍵的第一段）。
  final String pluginId;

  final List<TrackArtwork> artwork;

  /// 邊長（dp）。
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pixels = size * MediaQuery.devicePixelRatioOf(context);
    final chosen = pickArtwork(artwork, pixels);
    final cacheManager = chosen == null
        ? null
        : ref.watch(artworkCacheManagerProvider(pluginId));
    final placeholder = _Placeholder(size: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.of(context).radius.small),
      child: SizedBox.square(
        dimension: size,
        child: chosen == null || cacheManager == null
            ? placeholder
            // 封面是裝飾，曲名在旁邊。
            : ExcludeSemantics(
                child: CachedNetworkImage(
                  imageUrl: chosen.url.toString(),
                  cacheManager: cacheManager,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  // 以高解碼：封面多半是橫的（影片封面 16:9），裁成方形時高是
                  // 短邊；以寬解碼會讓高不夠、放大後模糊。
                  memCacheHeight: pixels.round(),
                  // 和佔位圖之間不淡入淡出，照 M1 的 Image.network。
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (context, url) => placeholder,
                  errorWidget: (context, url, error) => placeholder,
                ),
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
