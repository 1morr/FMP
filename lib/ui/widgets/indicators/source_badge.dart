import 'package:flutter/material.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../data/models/track.dart';

/// 音源标识徽章（灰色小圖標）
///
/// 搜索結果與導入預覽等列表共用。
class SourceBadge extends StatelessWidget {
  final SourceType sourceType;

  const SourceBadge({super.key, required this.sourceType});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = switch (sourceType) {
      SourceType.bilibili => SimpleIcons.bilibili,
      SourceType.youtube => SimpleIcons.youtube,
      SourceType.netease => SimpleIcons.neteasecloudmusic,
    };

    return Icon(
      icon,
      size: 14,
      color: colorScheme.outline,
    );
  }
}
