import 'package:flutter/material.dart';

/// `PopupMenuItem` 的內容：圖示、標籤、可選的尾端圖示，攤平成一個 `Row`。
///
/// 帶尾端圖示的項目不要用 `ListTile`。`PopupMenuButton` 用 intrinsic 寬度決定
/// 選單多寬（以 56dp 為級距、下限 112dp），而 `ListTile` 的 intrinsic 寬度少算
/// 了 trailing 前的 `horizontalTitleGap`（16dp），實際 layout 卻有保留。平常
/// 級距會把這 16dp 吸收掉；標籤短到選單剛好落在級距邊界時，標題就少了 16dp
/// —— 播放頁只有倍速一項時選單是 112dp，標題只剩約 14dp，`1.0x` 被斷成三行。
///
/// 視覺比照選單裡原本的 `ListTile`：M3 的 leading 寬 24 + 間距 16、標題
/// `bodyLarge`、圖示 `onSurfaceVariant`。
class PopupMenuRow extends StatelessWidget {
  const PopupMenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.trailing,
  });

  final Widget icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onSurfaceVariant;

    return Row(
      children: [
        IconTheme.merge(
          data: IconThemeData(color: iconColor),
          child: SizedBox(width: 24, child: Center(child: icon)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            // 顏色沿用 PopupMenuItem 給的 DefaultTextStyle，停用時才會變灰。
            style: theme.textTheme.bodyLarge?.apply(
              color: DefaultTextStyle.of(context).style.color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 16),
          IconTheme.merge(
            data: IconThemeData(color: iconColor),
            child: trailing!,
          ),
        ],
      ],
    );
  }
}
