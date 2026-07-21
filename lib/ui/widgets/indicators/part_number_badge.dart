import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import 'now_playing_indicator.dart';

/// 分P（多P影片）前導徽章：播放中顯示動態指示器，否則顯示 P{n} 方塊。
///
/// 搜尋頁分P列表、本地歌曲列表與歌單詳情頁共用同一規格。
class PartNumberBadge extends StatelessWidget {
  /// 分P編號（1 起）。
  final int partNumber;

  /// 是否正在播放此分P。
  final bool isPlaying;

  const PartNumberBadge({
    super.key,
    required this.partNumber,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (isPlaying) {
      return NowPlayingIndicator(
        size: 24,
        color: colorScheme.primary,
      );
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusSm,
      ),
      alignment: Alignment.center,
      child: Text(
        'P$partNumber',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.outline,
            ),
      ),
    );
  }
}
