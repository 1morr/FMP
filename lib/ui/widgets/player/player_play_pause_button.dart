import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';

/// 大圓形播放/暫停鈕，音樂/電台全螢幕播放器共用。
///
/// [isLoading] 為真時顯示 CircularProgressIndicator（與兩頁既有行為一致）；
/// 否則依 [isPlaying] 顯示播放或暫停圖示。是否可用由 [enabled] 控制
/// （音樂頁：有當前曲目；電台頁：恆啟用），實際播放/暫停邏輯由呼叫端透過
/// [onPressed] 注入（音樂：togglePlayPause；電台：pause/resume 分支）。
class PlayerPlayPauseButton extends StatelessWidget {
  final bool isLoading;
  final bool isPlaying;
  final bool enabled;
  final VoidCallback? onPressed;
  final ColorScheme colorScheme;

  const PlayerPlayPauseButton({
    super.key,
    required this.isLoading,
    required this.isPlaying,
    required this.enabled,
    required this.onPressed,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    const double buttonSize = AppSizes.playerMainButton;

    if (isLoading) {
      return SizedBox(
        width: buttonSize,
        height: buttonSize,
        child: FilledButton(
          onPressed: null,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            minimumSize: const Size(buttonSize, buttonSize),
            maximumSize: const Size(buttonSize, buttonSize),
            padding: EdgeInsets.zero,
          ),
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              color: colorScheme.onPrimary,
              strokeWidth: 3,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          minimumSize: const Size(buttonSize, buttonSize),
          maximumSize: const Size(buttonSize, buttonSize),
          padding: EdgeInsets.zero,
        ),
        child: Icon(
          isPlaying ? Icons.pause : Icons.play_arrow,
          size: 40,
        ),
      ),
    );
  }
}
