import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 播放列（ADR 0024 §決定 5）：封面、曲名、上傳者、播放控制與可拖動的進度條。
/// 佇列是空的時候不佔位置。
///
/// 控制項依它所在的寬度（最近的 `WindowClassScope`）分三段，只放已經有的功能：
///
/// - compact（< 600）：播放、下一首；
/// - medium（600–839）：上一首、播放、下一首、「⋯」（隨機、循環；ADR 的音量
///   圖示與輸出裝置在 M2 PR 13）；
/// - expanded 以上：隨機、上一首、播放、下一首、循環，控制與進度條置中，右側
///   留給 PR 13 的輸出裝置與音量。
///
/// 曲名至少約 160dp（ADR 0024 §決定 5）。曲名、上傳者、封面是佇列項目的
/// `TrackInfo`；狀態都來自 `PlaybackController`。點空白處開播放頁在 M2 PR 18a。
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  /// 曲名與上傳者那一欄；測試以它量曲名的寬度。
  static const titleKey = ValueKey('player-bar-title');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(playbackQueueProvider).value;
    final current = queue?.current;
    if (queue == null || current == null) return const SizedBox.shrink();
    final state = ref.watch(playbackStateProvider).value ?? const Idle();
    final t = ref.watch(translationsProvider).player;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;

    final track = Row(
      children: [
        ArtworkImage(
          pluginId: current.sourceTypeId,
          artwork: current.artwork,
          size: AppLayout.artworkThumbnail,
        ),
        SizedBox(width: spacing.x3),
        Expanded(
          key: titleKey,
          child: _TrackText(title: current.title, uploader: current.uploader),
        ),
      ],
    );
    final previous = IconButton(
      tooltip: t.previousTooltip,
      icon: Icon(Icons.skip_previous, semanticLabel: t.previous),
      // 第一首時回到這首開頭，所以一直可以按。
      onPressed: () =>
          unawaited(ref.read(playbackControllerProvider).previous()),
    );
    final next = IconButton(
      tooltip: t.nextTooltip,
      icon: Icon(Icons.skip_next, semanticLabel: t.next),
      onPressed: queue.hasNext
          ? () => unawaited(ref.read(playbackControllerProvider).next())
          : null,
    );
    final playPause = _PlayPauseButton(state: state);
    final shuffle = _ShuffleButton(enabled: queue.shuffleEnabled);
    final loop = _LoopButton(mode: queue.loopMode);
    const progress = _ProgressRow();

    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.x4,
          vertical: spacing.x2,
        ),
        child: switch (WindowClass.of(context)) {
          WindowClass.compact => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              progress,
              Row(
                children: [
                  Expanded(child: track),
                  playPause,
                  next,
                ],
              ),
            ],
          ),
          WindowClass.medium => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              progress,
              Row(
                children: [
                  Expanded(child: track),
                  previous,
                  playPause,
                  next,
                  _MoreMenu(queue: queue),
                ],
              ),
            ],
          ),
          // 3：4：3 讓 840 寬時曲名仍有約 180dp。
          WindowClass.expanded ||
          WindowClass.large ||
          WindowClass.extraLarge => Row(
            children: [
              Expanded(flex: 3, child: track),
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [shuffle, previous, playPause, next, loop],
                    ),
                    progress,
                  ],
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        },
      ),
    );
  }
}

class _TrackText extends StatelessWidget {
  const _TrackText({required this.title, required this.uploader});

