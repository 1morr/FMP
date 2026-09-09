import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/constants/ui_constants.dart';
import 'package:fmp/core/utils/number_format_utils.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/providers/audio/audio_player_selectors.dart';
import 'package:fmp/ui/handlers/track_action_coordinator.dart';
import 'package:fmp/ui/handlers/track_action_menu.dart';
import 'package:fmp/ui/widgets/images/track_thumbnail.dart';
import 'package:fmp/ui/widgets/indicators/vip_badge.dart';
import 'package:fmp/ui/widgets/menus/context_menu_region.dart';

/// 播放數群組還放得下的最小 tile 寬度。
///
/// 這一列的固定開銷是左右外距 32、名次欄 28、封面 48、選單按鈕 48 與兩個 16dp
/// 間隔，共 188dp；播放數群組本身約 66dp（間隔 8 + 圖示 14 + 間隔 2 + 數字）。
/// 320dp 以下同時放這兩者，藝人名就只剩個位數的像素 —— 播放數是次要資訊，
/// 藝人名不是，所以窄的時候整組退場而不是兩個一起被壓扁（#85）。
///
/// 側欄展開加右側面板的橫向手機（約 268dp 內容欄）落在門檻以下，是這個值要
/// 擋住的情境。
const double _viewCountMinTileWidth = 320;

/// 排行榜歌曲項目（首頁排行榜與探索頁共用）
///
/// 顯示排名、封面、標題（含 VIP 標記）、歌手與播放數。
/// 多選模式下 trailing 改為勾選框；[onTap] 可覆寫預設的臨時播放行為，
/// [onLongPress] 用於進入多選模式。
class RankingTrackTile extends ConsumerWidget {
  final Track track;
  final int rank;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const RankingTrackTile({
    super.key,
    required this.track,
    required this.rank,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    final isPlaying =
        currentTrack != null &&
        currentTrack.sourceId == track.sourceId &&
        currentTrack.pageNum == track.pageNum;

    return ContextMenuRegion(
      menuBuilder: (_) => _buildMenuItems(),
      onSelected: (value) => _handleMenuAction(context, ref, value),
      child: InkWell(
        onTap:
            onTap ??
            () {
              ref.read(audioControllerProvider.notifier).playTemporary(track);
            },
        onLongPress: onLongPress,
        borderRadius: AppRadius.borderRadiusMd,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 這一列自己量自己的容器，不問視窗有多寬：同一個 tile 在首頁的單欄、
            // 首頁的三欄與探索頁裡拿到的寬度都不一樣（見 lib/ui/AGENTS.md 的
            // Layout Conventions）。
            final isNarrow = constraints.maxWidth < _viewCountMinTileWidth;
            final gap = isNarrow ? 8.0 : 16.0;

            return Padding(
              // 窄的時候外距也一起收：一個 236dp 的 tile 原本有 64dp（本列 32 +
              // 首頁區塊 32）花在左右留白上，超過寬度的四分之一。內距縮小不影響
              // 觸控目標 —— InkWell 在外面。
              padding: EdgeInsets.symmetric(
                vertical: 8,
                horizontal: isNarrow ? 8 : 16,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: isNarrow ? 20 : 28,
                    child: Text(
                      '$rank',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                  SizedBox(width: gap),
                  TrackThumbnail(
                    track: track,
                    size: isNarrow
                        ? AppSizes.thumbnailSmall
                        : AppSizes.thumbnailMedium,
                    borderRadius: 4,
                    isPlaying: isPlaying,
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: isPlaying
                                          ? colorScheme.primary
                                          : null,
                                      fontWeight: isPlaying
                                          ? FontWeight.w600
                                          : null,
                                    ),
                              ),
                            ),
                            if (track.isVip) ...[
                              const SizedBox(width: 4),
                              const VipBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                track.artist ?? t.general.unknownArtist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            if (track.viewCount != null && !isNarrow)
                              // 整組包在 Flexible 裡：圖示與數字以前是不可縮的，
                              // 可用寬度一低於「藝人名最小寬 + 播放數固有寬」整
                              // 列就溢出（#85）。
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.play_arrow,
                                      size: 14,
                                      color: colorScheme.outline,
                                    ),
                                    const SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                        formatCount(track.viewCount!),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: colorScheme.outline,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isSelectionMode)
                    _SelectionCheckbox(isSelected: isSelected, onTap: onTap)
                  else
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) =>
                          _handleMenuAction(context, ref, value),
                      itemBuilder: (_) => _buildMenuItems(),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return buildTrackActionPopupMenuEntries(
      buildCommonTrackActionMenuItems(translations: t),
    );
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    await TrackActionCoordinator.handleSingle(
      context: context,
      ref: ref,
      track: track,
      actionId: action,
    );
  }
}

/// 圓形選擇勾選框
class _SelectionCheckbox extends StatelessWidget {
  final bool isSelected;
  final VoidCallback? onTap;

  const _SelectionCheckbox({required this.isSelected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: isSelected ? colorScheme.primary : colorScheme.outline,
      ),
      tooltip: isSelected ? t.general.deselect : t.general.select,
      onPressed: onTap,
    );
  }
}
