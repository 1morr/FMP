import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/settings/playback_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 設定頁的「播放」組（design §3.3、§9.8）：記住播放位置、臨時播放回佇列倒退
/// 秒數。其他欄位的那一列跟著用到它的 PR 加。
class PlaybackControls extends ConsumerWidget {
  const PlaybackControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(playbackPreferencesProvider).value;
    if (preferences == null) return const SizedBox.shrink();
    final t = ref.watch(translationsProvider).playback;
    final notifier = ref.read(playbackPreferencesProvider.notifier);
    final spacing = AppTokens.of(context).spacing;
    final theme = Theme.of(context);
    final rewindDefault = preferences.stored.tempPlayRewindSeconds == null
        ? preferences.tempPlayRewindSeconds
        : null;
    String rewindLabel(int seconds) {
      final label = seconds == 0
          ? t.rewindNone
          : t.rewindSeconds(seconds: seconds);
      return seconds == rewindDefault ? t.rewindDefault(label: label) : label;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.rememberPosition),
          subtitle: Text(t.rememberPositionHint),
          value: preferences.rememberPosition,
          onChanged: (remember) =>
              unawaited(notifier.setRememberPosition(remember)),
        ),
        SizedBox(height: spacing.x4),
        Text(t.tempPlayRewind, style: theme.textTheme.titleSmall),
        SizedBox(height: spacing.x1),
        Text(
          t.tempPlayRewindHint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: spacing.x2),
        // 倒退只在記住播放位置時有作用（沒記住就從頭開始），關著時停用，選了
        // 什麼照樣留著（舊版只在開著時才給設定）。
        Wrap(
          spacing: spacing.x2,
          runSpacing: spacing.x2,
          children: [
            for (final seconds in {
              ...tempPlayRewindOptionsSeconds,
              preferences.tempPlayRewindSeconds,
            }.toList()..sort())
              ChoiceChip(
                label: Text(rewindLabel(seconds)),
                selected: seconds == preferences.tempPlayRewindSeconds,
                onSelected: preferences.rememberPosition
                    ? (_) =>
                          unawaited(notifier.setTempPlayRewindSeconds(seconds))
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}
