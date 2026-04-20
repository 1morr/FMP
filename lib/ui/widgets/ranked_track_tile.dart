import 'package:flutter/material.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../../core/constants/ui_constants.dart';
import '../../data/models/track.dart';
import 'track_thumbnail.dart';
import 'vip_badge.dart';

/// 排行榜歌曲列表项组件
class RankedTrackTile extends StatelessWidget {
  final Track track;
  final bool isPlaying;
  final int rank;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final Widget? subtitle;
  final bool dense;

  const RankedTrackTile({
    super.key,
    required this.track,
    required this.rank,
    this.isPlaying = false,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.subtitle,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: AppRadius.borderRadiusMd,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: dense ? 4 : 8,
          horizontal: 16,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
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
                          style: textTheme.bodyLarge?.copyWith(
                            color: isPlaying ? colorScheme.primary : null,
                            fontWeight: isPlaying ? FontWeight.w600 : null,
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
                  subtitle ??
                      Text(
                        track.artist ?? t.general.unknownArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
