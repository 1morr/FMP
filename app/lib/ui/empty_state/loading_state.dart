import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/theme/app_tokens.dart';

/// 載入中：置中的轉圈，下面一行說明在等什麼（ADR 0035，R6.10）。文字同時是轉圈的語意名稱，
/// 螢幕閱讀器只念一次。
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ExcludeSemantics(child: CircularProgressIndicator()),
            SizedBox(height: spacing.x4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
