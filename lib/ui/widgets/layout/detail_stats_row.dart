import 'package:flutter/material.dart';

/// 詳情統計列的單一項目（圖示 + 文字）。
class DetailStatItem {
  const DetailStatItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// 詳情面板/彈窗共用的統計列。
///
/// 音樂 Detail Panel、電台 Detail Panel、行動版歌曲資訊彈窗、
/// 行動版直播資訊彈窗共用此寫法：Wrap(spacing: 16, runSpacing: 8)，
/// 單項為 primary 圖示 + onSurfaceVariant 內文。
class DetailStatsRow extends StatelessWidget {
  const DetailStatsRow({super.key, required this.items});

  final List<DetailStatItem> items;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                size: 16,
                color: colorScheme.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Text(
                item.label,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
