import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/output_device.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/playback/playback_controller.dart' show OutputDeviceState;
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/player/player_controls.dart';

// 播放列與播放頁頂列共用的音量與輸出裝置控制（design §4）。

/// 輸出裝置選單的項目：「系統預設」與後端列出的裝置，目前的打勾。選了就交給
/// 控制器（它也記成偏好）。
List<Widget> outputDeviceItems(
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

/// 輸出裝置鈕（平台能選時才放）。
class OutputDeviceButton extends ConsumerWidget {
  const OutputDeviceButton({super.key});

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
      menuChildren: outputDeviceItems(
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
class MuteButton extends ConsumerWidget {
  const MuteButton({super.key});

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
class VolumeSlider extends ConsumerStatefulWidget {
  const VolumeSlider({super.key, this.autofocus = false});

  /// 彈出的選單裡一開就拿焦點：Esc 才由選單接去關閉。
  final bool autofocus;

  @override
  ConsumerState<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends ConsumerState<VolumeSlider> {
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
