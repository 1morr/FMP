import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/radio/radio_service.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/player/live_widgets.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 電台與直播間的狀態標記（ADR 0031 §決定 4）：四種的顏色與圖示都不同，「查詢失敗」是警告色、
/// 不像未開播（D10）。開播中與播放頁的「直播中」同樣是紅色。
class RadioStatusTag extends ConsumerWidget {
  const RadioStatusTag({super.key, required this.status});

  final RadioStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).radio;
    final scheme = Theme.of(context).colorScheme;
    final warning = AppTokens.of(context).warning;
    return switch (status) {
      RadioStatus.live => StatusTag(
        icon: Icons.sensors,
        text: t.statusLive,
        background: scheme.error,
        foreground: scheme.onError,
      ),
      RadioStatus.offline => StatusTag(
        icon: Icons.sensors_off,
        text: t.statusOffline,
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
      ),
      RadioStatus.queryFailed => StatusTag(
        icon: Icons.error_outline,
        text: t.statusFailed,
        background: warning.container,
        foreground: warning.onContainer,
      ),
      // 還沒查過：只有邊框，和「未開播」的填色分開。
      RadioStatus.unchecked => StatusTag(
        icon: Icons.help_outline,
        text: t.statusUnchecked,
        background: scheme.surface,
        foreground: scheme.onSurfaceVariant,
        border: scheme.outline,
      ),
    };
  }
}

/// 標記加文字（電台列與直播間結果的主播）：放得下時在同一行，放不下時文字換到下一行；文字與
/// 標記自己的字都只有一行、太長就省略，不會撐破列。用 `Wrap` 而不是 `Text.rich` 的 `WidgetSpan`：
/// 後者裡面的字不在 guideline 測試的對比度檢查範圍內。
class TaggedLine extends StatelessWidget {
  const TaggedLine({super.key, required this.tag, this.text, this.extraTag});

  final Widget tag;
  final String? text;

  /// 狀態標記之後的第二個標記（直播間的分區）。
  final Widget? extraTag;

  @override
  Widget build(BuildContext context) {
    final spacing = AppTokens.of(context).spacing;
    final text = this.text;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.x1),
      child: Wrap(
        spacing: spacing.x2,
        runSpacing: spacing.x1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          tag,
          ?extraTag,
          if (text != null)
            Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
