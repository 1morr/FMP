import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';

/// 标签区块（逗号分隔字串解析 + 標籤 chips）。
///
/// 電台全屏播放器與桌面 Detail Panel 共用；呼叫方傳入原始逗號分隔字串，
/// 此處負責 split/trim/過濾空項。
class TagsSection extends StatelessWidget {
  /// 原始逗號分隔的標籤字串。
  final String tags;

  /// 標題文字（呼叫方負責 i18n）。
  final String title;

  const TagsSection({
    super.key,
    required this.tags,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tagList =
        tags.split(',').where((tag) => tag.trim().isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tag, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tagList
              .map((tag) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadius.borderRadiusXl,
                    ),
                    child: Text(
                      tag.trim(),
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
