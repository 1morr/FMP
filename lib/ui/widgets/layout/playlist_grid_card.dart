import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fmp/core/services/image_loading_service.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/providers/library/refresh_provider.dart';
import 'package:fmp/services/library/playlist_service.dart';
import 'package:fmp/ui/router.dart';
import 'package:fmp/ui/widgets/images/playlist_cover_image.dart';
import 'package:fmp/ui/widgets/layout/playlist_card.dart';
import 'package:fmp/ui/widgets/menus/context_menu_region.dart';
import 'package:fmp/ui/widgets/menus/playlist_card_actions.dart';

/// 歌單網格卡片：[PlaylistCard] 的外觀，加上右鍵選單、長按選單與導覽。
///
/// 首頁的「我的歌單」與音樂庫的歌單網格用的是同一個元件。它們曾經是兩份各自
/// 維護的私有 widget，逐字相同的選單處理器抄了兩遍，而導覽保護只補在音樂庫
/// 那一份 —— 這正是重複會怎麼壞掉的例子。選單行為住在
/// [PlaylistCardActions]，這裡只負責接線。
///
/// 排序模式的卡片不走這裡：它沒有選單也不導覽，直接用 [PlaylistCard] 搭
/// `dragHandle`，封面則共用 [playlistCardCover]。
class PlaylistGridCard extends ConsumerWidget {
  const PlaylistGridCard({
    super.key,
    required this.playlist,
    required this.coverAsync,
    this.margin,
  });

  final Playlist playlist;
  final AsyncValue<PlaylistCoverData> coverAsync;

  /// Card 外距；首頁傳 [EdgeInsets.zero]，音樂庫留 null 用 Card 預設值。
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRefreshing = ref.watch(isPlaylistRefreshingProvider(playlist.id));

    return ContextMenuRegion(
      menuBuilder: (context) =>
          PlaylistCardActions.buildContextMenuEntries(context, ref, playlist),
      onSelected: (value) =>
          PlaylistCardActions.handleAction(context, ref, playlist, value),
      child: PlaylistCard(
        playlist: playlist,
        margin: margin,
        isRefreshing: isRefreshing,
        onTap: () {
          // 兩個呼叫端都把卡片建在 LayoutBuilder 裡，在佈局期間導覽會炸，
          // 所以延到下一個 microtask 再推路由。
          final id = playlist.id;
          Future.microtask(() {
            if (context.mounted) {
              context.push(RoutePaths.playlistDetailPath(id));
            }
          });
        },
        onLongPress: () =>
            PlaylistCardActions.showOptionsSheet(context, ref, playlist),
        cover: playlistCardCover(coverAsync),
      ),
    );
  }
}

/// 歌單卡的封面區。三個呼叫端（首頁、音樂庫網格、音樂庫排序模式）共用。
///
/// 不傳 `width`：解碼尺寸由 [PlaylistCoverVariant.card] 的 `targetDisplaySize`
/// 決定，而版面寬度由 [PlaylistCard] 封面槽的 `StackFit.expand` 緊約束決定，
/// 兩者都輪不到 `width`。也不傳 `placeholder`：[PlaylistCoverImage] 的預設值
/// 就是 `ImagePlaceholder.playlist()`。
Widget playlistCardCover(AsyncValue<PlaylistCoverData> coverAsync) {
  return coverAsync.when(
    skipLoadingOnReload: true,
    data: (coverData) => coverData.hasCover
        ? PlaylistCoverImage(
            localPath: coverData.localPath,
            networkUrl: coverData.networkUrl,
            fit: BoxFit.cover,
            variant: PlaylistCoverVariant.card,
          )
        : const ImagePlaceholder.playlist(),
    loading: () => const ImagePlaceholder.playlist(),
    error: (error, stack) => const ImagePlaceholder.playlist(),
  );
}
