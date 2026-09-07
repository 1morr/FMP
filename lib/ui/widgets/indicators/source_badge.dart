import 'package:flutter/material.dart';

import '../../../core/utils/icon_helpers.dart';

/// 音源标识徽章（灰色小圖標）
///
/// 搜索結果與導入預覽等列表共用。
class SourceBadge extends StatelessWidget {
  final String sourceType;

  const SourceBadge({super.key, required this.sourceType});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Icon(
      getImportSourceIcon(sourceType),
      size: 14,
      color: colorScheme.outline,
    );
  }
}
