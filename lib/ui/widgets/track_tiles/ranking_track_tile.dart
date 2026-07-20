import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/utils/number_format_utils.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../services/audio/audio_provider.dart';
import '../../handlers/track_action_coordinator.dart';
import '../../handlers/track_action_menu.dart';
import '../images/track_thumbnail.dart';
import '../indicators/vip_badge.dart';
import '../menus/context_menu_region.dart';

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
    final isPlaying = currentTrack != null &&
        currentTrack.sourceId == track.sourceId &&
        currentTrack.pageNum == track.pageNum;

    return ContextMenuRegion(
      menuBuilder: (_) => _buildMenuItems(),
      onSelected: (value) => _handleMenuAction(context, ref, value),
      child: InkWell(
        onTap: onTap ??
            () {
              ref.read(audioControllerProvider.notifier).playTemporary(track);
            },
        onLongPress: onLongPress,
        borderRadius: AppRadius.borderRadiusMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 16,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.outline,
                      ),
                ),
              ),
              const SizedBox(width: 16),
              TrackThumbnail(
                track: track,
                size: AppSizes.thumbnailMedium,
                borderRadius: 4,
                isPlaying: isPlaying,
              ),
              const SizedBox(width: 16),
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
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: isPlaying ? colorScheme.primary : null,
                                  fontWeight:
                                      isPlaying ? FontWeight.w600 : null,
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
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                        if (track.viewCount != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.play_arrow,
                            size: 14,
                            color: colorScheme.outline,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            formatCount(track.viewCount!),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.outline,
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isSelectionMode)
                _SelectionCheckbox(
                  isSelected: isSelected,
                  onTap: onTap,
                )
              else
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) => _handleMenuAction(context, ref, value),
                  itemBuilder: (_) => _buildMenuItems(),
                ),
            ],
          ),
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

  const _SelectionCheckbox({
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: isSelected ? colorScheme.primary : colorScheme.outline,
      ),
      onPressed: onTap,
    );
  }
}
