import 'package:flutter/material.dart';

import '../../../core/utils/icon_helpers.dart';
import '../../../services/audio/audio_provider.dart';

/// 緊湊音量控制（AppBar 內使用），音樂/電台全螢幕播放器共用。
///
/// 兩個播放器頁面原本各自維護一份逐字相同的實作；抽出為單一元件以保證樣式
/// 一致、避免未來漂移。音量圖示與滑塊樣式（trackHeight 3、thumbRadius 5、
/// overlayRadius 10）為兩頁共用規格。tooltip 文案因 i18n namespace 不同
/// （音樂用 t.player、電台用 t.radio）由呼叫端傳入。
class CompactVolumeControl extends StatelessWidget {
  final double volume;
  final AudioController controller;
  final ColorScheme colorScheme;
  final String muteTooltip;
  final String unmuteTooltip;

  const CompactVolumeControl({
    super.key,
    required this.volume,
    required this.controller,
    required this.colorScheme,
    required this.muteTooltip,
    required this.unmuteTooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(getVolumeIcon(volume), size: 20),
          visualDensity: VisualDensity.compact,
          // 目前有音量 → 按鈕用於靜音；已靜音 → 顯示取消靜音。
          tooltip: volume > 0 ? muteTooltip : unmuteTooltip,
          onPressed: () => controller.toggleMute(),
        ),
        SizedBox(
          width: 100,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.surfaceContainerHighest,
              thumbColor: colorScheme.primary,
              overlayColor: colorScheme.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: volume,
              min: 0.0,
              max: 1.0,
              onChanged: (value) => controller.setVolume(value),
            ),
          ),
        ),
      ],
    );
  }
}
