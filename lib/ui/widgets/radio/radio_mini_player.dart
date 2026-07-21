import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../core/utils/number_format_utils.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../services/radio/radio_controller.dart';
import '../../router.dart';
import '../images/radio_cover_image.dart';
import '../player/mini_player_desktop_controls.dart';
import '../player/mini_player_play_pause_button.dart';

/// 電台迷你播放器
/// 顯示在頁面底部，展示當前播放的電台資訊和控制按鈕
/// 樣式與音樂迷你播放器一致
class RadioMiniPlayer extends ConsumerStatefulWidget {
  const RadioMiniPlayer({super.key});

  @override
  ConsumerState<RadioMiniPlayer> createState() => _RadioMiniPlayerState();
}

class _RadioMiniPlayerState extends ConsumerState<RadioMiniPlayer> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radioState = ref.watch(radioControllerProvider);
    final radioController = ref.read(radioControllerProvider.notifier);

    // 沒有電台在播放時不顯示
    if (!radioState.hasCurrentStation) {
      return const SizedBox.shrink();
    }

    final station = radioState.currentStation!;

    return GestureDetector(
      onTap: () => context.push(RoutePaths.radioPlayer),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              // 封面
              _buildThumbnail(station),
              const SizedBox(width: 8),

              // 電台資訊
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    _buildStatusRow(radioState, colorScheme, context),
                  ],
                ),
              ),

              // 同步按鈕
              _buildSyncButton(radioState, radioController),

              // 播放/暫停按鈕
              _buildPlayStopButton(radioState, radioController),

              // 重新載入直播按鈕（無條件重連，RadioController.reload）
              _buildReloadButton(radioState, radioController),

              // 桌面端音頻設備選擇器 + 音量控制（與音樂迷你播放器共用）
              if (isDesktopPlatform) const MiniPlayerDesktopControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(dynamic station) {
    return ClipRRect(
      borderRadius: AppRadius.borderRadiusMd,
      child: SizedBox(
        width: 48,
        height: 48,
        child: RadioCoverImage(
          networkUrl: station.thumbnailUrl,
          fit: BoxFit.cover,
          width: 48,
          height: 48,
          variant: RadioCoverVariant.compact,
        ),
      ),
    );
  }

  Widget _buildStatusRow(
    RadioState radioState,
    ColorScheme colorScheme,
    BuildContext context,
  ) {
    final parts = <String>[];

    // 主播名稱
    if (radioState.currentStation?.hostName != null) {
      parts.add(radioState.currentStation!.hostName!);
    }

    // 已播放時長
    if (radioState.isPlaying) {
      parts.add(DurationFormatter.format(radioState.playDuration));
    }

    // 觀眾數
    if (radioState.viewerCount != null) {
      parts.add(
          t.radio.viewersCount(count: _formatCount(radioState.viewerCount!)));
    }

    // 重連/緩衝狀態
    if (radioState.isReconnecting) {
      parts.add(t.radio.reconnecting);
    } else if (radioState.isBuffering) {
      parts.add(t.radio.buffering);
    }

    return Text(
      parts.isEmpty ? t.radio.live : parts.join(' · '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 播放/暫停按鈕
  Widget _buildPlayStopButton(
    RadioState state,
    RadioController controller,
  ) {
    return MiniPlayerPlayPauseButton(
      isPlaying: state.isPlaying,
      isLoading: state.isBuffering || state.isLoading,
      tooltip: state.isPlaying ? t.general.pause : t.general.play,
      onPressed: () {
        if (state.isPlaying) {
          controller.pause();
        } else {
          controller.resume();
        }
      },
    );
  }

  /// 同步按鈕（跳到直播邊緣，無法 seek 則重連；RadioController.sync）
  Widget _buildSyncButton(
    RadioState state,
    RadioController controller,
  ) {
    final isDisabled = state.isBuffering || state.isLoading || !state.isPlaying;

    return IconButton(
      icon: const Icon(
        Icons.sync,
        size: 24,
      ),
      visualDensity: VisualDensity.compact,
      tooltip: t.radio.syncLive,
      onPressed: isDisabled ? null : () => controller.sync(),
    );
  }

  /// 重新載入按鈕（無條件重連直播流，RadioController.reload）
  Widget _buildReloadButton(
    RadioState state,
    RadioController controller,
  ) {
    final isDisabled = state.isBuffering || state.isLoading || !state.isPlaying;

    return IconButton(
      icon: const Icon(
        Icons.refresh,
        size: 24,
      ),
      visualDensity: VisualDensity.compact,
      tooltip: t.radio.reloadLive,
      onPressed: isDisabled ? null : () => controller.reload(),
    );
  }

  String _formatCount(int count) => formatCount(count);
}
