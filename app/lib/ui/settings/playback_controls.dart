import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/settings/playback_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 設定頁的「播放」組（design §3.3、§9.8）：音質、格式偏好、記住播放位置、
/// 臨時播放回佇列倒退秒數、跳過試聽片段（design §3.3 的順序）。其他欄位的那一列
/// 跟著用到它的 PR 加。
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
      return seconds == rewindDefault ? t.optionDefault(label: label) : label;
    }

    // 沒設定過時，生效的那一個標「（預設）」（同倒退秒數與快取上限）。
    String defaultLabel(String label, {required bool isDefault}) =>
        isDefault ? t.optionDefault(label: label) : label;

    Widget heading(String title, String hint) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        SizedBox(height: spacing.x1),
        Text(
          hint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: spacing.x2),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(t.audioQuality, t.audioQualityHint),
        Wrap(
          spacing: spacing.x2,
          runSpacing: spacing.x2,
          children: [
            for (final quality in AudioQuality.values)
              ChoiceChip(
                label: Text(
                  defaultLabel(
                    switch (quality) {
                      AudioQuality.high => t.qualityHigh,
                      AudioQuality.medium => t.qualityMedium,
                      AudioQuality.low => t.qualityLow,
                    },
                    isDefault:
                        preferences.stored.audioQuality == null &&
                        quality == preferences.audioQuality,
                  ),
                ),
                selected: quality == preferences.audioQuality,
                onSelected: (_) => unawaited(notifier.setAudioQuality(quality)),
              ),
          ],
        ),
        SizedBox(height: spacing.x4),
        heading(t.formatPriority, t.formatPriorityHint),
        Wrap(
          spacing: spacing.x2,
          runSpacing: spacing.x2,
          children: [
            for (final priority in AudioFormatPriority.values)
              ChoiceChip(
                label: Text(
                  defaultLabel(
                    switch (priority) {
                      AudioFormatPriority.opusFirst => t.formatOpusFirst,
                      AudioFormatPriority.aacFirst => t.formatAacFirst,
                    },
                    isDefault:
                        preferences.stored.audioFormatPriority == null &&
                        priority == preferences.audioFormatPriority,
                  ),
                ),
                selected: priority == preferences.audioFormatPriority,
                onSelected: (_) =>
                    unawaited(notifier.setAudioFormatPriority(priority)),
              ),
          ],
        ),
        SizedBox(height: spacing.x4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.rememberPosition),
          subtitle: Text(t.rememberPositionHint),
          value: preferences.rememberPosition,
          onChanged: (remember) =>
              unawaited(notifier.setRememberPosition(remember)),
        ),
        SizedBox(height: spacing.x4),
        heading(t.tempPlayRewind, t.tempPlayRewindHint),
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
        SizedBox(height: spacing.x4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.skipPreviewClips),
          subtitle: Text(t.skipPreviewClipsHint),
          value: preferences.skipPreviewClips,
          onChanged: (skip) => unawaited(notifier.setSkipPreviewClips(skip)),
        ),
      ],
    );
  }
}
