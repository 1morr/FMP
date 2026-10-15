import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/plugin_artwork.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';

/// 歌單的封面（M4 design §10.5）：有自訂封面（`playlists.artwork_json`）就用它，經網域包含它的
/// 插件的媒體 client 讀（`artworkPluginProvider`；那個插件停用或移除後是佔位圖）；沒有就是
/// [firstTrack] 的封面；空歌單是帶歌單圖示的佔位圖。
class PlaylistCover extends ConsumerWidget {
  const PlaylistCover({
    super.key,
    required this.artwork,
    required this.firstTrack,
    required this.size,
  });

  /// 歌單自己的封面；空＝用第一首的。
  final List<TrackArtwork> artwork;
  final TrackInfo? firstTrack;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.queue_music,
          size: size / 2,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    if (artwork.isNotEmpty) {
      return ArtworkImage(
        pluginId: ref.watch(artworkPluginProvider(artwork.first.url)) ?? '',
        artwork: artwork,
        size: size,
        fallback: fallback,
      );
    }
    final first = firstTrack;
    return ArtworkImage(
      pluginId: first?.sourceTypeId ?? '',
      artwork: first?.artwork ?? const [],
      size: size,
      fallback: fallback,
    );
  }
}
