import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/output_device.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/playback/playback_controller.dart' show OutputDeviceState;
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/ui/player/player_controls.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/layout_state.dart';
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
/// `TrackInfo`；狀態都來自 `PlaybackController`。點曲名與封面那一塊開播放頁。
///
/// 只有圖示的按鈕以 tooltip（附按鍵）當名稱，不另外給 `Icon.semanticLabel`：兩個都給
/// 輔助技術會念成「X. X」。
///
/// 曲名下面那一行在「重試中」「等待網路連線」「試聽」時先寫狀態再接上傳者，
/// 三種寬度都在曲名欄裡，不另外佔位置。
///
/// [panelToggle] 是整個視窗 >= 840（右側「正在播放」面板可能出現）：expanded 以上那一段在
/// 輸出裝置鈕前多一顆開關面板的鈕，medium 那一段把它放進「⋯」的勾選項。播放列自己的
/// 寬度量不出整個視窗，所以由外殼給。
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key, this.panelToggle = false});

  /// 是否提供開關右側面板的控制（見類別說明）。
  final bool panelToggle;

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
    final status = playbackStatusLabel(t, state, previewing: previewing);
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;

    final trackRow = Row(
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
    // 點曲名與封面那一塊開播放頁；點擊區與右邊的按鈕分開（ADR 0024 §決定 5）。
    final track = _OpenPlayerArea(child: trackRow);
    const previous = PreviousButton();
    final next = NextButton(enabled: queue.hasNext);
    final playPause = PlayPauseButton(state: state);
    final shuffle = ShuffleButton(enabled: queue.shuffleEnabled);
    final loop = LoopButton(mode: queue.loopMode);
    const progress = ProgressRow();
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
                  _MoreMenu(
                    queue: queue,
                    selectsDevice: selectsDevice,
                    panelToggle: panelToggle,
                  ),
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
                      if (panelToggle) const _PanelToggleButton(),
                      if (selectsDevice) const _OutputDeviceButton(),
                      const _MuteButton(),
                      // 開關面板的鈕讓右側變擠時，滑桿先縮短。
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppLayout.volumeSliderWidth,
                          ),
                          child: const _VolumeSlider(),
                        ),
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

/// 曲名與封面那一塊：點一下開播放頁。自己有一個 `FocusNode`，播放頁關掉後焦點回到
/// 這裡。語意是按鈕，名稱是裡面的曲名與上傳者，「開啟播放頁」放在提示（hint）。
class _OpenPlayerArea extends ConsumerStatefulWidget {
  const _OpenPlayerArea({required this.child});

  final Widget child;

  @override
  ConsumerState<_OpenPlayerArea> createState() => _OpenPlayerAreaState();
}

class _OpenPlayerAreaState extends ConsumerState<_OpenPlayerArea> {
  final _focus = FocusNode(debugLabel: 'Open the player');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).playerPage;
    // `InkWell` 只給點擊動作，不標成按鈕。
    return Semantics(
      button: true,
      hint: t.openHint,
      child: InkWell(
        focusNode: _focus,
        onTap: () {
          _focus.requestFocus();
          unawaited(openPlayerPage(context, opener: _focus));
        },
        child: widget.child,
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

/// medium 寬度的「⋯」：隨機、循環與（能選時的）輸出裝置（ADR 0024 §決定 5）。
class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({
    required this.queue,
    required this.selectsDevice,
    required this.panelToggle,
  });

  final QueueState queue;
  final bool selectsDevice;
  final bool panelToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    final t = translations.player;
    final devices = selectsDevice
        ? ref.watch(playbackOutputDevicesProvider).value
        : null;
    final panelExpanded = ref.watch(panelExpandedProvider);
    return IconMenu(
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
        if (panelToggle)
          CheckboxMenuButton(
            value: panelExpanded,
            onChanged: (_) => rememberPanel(ref, expanded: !panelExpanded),
            child: Text(translations.shell.panelMenuItem),
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

/// 開關右側面板的鈕（整個視窗 >= 840 時，expanded 以上那一段），照 Spotify 的
/// 「正在播放」鈕：面板開著時是選取的樣子。
class _PanelToggleButton extends ConsumerWidget {
  const _PanelToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).shell;
    final expanded = ref.watch(panelExpandedProvider);
    return IconButton(
      tooltip: expanded ? t.panelHideTooltip : t.panelShowTooltip,
      isSelected: expanded,
      icon: const Icon(Icons.view_sidebar_outlined),
      selectedIcon: const Icon(Icons.view_sidebar),
      onPressed: () => rememberPanel(ref, expanded: !expanded),
    );
  }
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
    return IconMenu(
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
    return IconMenu(
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
