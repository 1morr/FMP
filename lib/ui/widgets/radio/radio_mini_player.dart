import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../../services/radio/radio_controller.dart';
import '../../router.dart';

/// 電台迷你播放器
/// 顯示在頁面底部，展示當前播放的電台資訊和控制按鈕
class RadioMiniPlayer extends ConsumerWidget {
  const RadioMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radioState = ref.watch(radioControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // 沒有電台在播放時不顯示
    if (!radioState.hasCurrentStation) {
      return const SizedBox.shrink();
    }

    final station = radioState.currentStation!;
    final controller = ref.read(radioControllerProvider.notifier);

    return GestureDetector(
      onTap: () => context.go(RoutePaths.radio),
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
              _buildThumbnail(station, colorScheme),
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

              // LIVE 標記
              if (radioState.isPlaying)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
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

              // 載入指示器
              if (radioState.isLoading || radioState.isBuffering)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),

              // 停止按鈕
              IconButton(
                icon: const Icon(Icons.stop),
                iconSize: 28,
                onPressed: () => controller.stop(),
                tooltip: '停止',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(dynamic station, ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: station.thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: station.thumbnailUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                placeholder: (context, url) => _buildPlaceholder(colorScheme),
                errorWidget: (context, url, error) =>
                    _buildPlaceholder(colorScheme),
              )
            : _buildPlaceholder(colorScheme),
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      width: 48,
      height: 48,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.radio,
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
    );
  }

  Widget _buildStatusRow(
    RadioState radioState,
    ColorScheme colorScheme,
    BuildContext context,
  ) {
    final parts = <String>[];

    // 已播放時長
    if (radioState.isPlaying) {
      parts.add(_formatDuration(radioState.playDuration));
    }

    // 觀眾數
    if (radioState.viewerCount != null) {
      parts.add('${_formatCount(radioState.viewerCount!)}觀看');
    }

    // 重連/緩衝狀態
    if (radioState.isReconnecting) {
      parts.add('重連中...');
    } else if (radioState.isBuffering) {
      parts.add('緩衝中...');
    }

    return Text(
      parts.isEmpty ? '直播中' : parts.join(' · '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
