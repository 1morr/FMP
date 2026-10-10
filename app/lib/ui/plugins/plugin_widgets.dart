import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/theme/app_tokens.dart';

// 插件頁與首次啟動引導共用的列元件。

/// 卡片的名稱、版本與作者、說明與標記。
class PluginHeading extends StatelessWidget {
  const PluginHeading({
    super.key,
    required this.name,
    required this.byline,
    required this.description,
    required this.tags,
  });

  final String name;
  final String byline;
  final String description;
  final List<Widget> tags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: theme.textTheme.titleMedium),
        Text(
          byline,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (description.isNotEmpty) ...[
          SizedBox(height: spacing.x1),
          Text(description, style: theme.textTheme.bodyMedium),
        ],
        if (tags.isNotEmpty) ...[
          SizedBox(height: spacing.x2),
          Wrap(spacing: spacing.x2, runSpacing: spacing.x1, children: tags),
        ],
      ],
    );
  }
}

enum PluginTagTone { neutral, primary, error }

/// 小標記（已停用、沒有回應、有更新、已安裝）：只是文字，不能點。
class PluginTag extends StatelessWidget {
  const PluginTag({
    super.key,
    required this.text,
    this.tone = PluginTagTone.neutral,
  });

  final String text;
  final PluginTagTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      PluginTagTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      PluginTagTone.primary => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      PluginTagTone.error => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(tokens.radius.small),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.x2,
          vertical: tokens.spacing.x1,
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: foreground),
        ),
      ),
    );
  }
}
