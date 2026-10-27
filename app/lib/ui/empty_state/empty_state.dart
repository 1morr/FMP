import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 圖示、標題、說明與動作：頁面的空狀態與失敗狀態共用這一個樣子（ADR 0035，R6.10）。
///
/// - 預設置中、整頁用。
/// - [error]：失敗狀態，圖示用 error 色，一眼分得出「出錯」與「只是空」。
/// - [compact]：區塊級的橫條（首頁一個區塊讀取失敗）：圓角底色、圖示在左、動作在右，不置中、
///   不捲動；[error] 時底色是 errorContainer。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.error = false,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  /// 失敗狀態（error 色圖示）。
  final bool error;

  /// 區塊級的緊湊橫條。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = AppTokens.of(context);
    final spacing = tokens.spacing;
    final body = this.body;
    final action = this.action;
    if (compact) {
      final background = error
          ? scheme.errorContainer
          : scheme.surfaceContainerHighest;
      final foreground = error
          ? scheme.onErrorContainer
          : scheme.onSurfaceVariant;
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.x4,
          vertical: spacing.x2,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(tokens.radius.medium),
          ),
          child: Padding(
            padding: EdgeInsets.all(spacing.x3),
            child: Row(
              children: [
                Icon(icon, color: foreground),
                SizedBox(width: spacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: foreground,
                        ),
                      ),
                      if (body != null)
                        Text(
                          body,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: foreground,
                          ),
                        ),
                    ],
                  ),
                ),
                if (action != null) ...[SizedBox(width: spacing.x2), action],
              ],
            ),
          ),
        ),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(spacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: AppLayout.emptyStateIcon,
              color: error ? scheme.error : scheme.onSurfaceVariant,
            ),
            SizedBox(height: spacing.x4),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              SizedBox(height: spacing.x2),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[SizedBox(height: spacing.x4), action],
          ],
        ),
      ),
    );
  }
}
