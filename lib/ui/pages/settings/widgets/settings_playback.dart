part of '../settings_page.dart';

/// 自动跳转到当前播放
class _AutoScrollToPlayingTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playbackSettingsProvider);

    return SwitchListTile(
      secondary: const Icon(Icons.my_location_outlined),
      title: Text(t.settings.autoScrollToPlaying.title),
      subtitle: Text(t.settings.autoScrollToPlaying.subtitle),
      value: settings.autoScrollToCurrentTrack,
      onChanged: settings.isLoading
          ? null
          : (value) {
              ref
                  .read(playbackSettingsProvider.notifier)
                  .setAutoScrollToCurrentTrack(value);
            },
    );
  }
}

/// 记住播放位置
class _RememberPlaybackPositionTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playbackSettingsProvider);
    final isEnabled =
        settings.isLoading ? true : settings.rememberPlaybackPosition;

    return ListTile(
      leading: const Icon(Icons.history_outlined),
      title: Text(t.settings.rememberPosition.title),
      subtitle: Text(isEnabled ? t.general.enabled : t.general.disabled),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEnabled && !settings.isLoading)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: t.settings.rememberPosition.configRewind,
              onPressed: () => showDialog(
                context: context,
                builder: (context) => const _RewindSettingsDialog(),
              ),
            ),
          Switch(
            value: isEnabled,
            onChanged: settings.isLoading
                ? null
                : (value) {
                    ref
                        .read(playbackSettingsProvider.notifier)
                        .setRememberPlaybackPosition(value);
                  },
          ),
        ],
      ),
      onTap: settings.isLoading
          ? null
          : isEnabled
              ? () => showDialog(
                    context: context,
                    builder: (context) => const _RewindSettingsDialog(),
                  )
              : () => ref
                  .read(playbackSettingsProvider.notifier)
                  .setRememberPlaybackPosition(true),
    );
  }
}

/// 自动匹配歌词（含歌词源设置入口）
class _AutoMatchLyricsTile extends ConsumerWidget {
  void _openSourceSettings(BuildContext context) {
    context.push(RoutePaths.lyricsSourceSettings);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioSettings = ref.watch(audioSettingsProvider);
    final isEnabled =
        audioSettings.isLoading ? true : audioSettings.autoMatchLyrics;

    return ListTile(
      leading: const Icon(Icons.lyrics_outlined),
      title: Text(t.settings.autoMatchLyrics.title),
      subtitle: Text(t.settings.autoMatchLyrics.subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEnabled && !audioSettings.isLoading)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: t.settings.lyricsSourceSettings.title,
              onPressed: () => _openSourceSettings(context),
            ),
          Switch(
            value: isEnabled,
            onChanged: audioSettings.isLoading
                ? null
                : (value) {
                    ref
                        .read(audioSettingsProvider.notifier)
                        .setAutoMatchLyrics(value);
                  },
          ),
        ],
      ),
      onTap: audioSettings.isLoading
          ? null
          : isEnabled
              ? () => _openSourceSettings(context)
              : () => ref
                  .read(audioSettingsProvider.notifier)
                  .setAutoMatchLyrics(true),
    );
  }
}

/// 回退时间配置弹窗
class _RewindSettingsDialog extends ConsumerWidget {
  const _RewindSettingsDialog();

  static const _rewindOptions = [0, 3, 5, 10, 15, 30];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playbackSettingsProvider);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.history_outlined),
          const SizedBox(width: 8),
          Text(t.settings.rewindSettings.title),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.settings.rewindSettings.description,
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _buildRewindRow(
              context: context,
              label: t.settings.rewindSettings.restartRewind,
              subtitle: t.settings.rewindSettings.restartRewindSubtitle,
              value: settings.restartRewindSeconds,
              onChanged: (v) => ref
                  .read(playbackSettingsProvider.notifier)
                  .setRestartRewindSeconds(v),
            ),
            const SizedBox(height: 16),
            _buildRewindRow(
              context: context,
              label: t.settings.rewindSettings.tempPlayRewind,
              subtitle: t.settings.rewindSettings.tempPlayRewindSubtitle,
              value: settings.tempPlayRewindSeconds,
              onChanged: (v) => ref
                  .read(playbackSettingsProvider.notifier)
                  .setTempPlayRewindSeconds(v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.general.close),
        ),
      ],
    );
  }

  Widget _buildRewindRow({
    required BuildContext context,
    required String label,
    required String subtitle,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(subtitle,
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _rewindOptions.map((option) {
            final isSelected = option == value;
            return ChoiceChip(
              label: Text(option == 0
                  ? t.settings.rewindSettings.noRewind
                  : t.settings.rewindSettings.seconds(n: option)),
              selected: isSelected,
              onSelected: (_) => onChanged(option),
            );
          }).toList(),
        ),
      ],
    );
  }
}
