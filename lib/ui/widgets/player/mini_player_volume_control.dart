import 'package:flutter/material.dart';

import '../../../core/constants/breakpoints.dart';
import '../../../core/constants/ui_constants.dart';
import '../../../core/utils/icon_helpers.dart';
import '../../../services/audio/audio_provider.dart';

/// 迷你播放器音量控制（僅桌面端顯示），音樂/電台迷你播放器共用。
///
/// 兩個迷你播放器原本各自維護一份逐字相同的實作；抽出為單一元件以保證
/// 樣式一致。窄屏（`Breakpoints.isMobile`）使用彈出式直式滑塊，寬屏使用
/// 靜音鈕 + 橫式滑塊。滑塊規格與 `CompactVolumeControl` 相同
/// （trackHeight 3、thumbRadius 5、overlayRadius 10）。tooltip 文案因
/// i18n namespace 不同（音樂用 t.player、電台用 t.radio）由呼叫端傳入。
class MiniPlayerVolumeControl extends StatelessWidget {
  final double volume;
  final AudioController controller;
  final ColorScheme colorScheme;
  final String volumeTooltip;
  final String muteTooltip;
  final String unmuteTooltip;

  const MiniPlayerVolumeControl({
    super.key,
    required this.volume,
    required this.controller,
    required this.colorScheme,
    required this.volumeTooltip,
    required this.muteTooltip,
    required this.unmuteTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = Breakpoints.isMobile(MediaQuery.sizeOf(context).width);

    // 窄屏時使用彈出式直式滑塊。
    if (isNarrow) {
      return MenuAnchor(
        builder: (context, menuController, child) {
          return IconButton(
            icon: Icon(getVolumeIcon(volume), size: 20),
            visualDensity: VisualDensity.compact,
            tooltip: volumeTooltip,
            onPressed: () {
              if (menuController.isOpen) {
                menuController.close();
              } else {
                menuController.open();
              }
            },
          );
        },
        style: MenuStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusLg),
          ),
        ),
        alignmentOffset: const Offset(0, -170),
        menuChildren: [
          SizedBox(
            width: 40,
            height: 120,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: _sliderThemeData,
                child: Slider(
                  value: volume,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (value) => controller.setVolume(value),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 寬屏時顯示靜音鈕 + 橫式滑塊。
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
            data: _sliderThemeData,
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

  /// 與 `CompactVolumeControl` 共用的滑塊規格。
  SliderThemeData get _sliderThemeData => SliderThemeData(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.2),
      );
}
