import 'package:flutter/material.dart';

/// 詳情統計列的單一項目（圖示 + 文字）。
class DetailStatItem {
  const DetailStatItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// 依圖示的光學佔比回傳補償後的尺寸。
///
/// Material 的 play_arrow / star 字形在 24dp 網格內的視覺佔比小於
/// thumb_up、comment 等填滿型圖示，同尺寸並排時看起來明顯偏小。
/// 沿用重構前音樂詳情面板的補償比例（基準 18、播放 26、收藏 24，
/// 約 1.44x / 1.33x），換算到目前的基準 16。
double _compensatedIconSize(IconData icon) {
  if (icon == Icons.play_arrow_rounded || icon == Icons.play_arrow) {
    return 23;
  }
  if (icon == Icons.star_rounded || icon == Icons.star) {
    return 21;
  }
  return 16;
}

/// 詳情面板/彈窗共用的統計列。
///
/// 音樂 Detail Panel、電台 Detail Panel、行動版歌曲資訊彈窗、
/// 行動版直播資訊彈窗共用此寫法：單項為 primary 圖示 + onSurfaceVariant
/// 內文。[alignment] 預設靠左（行動版彈窗）；寬幅的桌面面板可傳
/// [WrapAlignment.spaceEvenly] 讓統計項均勻撐滿整行。
/// 只有一個統計項時一律靠左（spaceEvenly 會把單項置中，與面板其他
/// 左對齊內容不一致）。
class DetailStatsRow extends StatelessWidget {
  const DetailStatsRow({
    super.key,
    required this.items,
    this.alignment = WrapAlignment.start,
  });

  final List<DetailStatItem> items;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: items.length > 1 ? alignment : WrapAlignment.start,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                size: _compensatedIconSize(item.icon),
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
