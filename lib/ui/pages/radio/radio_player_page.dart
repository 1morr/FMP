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
          // 桌面端音量控制（緊湊版）
          if (isDesktop)
            _buildCompactVolumeControl(
                context, audioState, audioController, colorScheme),
          // 更多選項
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            offset: const Offset(0, 48),
            onSelected: (value) {
              if (value == 'info') {
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (!context.mounted) return;
                  _showLiveInfoDialog(context, radioState, colorScheme);
                });
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'info',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20),
                    SizedBox(width: 12),
                    Text('信息'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: station == null
          ? const Center(child: Text('沒有正在播放的電台'))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // 封面圖
                  Expanded(
                    flex: 3,
                    child: _buildCoverArt(station, colorScheme),
                  ),
                  const SizedBox(height: 32),

                  // 電台資訊
                  _buildStationInfo(context, radioState, colorScheme),
                  const SizedBox(height: 32),

                  // 狀態行（代替進度條）
                  _buildStatusBar(context, radioState, colorScheme),
                  const SizedBox(height: 24),

                  // 播放控制
                  _buildPlaybackControls(radioState, radioController, colorScheme),
                ],
              ),
            ),
    );
  }

  /// 封面圖
  Widget _buildCoverArt(dynamic station, ColorScheme colorScheme) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: station.thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: station.thumbnailUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => _buildCoverPlaceholder(colorScheme),
                errorWidget: (context, url, error) =>
                    _buildCoverPlaceholder(colorScheme),
              )
            : _buildCoverPlaceholder(colorScheme),
      ),
    );
  }

  Widget _buildCoverPlaceholder(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.radio,
        size: 120,
        color: colorScheme.primary,
      ),
    );
  }

  /// 電台資訊
  Widget _buildStationInfo(
    BuildContext context,
    RadioState state,
    ColorScheme colorScheme,
  ) {
    final station = state.currentStation;

    return Column(
      children: [
        Text(
          station?.title ?? '未知電台',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          station?.hostName ?? '直播中',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// 狀態行（代替進度條，顯示 LIVE 標記、播放時長、觀眾數等）
  Widget _buildStatusBar(
    BuildContext context,
    RadioState state,
    ColorScheme colorScheme,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // LIVE 標記
        if (state.isPlaying) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],

        // 已播放時長
        if (state.isPlaying)
          Text(
            _formatDuration(state.playDuration),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),

        // 觀眾數
        if (state.viewerCount != null) ...[
          if (state.isPlaying)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '·',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          Text(
            '${_formatCount(state.viewerCount!)} 觀眾',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],

        // 重連/緩衝狀態
        if (state.isReconnecting)
          Text(
            '重連中...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.error,
                ),
          ),
        if (state.isBuffering && !state.isReconnecting)
          Text(
            '緩衝中...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
      ],
    );
  }

  /// 播放控制按鈕
  Widget _buildPlaybackControls(
    RadioState state,
    RadioController controller,
    ColorScheme colorScheme,
  ) {
    const double buttonSize = 80;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 播放/停止按鈕（大）
        SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: state.isBuffering || state.isLoading
              ? FilledButton(
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
                )
              : FilledButton(
                  onPressed: () {
                    if (state.isPlaying) {
                      controller.stop();
                    } else if (state.currentStation != null) {
                      controller.play(state.currentStation!);
                    }
                  },
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    minimumSize: const Size(buttonSize, buttonSize),
                    maximumSize: const Size(buttonSize, buttonSize),
                    padding: EdgeInsets.zero,
                  ),
                  child: Icon(
                    state.isPlaying ? Icons.stop : Icons.play_arrow,
                    size: 40,
                  ),
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
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
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

  /// 顯示直播間信息彈窗
  void _showLiveInfoDialog(
    BuildContext context,
    RadioState state,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LiveInfoDialog(state: state),
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

/// 直播間信息彈窗
class _LiveInfoDialog extends ConsumerWidget {
  final RadioState state;

  const _LiveInfoDialog({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final station = state.currentStation;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 頂部拖動手柄
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 標題欄
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '直播間信息',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 內容區域
          Padding(
            padding: const EdgeInsets.all(20),
            child: station == null
                ? const Text('無法獲取直播間信息')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 標題
                      Text(
                        station.title,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 16),

                      // 主播信息
                      if (station.hostName != null)
                        Row(
                          children: [
                            // 主播頭像
                            ClipOval(
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: station.hostAvatarUrl != null
                                    ? Image.network(
                                        station.hostAvatarUrl!,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) =>
                                            _buildAvatarPlaceholder(colorScheme),
                                      )
                                    : _buildAvatarPlaceholder(colorScheme),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                station.hostName!,
                                style: textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 16),

                      // 統計數據
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          // 觀看人數
                          if (state.viewerCount != null)
                            _buildStatItem(
                              context,
                              Icons.visibility_rounded,
                              '${_formatCount(state.viewerCount!)} 觀眾',
                            ),
                          // 已播放時長
                          if (state.isPlaying)
                            _buildStatItem(
                              context,
                              Icons.schedule_outlined,
                              '已播放 ${_formatDuration(state.playDuration)}',
                            ),
                          // 開播時間
                          if (state.liveStartTime != null)
                            _buildStatItem(
                              context,
                              Icons.play_circle_outline,
                              '開播於 ${_formatDateTime(state.liveStartTime!)}',
                            ),
                          // 直播狀態
                          _buildStatItem(
                            context,
                            state.isPlaying
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            state.isPlaying ? '直播中' : '已停止',
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // 直播間連結
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.link,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                station.url,
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPlaceholder(ColorScheme colorScheme) {
    return Container(
      width: 40,
      height: 40,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.person,
        size: 24,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, IconData icon, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: colorScheme.primary.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
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

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays > 0) {
      return '${diff.inDays} 天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} 小時前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} 分鐘前';
    } else {
      return '剛剛';
    }
  }
}
