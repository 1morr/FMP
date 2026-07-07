import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';

/// 封面圖容器外殼，音樂/電台全螢幕播放器共用。
///
/// 統一 AspectRatio(1) + 圓角陰影容器的樣式（surfaceContainerHighest 底色、
/// borderRadiusXl、shadow blur 20 / offset (0,10)、antiAlias 裁切）。內部封面圖
/// （TrackCover 或 RadioCoverImage）或 placeholder 由 [child] 注入，使兩頁的
/// 封面框外觀一致。
class CoverArtContainer extends StatelessWidget {
  final Widget child;
  final ColorScheme colorScheme;

  const CoverArtContainer({
    super.key,
    required this.child,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.borderRadiusXl,
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
