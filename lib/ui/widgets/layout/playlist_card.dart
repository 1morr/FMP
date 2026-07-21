import 'package:flutter/material.dart';

import '../../../core/utils/icon_helpers.dart';
import '../../../data/models/playlist.dart';
import '../../../i18n/strings.g.dart';

/// 共享歌單卡片。
///
/// 統一首頁與音樂庫的三種歌單卡片外觀：Card 表面 + 封面 + 信息區
/// （名稱 + Mix/導入/曲目數徽章列）。封面由呼叫端以
/// [PlaylistCoverImage] 搭配語意 variant 建構後傳入，本元件不直接載圖。
///
/// - [isRefreshing] 為 true 時在封面上疊加刷新進度遮罩（音樂庫刷新中）。
/// - [dragHandle] 不為 null 時疊加在卡片右上角（排序模式），通常搭配
///   [enableInkWell] = false 使用。
/// - 右鍵/長按菜單由呼叫端包 ContextMenuRegion / bottom sheet 處理。
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.cover,
    this.onTap,
    this.onLongPress,
    this.margin,
    this.isRefreshing = false,
    this.dragHandle,
    this.enableInkWell = true,
  });

  final Playlist playlist;

  /// 封面區內容（呼叫端以 PlaylistCoverImage + 語意 variant 建構）。
  final Widget cover;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Card 外距；首頁傳 [EdgeInsets.zero]，音樂庫使用預設。
  final EdgeInsetsGeometry? margin;

  /// 是否在封面上顯示刷新進度遮罩。
  final bool isRefreshing;

  /// 疊加在卡片右上角的元件（排序模式傳拖動把手）。
  final Widget? dragHandle;

  /// 是否包裹 InkWell（排序模式為 false）。
  final bool enableInkWell;

  @override
  Widget build(BuildContext context) {
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              cover,
              // 刷新指示器覆盖层
              if (isRefreshing)
                Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 信息
        Padding(
          padding: const EdgeInsets.all(8),
          child: _PlaylistCardInfo(playlist: playlist),
        ),
      ],
    );

    if (enableInkWell) {
      content = InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: content,
      );
    }

    if (dragHandle != null) {
      content = Stack(
        children: [
          content,
          Positioned(top: 4, right: 4, child: dragHandle!),
        ],
      );
    }

    return Card(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

/// 歌單卡片信息區：名稱 + Mix/導入來源/曲目數徽章列。
class _PlaylistCardInfo extends StatelessWidget {
  const _PlaylistCardInfo({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          playlist.name,
          style: textTheme.titleSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            if (playlist.isMix) ...[
              Icon(
                Icons.radio,
                size: 12,
                color: colorScheme.tertiary,
              ),
              const SizedBox(width: 4),
              Text(
                'Mix',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.tertiary,
                ),
              ),
            ] else ...[
              if (playlist.isImported) ...[
                Icon(
                  getImportSourceIcon(playlist.importSourceType),
                  size: 12,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                t.library.trackCount(n: playlist.trackCount),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
