import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';

// 播放列與播放頁共用的播放控制（M2 PR 18a 從 `player_bar.dart` 抽出）：隨機、循環、
// 播放暫停、進度條、以圖示鈕打開的選單，以及曲名下那一行的狀態標示。
// 規則與閘門見 `app/AGENTS.md` § 介面；只有圖示的按鈕以 tooltip 當名稱，不另外給
// `Icon.semanticLabel`。

/// 播放的狀態標示（重試中、等待網路連線、試聽）；都不是時為 `null`。
String? playbackStatusLabel(
  Translations$player$zh_TW t,
  PlaybackState state, {
  required bool previewing,
}) => switch (state) {
  Retrying(waitingForNetwork: true) => t.waitingForNetwork,
  Retrying() => t.retrying,
  _ when previewing => t.preview,
  _ => null,
};

/// 上一首。第一首時回到這首開頭，所以一直可以按。
class PreviousButton extends ConsumerWidget {
  const PreviousButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).player;
    return IconButton(
      tooltip: t.previousTooltip,
      icon: const Icon(Icons.skip_previous),
      onPressed: () =>
          unawaited(ref.read(playbackControllerProvider).previous()),
    );
  }
}

/// 下一首；沒有下一首（也不循環）時停用。
class NextButton extends ConsumerWidget {
  const NextButton({super.key, required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).player;
    return IconButton(
      tooltip: t.nextTooltip,
      icon: const Icon(Icons.skip_next),
      onPressed: enabled
          ? () => unawaited(ref.read(playbackControllerProvider).next())
          : null,
    );
  }
}

/// 隨機開關（ADR 0018 §決定 5：隨機以位置為單位）。
class ShuffleButton extends ConsumerWidget {
  const ShuffleButton({super.key, required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).player;
    return IconButton(
      tooltip: t.shuffleTooltip,
      isSelected: enabled,
      icon: const Icon(Icons.shuffle),
      onPressed: () =>
          ref.read(playbackControllerProvider).setShuffle(!enabled),
    );
  }
}

/// 循環：按一下依關閉 → 全部 → 單曲輪轉（舊版 `cycleLoopMode`）。
class LoopButton extends ConsumerWidget {
  const LoopButton({super.key, required this.mode});

  final LoopMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).player;
    return IconButton(
      tooltip: loopTooltip(t, mode),
      isSelected: mode != LoopMode.off,
      icon: Icon(loopIcon(mode)),
      onPressed: () => ref.read(playbackControllerProvider).cycleLoopMode(),
    );
  }
}

/// 循環模式的圖示：單曲是 `repeat_one`，其他是 `repeat`（關閉時不選取）。
IconData loopIcon(LoopMode mode) => switch (mode) {
  LoopMode.off || LoopMode.all => Icons.repeat,
  LoopMode.one => Icons.repeat_one,
};

/// 循環模式的 tooltip：名稱附按鍵 Ctrl+R（同時是按鈕的語意名稱）。
String loopTooltip(Translations$player$zh_TW t, LoopMode mode) =>
    switch (mode) {
      LoopMode.off => t.loopOffTooltip,
      LoopMode.all => t.loopAllTooltip,
      LoopMode.one => t.loopOneTooltip,
    };

/// 循環模式的名稱（選單項目）。
String loopLabel(Translations t, LoopMode mode) => switch (mode) {
  LoopMode.off => t.player.loopOff,
  LoopMode.all => t.player.loopAll,
  LoopMode.one => t.player.loopOne,
};

/// 以一個圖示鈕打開的選單。按鈕與 `MenuAnchor` 共用一個 `FocusNode`
/// （`childFocusNode`，Flutter `MenuAnchor` 文件的寫法）：選單打開時焦點移到
/// 按鈕、在選單的快捷鍵之內，以滑鼠打開的也能以 Esc 關掉、以方向鍵進入選單。
/// 沒有它的話焦點留在外殼，Esc 到不了選單。
class IconMenu extends StatefulWidget {
  const IconMenu({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.menuChildren,
    this.isSelected,
  });

  final String tooltip;
  final Widget icon;
  final List<Widget> menuChildren;
  final bool? isSelected;

  @override
  State<IconMenu> createState() => _IconMenuState();
}

class _IconMenuState extends State<IconMenu> {
  final _button = FocusNode(debugLabel: 'menu button');

  @override
  void dispose() {
    _button.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    childFocusNode: _button,
    menuChildren: widget.menuChildren,
    builder: (context, menu, _) => IconButton(
      focusNode: _button,
      tooltip: widget.tooltip,
      isSelected: widget.isSelected,
      icon: widget.icon,
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
    ),
  );
}

/// 播放／暫停。載入、緩衝與等重試時在按鈕裡轉圈，按下是暫停（使用者要的是
/// 「別播了」）。
class PlayPauseButton extends ConsumerWidget {
  const PlayPauseButton({super.key, required this.state});

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
          : Icon(wantsSound ? Icons.pause : Icons.play_arrow),
    );
  }
}

/// 位置、進度條、時長。拖動時只改畫面上的位置，放開才 seek。
class ProgressRow extends ConsumerStatefulWidget {
  const ProgressRow({super.key});

  @override
  ConsumerState<ProgressRow> createState() => _ProgressRowState();
}

class _ProgressRowState extends ConsumerState<ProgressRow> {
  /// 拖動中的位置（毫秒）；沒在拖是 `null`。
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).player;
    final theme = Theme.of(context);
    final progress = ref.watch(playbackProgressProvider).value;
    final current = ref.watch(playbackQueueProvider).value?.current;
    final idle =
        (ref.watch(playbackStateProvider).value ?? const Idle()) is Idle;
    // `Idle` 時沒有來源，進度 stream 留著上一個來源最後的回報（臨時播放、清空之
    // 前的歌），不是這首。按播放從哪裡開始就顯示哪裡：啟動恢復後還沒播（含先臨時
    // 播放、結束後停著）是恢復的位置，拖動就是改起點（沒有來源時控制器的 seek 改
    // 的是它）；其他從頭開始，不能拖。時長是曲目的。
    if (idle) ref.watch(playbackSeeksProvider);
    final restored = idle
        ? ref.read(playbackControllerProvider).restoredPosition
        : null;
    final duration = idle ? current?.duration : progress?.duration;
    final startsAt = idle
        ? restored ?? Duration.zero
        : progress?.position ?? Duration.zero;
    final max = duration?.inMilliseconds.toDouble() ?? 0;
    final seekable = max > 0 && (!idle || restored != null);
    final position = seekable
        ? (_dragging ?? startsAt.inMilliseconds.toDouble()).clamp(0.0, max)
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