  final String title;
  final String? uploader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uploader = this.uploader;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        if (uploader != null)
          Text(
            uploader,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// 隨機開關（ADR 0018 §決定 5：隨機以位置為單位）。
class _ShuffleButton extends ConsumerWidget {
  const _ShuffleButton({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).player;
    return IconButton(
      tooltip: t.shuffle,
      isSelected: enabled,
      icon: Icon(Icons.shuffle, semanticLabel: t.shuffle),
      onPressed: () =>
          ref.read(playbackControllerProvider).setShuffle(!enabled),
    );
  }
}

/// 循環：按一下依關閉 → 全部 → 單曲輪轉（舊版 `cycleLoopMode`）。
class _LoopButton extends ConsumerWidget {
  const _LoopButton({required this.mode});

  final LoopMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = loopLabel(ref.watch(translationsProvider), mode);
    return IconButton(
      tooltip: label,
      isSelected: mode != LoopMode.off,
      icon: Icon(loopIcon(mode), semanticLabel: label),
      onPressed: () => ref.read(playbackControllerProvider).cycleLoopMode(),
    );
  }
}

/// 循環模式的圖示：單曲是 `repeat_one`，其他是 `repeat`（關閉時不選取）。
IconData loopIcon(LoopMode mode) => switch (mode) {
  LoopMode.off || LoopMode.all => Icons.repeat,
  LoopMode.one => Icons.repeat_one,
};

/// 循環模式的名稱（tooltip 與語意標籤）。
String loopLabel(Translations t, LoopMode mode) => switch (mode) {
  LoopMode.off => t.player.loopOff,
  LoopMode.all => t.player.loopAll,
  LoopMode.one => t.player.loopOne,
};

/// medium 寬度的「⋯」：隨機與循環（ADR 0024 §決定 5）。
class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.queue});

  final QueueState queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    final t = translations.player;
    return MenuAnchor(
      menuChildren: [
        CheckboxMenuButton(
          value: queue.shuffleEnabled,
          onChanged: (_) => ref
              .read(playbackControllerProvider)
              .setShuffle(!queue.shuffleEnabled),
          child: Text(t.shuffle),
        ),
        MenuItemButton(
          leadingIcon: Icon(loopIcon(queue.loopMode)),
          onPressed: () => ref.read(playbackControllerProvider).cycleLoopMode(),
          child: Text(loopLabel(translations, queue.loopMode)),
        ),
      ],
      builder: (context, menu, _) => IconButton(
        tooltip: t.more,
        icon: Icon(Icons.more_horiz, semanticLabel: t.more),
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

/// 播放／暫停。載入、緩衝與等重試時在按鈕裡轉圈，按下是暫停（使用者要的是
/// 「別播了」）。
class _PlayPauseButton extends ConsumerWidget {
  const _PlayPauseButton({required this.state});

  final PlaybackState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).player;
    final busy = switch (state) {
      Loading() || Buffering() || Retrying() => true,
      Idle() || Playing() || Paused() || Failed() => false,
    };
    final wantsSound = busy || state is Playing;
    return IconButton.filled(
      tooltip: wantsSound ? t.pauseTooltip : t.playTooltip,
      onPressed: () {
        final controller = ref.read(playbackControllerProvider);
        unawaited(wantsSound ? controller.pause() : controller.play());
      },
      icon: busy
          ? SizedBox.square(
              dimension: IconTheme.of(context).size,
              child: CircularProgressIndicator(
                semanticsLabel: t.loading,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : Icon(
              wantsSound ? Icons.pause : Icons.play_arrow,
              semanticLabel: wantsSound ? t.pause : t.play,
            ),
    );
  }
}

/// 位置、進度條、時長。拖動時只改畫面上的位置，放開才 seek。
class _ProgressRow extends ConsumerStatefulWidget {
  const _ProgressRow();

  @override
  ConsumerState<_ProgressRow> createState() => _ProgressRowState();
}

class _ProgressRowState extends ConsumerState<_ProgressRow> {
  /// 拖動中的位置（毫秒）；沒在拖是 `null`。
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).player;
    final theme = Theme.of(context);
    final progress = ref.watch(playbackProgressProvider).value;
    final duration = progress?.duration;
    final max = duration?.inMilliseconds.toDouble() ?? 0;
    final seekable = max > 0;
    final position = seekable
        ? (_dragging ?? progress!.position.inMilliseconds.toDouble()).clamp(
            0.0,
            max,
          )
        : 0.0;
    final timeStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Duration at(double milliseconds) =>
        Duration(milliseconds: milliseconds.round());
    return Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppLayout.playerTimeLabel,
          ),
          child: Text(
            formatDuration(at(position)),
            style: timeStyle,
            textAlign: TextAlign.end,
          ),
        ),
        Expanded(
          child: Semantics(
            label: t.progress,
            child: Slider(
              value: position,
              max: seekable ? max : 1,
              semanticFormatterCallback: (value) => formatDuration(at(value)),
              onChanged: seekable
                  ? (value) => setState(() => _dragging = value)
                  : null,
              onChangeEnd: seekable
                  ? (value) {
                      setState(() => _dragging = null);
                      unawaited(
                        ref.read(playbackControllerProvider).seek(at(value)),
                      );
                    }
                  : null,
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppLayout.playerTimeLabel,
          ),
          child: Text(
            duration == null ? '-:--' : formatDuration(duration),
            style: timeStyle,
          ),
        ),
      ],
    );
  }
}
