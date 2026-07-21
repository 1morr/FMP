import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../../../providers/audio/audio_player_selectors.dart';
import '../../../services/audio/audio_provider.dart';
import 'fmp_audio_device_selector.dart';
import 'mini_player_volume_control.dart';

/// 迷你播放器桌面端尾隨控制群（音訊裝置選擇器 + 音量控制），
/// 音樂/電台迷你播放器共用。
///
/// 兩個迷你播放器原本各自維護一份幾乎相同的實作（僅 gutter 8 vs 4、
/// tooltip namespace 不同而漂移）；抽出為單一元件以保證一致。統一使用
/// 8px gutter 與 `t.player` 的音量 tooltip 文案。僅桌面端由呼叫端以
/// `isDesktopPlatform` 判斷後插入。
class MiniPlayerDesktopControls extends ConsumerWidget {
  const MiniPlayerDesktopControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // 只监听音量和音频设备（窄 select，避免對 audioControllerProvider
    // 做全狀態 watch）。
    final volume =
        ref.watch(audioControllerProvider.select((state) => state.volume));
    final desktopAudioDeviceState = ref.watch(desktopAudioDeviceStateProvider);

    final controller = ref.read(audioControllerProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 8),

        // 音频设备选择器
        if (desktopAudioDeviceState.hasSelectableDevices)
          FmpAudioDeviceSelector(
            state: desktopAudioDeviceState,
            controller: controller,
            colorScheme: colorScheme,
          ),

        // 音量控制
        MiniPlayerVolumeControl(
          volume: volume,
          controller: controller,
          colorScheme: colorScheme,
          volumeTooltip: t.player.volume,
          muteTooltip: t.player.mute,
          unmuteTooltip: t.player.unmute,
        ),
      ],
    );
  }
}
