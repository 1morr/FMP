import 'package:flutter/material.dart';
import 'package:fmp/i18n/strings.g.dart';
import '../../data/models/track.dart';
import 'track_thumbnail.dart';
import '../../core/constants/ui_constants.dart';

/// 统一的歌曲列表项组件
///
/// 支持两种模式：
/// - 标准模式：封面 + 信息（使用 ListTile）
/// - 排名模式：排名 + 封面 + 信息（使用 InkWell，样式匹配 ListTile）
///
/// 使用示例：
/// ```dart
/// // 标准模式（歌单详情页）
/// TrackTile(
///   track: track,
///   isPlaying: isPlaying,
///   onTap: () => play(track),
///   trailing: PopupMenuButton(...),
/// )
///
/// // 排名模式（排行榜）
/// TrackTile(
///   track: track,
///   rank: 1,
///   isPlaying: isPlaying,
///   onTap: () => play(track),
///   trailing: PopupMenuButton(...),
/// )
/// ```
class TrackTile extends StatelessWidget {
  /// 歌曲数据
  final Track track;

  /// 是否正在播放
  final bool isPlaying;

  /// 排名（如果提供，使用排名模式布局）
  final int? rank;

  /// 点击回调
  final VoidCallback? onTap;

  /// 长按回调
  final VoidCallback? onLongPress;

  /// 尾部组件（通常是菜单按钮）
  final Widget? trailing;

  /// 自定义副标题（如果不提供，默认显示歌手名）
  final Widget? subtitle;

  /// 是否使用紧凑模式（减小垂直间距）
  final bool dense;

  const TrackTile({
    super.key,
    required this.track,
    this.isPlaying = false,
    this.rank,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.subtitle,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    if (rank != null) {
      // 排名模式：使用 InkWell，样式匹配 ListTile
      return _buildRankingTile(context);
    } else {
      // 标准模式：使用 ListTile
      return _buildStandardTile(context);
    }
  }

  /// 标准模式：使用 ListTile
  Widget _buildStandardTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      dense: dense,
      onTap: onTap,
      onLongPress: onLongPress,
      leading: TrackThumbnail(
        track: track,
        size: AppSizes.thumbnailMedium,
        isPlaying: isPlaying,
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isPlaying ? colorScheme.primary : null,
          fontWeight: isPlaying ? FontWeight.w600 : null,
        ),
      ),
      subtitle: subtitle ??
          Text(
            track.artist ?? t.general.unknownArtist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      trailing: trailing,
    );
  }

  /// 排名模式：使用 InkWell，样式匹配 ListTile
  Widget _buildRankingTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: AppRadius.borderRadiusMd,  // 8dp - 匹配 ListTile 的圆角
      child: Padding(
        // 匹配 ListTile 的内边距
        padding: EdgeInsets.symmetric(
          vertical: dense ? 4 : 8,
          horizontal: 16,
        ),
        child: Row(
          children: [
            // 排名（宽度 28dp）
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
            // 匹配 ListTile leading 的右侧间距
            const SizedBox(width: 16),

            // 封面
            TrackThumbnail(
              track: track,
              size: AppSizes.thumbnailMedium,
              borderRadius: 4,
              isPlaying: isPlaying,
            ),
            // 匹配 ListTile leading 的右侧间距
            const SizedBox(width: 16),

            // 歌曲信息（匹配 ListTile 的 title + subtitle）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title - 使用 bodyLarge 匹配 ListTile
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge?.copyWith(
                      color: isPlaying ? colorScheme.primary : null,
                      fontWeight: isPlaying ? FontWeight.w600 : null,
                    ),
                  ),
                  // 匹配 ListTile title-subtitle 间距
                  const SizedBox(height: 2),
                  // Subtitle
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

            // Trailing
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
