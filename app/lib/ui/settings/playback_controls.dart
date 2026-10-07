import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/settings/playback_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 設定頁的「播放」組（design §3.3、§9.8）：音質、格式偏好、記住播放位置、
/// 臨時播放回佇列倒退秒數、跳過試聽片段、重啟恢復倒退秒數、播放歷史保留筆數、切歌時捲到目前歌曲（design §3.3 的順序）。
/// 其他欄位的那一列跟著用到它的 PR 加。
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
    // 倒退秒數的選項：沒設定過時，生效的那一個標「（預設）」。倒退只在記住播放
    // 位置時有作用（沒記住就從頭開始），關著時停用，選了什麼照樣留著（舊版只在
    // 開著時才給設定）。
    Widget rewindOptions({
      required int current,
      required bool isUnset,
      required List<int> options,
      required ValueChanged<int> onSelected,
    }) => Wrap(
      spacing: spacing.x2,
      runSpacing: spacing.x2,
      children: [
        for (final seconds in {...options, current}.toList()..sort())
          ChoiceChip(
            label: Text(() {
              final label = seconds == 0
                  ? t.rewindNone
                  : t.rewindSeconds(seconds: seconds);
              return isUnset && seconds == current
                  ? t.optionDefault(label: label)
                  : label;
            }()),
            selected: seconds == current,
            onSelected: preferences.rememberPosition
                ? (_) => onSelected(seconds)
                : null,
          ),
      ],
    );

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
        rewindOptions(
          current: preferences.tempPlayRewindSeconds,
          isUnset: preferences.stored.tempPlayRewindSeconds == null,
          options: tempPlayRewindOptionsSeconds,
          onSelected: (seconds) =>
              unawaited(notifier.setTempPlayRewindSeconds(seconds)),
        ),
        SizedBox(height: spacing.x4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.skipPreviewClips),
          subtitle: Text(t.skipPreviewClipsHint),
          value: preferences.skipPreviewClips,
          onChanged: (skip) => unawaited(notifier.setSkipPreviewClips(skip)),
        ),
        SizedBox(height: spacing.x4),
        heading(t.restartRewind, t.restartRewindHint),
        rewindOptions(
          current: preferences.restartRewindSeconds,
          isUnset: preferences.stored.restartRewindSeconds == null,
          options: restartRewindOptionsSeconds,
          onSelected: (seconds) =>
              unawaited(notifier.setRestartRewindSeconds(seconds)),
        ),
        SizedBox(height: spacing.x4),
        heading(t.playHistoryLimit, t.playHistoryLimitHint),
        Wrap(
          spacing: spacing.x2,
          runSpacing: spacing.x2,
          children: [
            for (final limit in {
              ...playHistoryLimitOptions,
              preferences.playHistoryLimit,
            }.toList()..sort())
              ChoiceChip(
                label: Text(
                  defaultLabel(
                    t.playHistoryLimitOption(
                      // 千分位：三種介面語言都寫成 10,000。
                      count: NumberFormat.decimalPattern('en').format(limit),
                    ),
                    isDefault:
                        preferences.stored.playHistoryLimit == null &&
                        limit == preferences.playHistoryLimit,
                  ),
                ),
                selected: limit == preferences.playHistoryLimit,
                onSelected: (_) =>
                    unawaited(notifier.setPlayHistoryLimit(limit)),
              ),
          ],
        ),
        SizedBox(height: spacing.x4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.autoScrollToCurrent),
          subtitle: Text(t.autoScrollToCurrentHint),
          value: preferences.autoScrollToCurrent,
          onChanged: (enabled) =>
              unawaited(notifier.setAutoScrollToCurrent(enabled)),
        ),
      ],
    );
  }
}
