import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/playback/playback_controller.dart' show OutputDeviceState;
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
/// 控制項依它所在的寬度（最近的 `WindowClassScope`）分三段：
///
/// - compact（< 600）：播放、下一首；
/// - medium（600–839）：上一首、播放、下一首、音量圖示（點開彈出式滑桿，裡面也能
///   靜音）、「⋯」（隨機、循環、輸出裝置）；
/// - expanded 以上：隨機、上一首、播放、下一首、循環，控制與進度條置中；右側是
///   輸出裝置、靜音鈕與音量滑桿。輸出裝置只在平台宣告能選時（Windows）有。
///
/// 曲名至少約 160dp（ADR 0024 §決定 5）。曲名、上傳者、封面是佇列項目的
/// `TrackInfo`；狀態都來自 `PlaybackController`。點空白處開播放頁在 M2 PR 18a。
///
/// 只有圖示的按鈕以 tooltip（附按鍵）當名稱，不另外給 `Icon.semanticLabel`：兩個都給
/// 輔助技術會念成「X. X」。
///
/// 曲名下面那一行在「重試中」「等待網路連線」「試聽」時先寫狀態再接上傳者，
/// 三種寬度都在曲名欄裡，不另外佔位置。
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
    final previewing = ref.watch(playbackPreviewProvider).value ?? false;
    final t = ref.watch(translationsProvider).player;
    final status = switch (state) {
      Retrying(waitingForNetwork: true) => t.waitingForNetwork,
      Retrying() => t.retrying,
      _ when previewing => t.preview,
      _ => null,
    };
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
          child: _TrackText(
            title: current.title,
            uploader: current.uploader,
            status: status,
          ),
        ),
      ],
    );
    final previous = IconButton(
      tooltip: t.previousTooltip,
      icon: const Icon(Icons.skip_previous),
      // 第一首時回到這首開頭，所以一直可以按。
      onPressed: () =>
          unawaited(ref.read(playbackControllerProvider).previous()),
    );
    final next = IconButton(
      tooltip: t.nextTooltip,
      icon: const Icon(Icons.skip_next),
      onPressed: queue.hasNext
          ? () => unawaited(ref.read(playbackControllerProvider).next())
          : null,
    );
    final playPause = _PlayPauseButton(state: state);
    final shuffle = _ShuffleButton(enabled: queue.shuffleEnabled);
    final loop = _LoopButton(mode: queue.loopMode);
    const progress = _ProgressRow();
    final selectsDevice = ref.watch(outputDeviceSelectionProvider);

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
                  const _VolumeMenu(),
                  _MoreMenu(queue: queue, selectsDevice: selectsDevice),
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
              Expanded(
                flex: 3,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selectsDevice) const _OutputDeviceButton(),
                      const _MuteButton(),
                      const SizedBox(
                        width: AppLayout.volumeSliderWidth,
                        child: _VolumeSlider(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _TrackText extends StatelessWidget {
  const _TrackText({
    required this.title,
    required this.uploader,
    required this.status,
  });

  final String title;
  final String? uploader;

  /// 播放的狀態標示（重試中、等待網路連線、試聽）；沒有時為 `null`。
  final String? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uploader = this.uploader;
    final status = this.status;
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
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
        if (status != null || uploader != null)
          // 一行、放不下就省略：窄的時候狀態在前面，先看得到。狀態改變時讀出來
          // （live region），不搶焦點。
          Semantics(
            liveRegion: status != null,
            child: Text.rich(
              TextSpan(
                children: [
                  if (status != null)
                    TextSpan(
                      text: status,
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  if (status != null && uploader != null)
                    WidgetSpan(
                      child: SizedBox(width: AppTokens.of(context).spacing.x2),
                    ),
                  if (uploader != null) TextSpan(text: uploader),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle,
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
      tooltip: t.shuffleTooltip,
      isSelected: enabled,
      icon: const Icon(Icons.shuffle),
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

/// medium 寬度的「⋯」：隨機、循環與（能選時的）輸出裝置（ADR 0024 §決定 5）。
class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.queue, required this.selectsDevice});

  final QueueState queue;
  final bool selectsDevice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    final t = translations.player;
    final devices = selectsDevice
        ? ref.watch(playbackOutputDevicesProvider).value
        : null;
    return _IconMenu(
      tooltip: t.more,
      icon: const Icon(Icons.more_horiz),
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
        if (selectsDevice)
          SubmenuButton(
            leadingIcon: const Icon(Icons.speaker),
            menuChildren: _deviceItems(
              t,
              devices ?? (devices: const [], selected: null),
              (device) => unawaited(
                ref.read(playbackControllerProvider).selectOutputDevice(device),
              ),
            ),
            child: Text(t.outputDevice),
          ),
      ],
    );
  }
}

/// 以一個圖示鈕打開的選單。按鈕與 `MenuAnchor` 共用一個 `FocusNode`
/// （`childFocusNode`，Flutter `MenuAnchor` 文件的寫法）：選單打開時焦點移到
/// 按鈕、在選單的快捷鍵之內，以滑鼠打開的也能以 Esc 關掉、以方向鍵進入選單。
/// 沒有它的話焦點留在外殼，Esc 到不了選單。
class _IconMenu extends StatefulWidget {
  const _IconMenu({
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
  State<_IconMenu> createState() => _IconMenuState();
}

class _IconMenuState extends State<_IconMenu> {
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

/// 輸出裝置選單的項目：「系統預設」與後端列出的裝置，目前的打勾。選了就交給
/// 控制器（它也記成偏好）。
List<Widget> _deviceItems(
  Translations$player$zh_TW t,
  OutputDeviceState state,
  void Function(OutputDevice? device) select,
) {
  Widget item(String label, OutputDevice? device) {
    final selected = state.selected == device;
    return Semantics(
      selected: selected,
      child: MenuItemButton(
        leadingIcon: Visibility.maintain(
          visible: selected,
          child: const Icon(Icons.check),
        ),
        onPressed: () => select(device),
        child: Text(label),
      ),
    );
  }

  return [
    item(t.systemDefault, null),
    for (final device in state.devices) item(device.name, device),
  ];
}

/// 輸出裝置鈕（expanded 以上，平台能選時）。
class _OutputDeviceButton extends ConsumerWidget {
  const _OutputDeviceButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).player;
    final state =
        ref.watch(playbackOutputDevicesProvider).value ??
        (devices: const <OutputDevice>[], selected: null);
    return _IconMenu(
      tooltip: t.outputDevice,
      isSelected: state.selected != null,
      icon: const Icon(Icons.speaker),
      menuChildren: _deviceItems(
        t,
        state,
        (device) => unawaited(
          ref.read(playbackControllerProvider).selectOutputDevice(device),
        ),
      ),
    );
  }
}

/// 音量圖示：靜音或 0 是 off，未滿一半是 down。
IconData volumeIcon(double volume, {required bool muted}) => switch (volume) {
  _ when muted || volume <= 0 => Icons.volume_off,
  < 0.5 => Icons.volume_down,
  _ => Icons.volume_up,
};

/// 靜音鈕：切換靜音，圖示反映靜音與音量大小。
class _MuteButton extends ConsumerWidget {
  const _MuteButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).player;
    final state =
        ref.watch(playbackVolumeProvider).value ?? (volume: 1.0, muted: false);
    return IconButton(
      tooltip: state.muted ? t.unmute : t.mute,
      icon: Icon(volumeIcon(state.volume, muted: state.muted)),
      onPressed: () =>
          unawaited(ref.read(playbackControllerProvider).toggleMute()),
    );
  }
}

/// 音量滑桿（0–100%）：拖曳時即時套用，`setVolume` 同時取消靜音；音量拖到 0 不算
/// 靜音（靜音與音量分開記）。
class _VolumeSlider extends ConsumerStatefulWidget {
  const _VolumeSlider({this.autofocus = false});

  /// 彈出的選單裡一開就拿焦點：Esc 才由選單接去關閉。
  final bool autofocus;

  @override
  ConsumerState<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends ConsumerState<_VolumeSlider> {
  /// 拖動中的值（0–100）；沒在拖是 `null`，免得跟 stream 的更新差一拍。
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).player;
    final volume = ref.watch(playbackVolumeProvider).value?.volume ?? 1.0;
    final value = (_dragging ?? volume * 100).clamp(0.0, 100.0);
    return Semantics(
      label: t.volume,
      child: Slider(
        autofocus: widget.autofocus,
        value: value,
        max: 100,
        semanticFormatterCallback: (value) => '${value.round()}%',
        onChanged: (value) {
          setState(() => _dragging = value);
          unawaited(
            ref.read(playbackControllerProvider).setVolume(value / 100),
          );
        },
        onChangeEnd: (_) => setState(() => _dragging = null),
      ),
    );
  }
}

/// medium 寬度的音量圖示：點開彈出式滑桿，裡面也能切靜音。
class _VolumeMenu extends ConsumerWidget {
  const _VolumeMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).player;
    final state =
        ref.watch(playbackVolumeProvider).value ?? (volume: 1.0, muted: false);
    return _IconMenu(
      tooltip: t.volumeTooltip,
      icon: Icon(volumeIcon(state.volume, muted: state.muted)),
      menuChildren: const [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MuteButton(),
            SizedBox(
              width: AppLayout.volumeSliderWidth,
              child: _VolumeSlider(autofocus: true),
            ),
          ],
        ),
      ],
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
          : Icon(wantsSound ? Icons.pause : Icons.play_arrow),
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
