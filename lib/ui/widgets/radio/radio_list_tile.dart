import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../data/models/radio_station.dart';
import '../../../data/models/track.dart';


/// 電台列表項
class RadioStationTile extends ConsumerWidget {
  final RadioStation station;
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const RadioStationTile({
    super.key,
    required this.station,
    this.isPlaying = false,
    this.isLoading = false,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            // 封面
            _buildThumbnail(colorScheme),

            const SizedBox(width: 12),

            // 資訊
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 標題
                  Text(
                    station.title,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: isPlaying ? FontWeight.bold : null,
                      color: isPlaying ? colorScheme.primary : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // 副標題
                  _buildSubtitle(colorScheme, textTheme),
                ],
              ),
            ),

            // 載入指示器或選項按鈕
            if (isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: colorScheme.onSurfaceVariant,
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'delete':
                      onDelete?.call();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20),
                        SizedBox(width: 12),
                        Text('刪除'),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(ColorScheme colorScheme) {
    const size = 56.0;
    const borderRadius = BorderRadius.all(Radius.circular(8));

    return Stack(
      children: [
        // 封面圖
        ClipRRect(
          borderRadius: borderRadius,
          child: ImageLoadingService.loadImage(
              networkUrl: station.thumbnailUrl,
              placeholder: _buildPlaceholder(colorScheme),
              fit: BoxFit.cover,
              width: size,
              height: size,
            ),
        ),

        // 播放中指示器
        if (isPlaying)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                color: colorScheme.primary.withValues(alpha: 0.3),
              ),
              child: Center(
                child: Icon(
                  Icons.graphic_eq,
                  color: colorScheme.onPrimary,
                  size: 24,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      width: 56,
      height: 56,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.radio,
        color: colorScheme.onSurfaceVariant,
        size: 28,
      ),
    );
  }

  Widget _buildSubtitle(ColorScheme colorScheme, TextTheme textTheme) {
    final parts = <InlineSpan>[];

    // 主播名
    if (station.hostName != null && station.hostName!.isNotEmpty) {
      parts.add(TextSpan(text: station.hostName!));
    }

    // 平台類型
    final platformIcon = station.sourceType == SourceType.bilibili
        ? 'B站'
        : 'YouTube';

    if (parts.isNotEmpty) {
      parts.add(const TextSpan(text: ' · '));
    }
    parts.add(TextSpan(text: platformIcon));

    // 播放中標記
    if (isPlaying) {
      parts.add(const TextSpan(text: ' · '));
      parts.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ));
    }

    return RichText(
      text: TextSpan(
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        children: parts,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
