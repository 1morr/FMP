import 'dart:io' show Platform;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/icon_helpers.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../services/radio/radio_controller.dart';

/// 電台播放器頁面（全屏）
class RadioPlayerPage extends ConsumerWidget {
  const RadioPlayerPage({super.key});

  /// 是否為桌面平台
  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final radioState = ref.watch(radioControllerProvider);
    final radioController = ref.read(radioControllerProvider.notifier);
    final audioState = ref.watch(audioControllerProvider);
    final audioController = ref.read(audioControllerProvider.notifier);

    final station = radioState.currentStation;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('電台'),
        actions: [
          if (isDesktop)
            _buildCompactVolumeControl(
                context, audioState, audioController, colorScheme),
        ],
      ),
      body: station == null
          ? const Center(child: Text('沒有正在播放的電台'))
          : SafeArea(
              child: Column(
                children: [
                  // 封面區域
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.surfaceContainerHighest,
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.shadow.withValues(alpha: 0.2),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: station.thumbnailUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: station.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        _buildCoverPlaceholder(colorScheme),
                                    errorWidget: (context, url, error) =>
                                        _buildCoverPlaceholder(colorScheme),
                                  )
                                : _buildCoverPlaceholder(colorScheme),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 資訊區域
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        // 標題
                        Text(
                          station.title,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        // 主播名稱
                        if (station.hostName != null)
                          Text(
                            station.hostName!,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 8),
                        // 狀態行
                        _buildInfoRow(radioState, colorScheme, context),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 控制區域
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: _buildControls(
                        radioState, radioController, colorScheme),
                  ),

                  const SizedBox(height: 48),
                ],
              ),
            ),
    );
  }

  Widget _buildCoverPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.radio,
        size: 80,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _buildInfoRow(
    RadioState radioState,
    ColorScheme colorScheme,
    BuildContext context,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // LIVE 標記
        if (radioState.isPlaying) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],

        // 已播放時長
        if (radioState.isPlaying)
          Text(
            _formatDuration(radioState.playDuration),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),

        // 觀眾數
        if (radioState.viewerCount != null) ...[
          if (radioState.isPlaying)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '·',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          Text(
            '${_formatCount(radioState.viewerCount!)} 觀看',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],

        // 重連/緩衝
        if (radioState.isReconnecting)
          Text(
            '重連中...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.error,
                ),
          ),
        if (radioState.isBuffering && !radioState.isReconnecting)
          Text(
            '緩衝中...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
      ],
    );
  }

  Widget _buildControls(
    RadioState state,
    RadioController controller,
    ColorScheme colorScheme,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 播放/停止按鈕（大）
        SizedBox(
          width: 64,
          height: 64,
          child: state.isBuffering || state.isLoading
              ? Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: colorScheme.primary,
                      strokeWidth: 3,
                    ),
                  ),
                )
              : IconButton.filled(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    state.isPlaying ? Icons.stop : Icons.play_arrow,
                    size: 36,
                  ),
                  onPressed: () {
                    if (state.isPlaying) {
                      controller.stop();
                    } else if (state.currentStation != null) {
                      controller.play(state.currentStation!);
                    }
                  },
                ),
        ),
      ],
    );
  }

  /// 緊湊音量控制（AppBar 內使用）
  Widget _buildCompactVolumeControl(
    BuildContext context,
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(getVolumeIcon(state.volume), size: 20),
          visualDensity: VisualDensity.compact,
          tooltip: state.volume > 0 ? '靜音' : '取消靜音',
          onPressed: () => controller.toggleMute(),
        ),
        SizedBox(
          width: 100,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.surfaceContainerHighest,
              thumbColor: colorScheme.primary,
              overlayColor: colorScheme.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: state.volume,
              min: 0.0,
              max: 1.0,
              onChanged: (value) => controller.setVolume(value),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}萬';
    }
    return count.toString();
  }
}
