import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 置中的圖示、標題、說明與動作：頁面的空狀態與失敗狀態共用這一個樣子。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final body = this.body;
    final action = this.action;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(spacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: AppLayout.emptyStateIcon,
              color: theme.colorScheme.onSurfaceVariant,
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
                  color: theme.colorScheme.onSurfaceVariant,
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
