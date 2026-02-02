import 'dart:io' show Platform;
import '../../../core/services/image_loading_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/icon_helpers.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../services/platform/url_launcher_service.dart';
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
              if (value == 'sync') {
                radioController.sync();
              } else if (value == 'info') {
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (!context.mounted) return;
                  _showLiveInfoDialog(context, radioState, colorScheme);
                });
              }
            },
            itemBuilder: (context) {
              final isDisabled = radioState.isBuffering || radioState.isLoading || !radioState.isPlaying;
              return [
                PopupMenuItem(
                  value: 'sync',
                  enabled: !isDisabled,
                  child: Row(
                    children: [
                      Icon(
                        Icons.sync,
                        size: 20,
                        color: isDisabled ? colorScheme.onSurfaceVariant.withValues(alpha: 0.38) : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '同步直播',
                        style: isDisabled
                            ? TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.38))
                            : null,
                      ),
                    ],
                  ),
                ),
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
              ];
            },
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
                  const SizedBox(height: 16),

                  // LIVE 標記
                  _buildLiveTag(radioState),
                  const SizedBox(height: 16),

                  // 狀態行
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
        child: ImageLoadingService.loadImage(
          networkUrl: station.thumbnailUrl,
          placeholder: _buildCoverPlaceholder(colorScheme),
          fit: BoxFit.cover,
        ),
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

  /// 電台資訊（固定高度，避免佈局跳動）
  Widget _buildStationInfo(
    BuildContext context,
    RadioState state,
    ColorScheme colorScheme,
  ) {
    final station = state.currentStation;

    return SizedBox(
      height: 80, // 固定高度：標題兩行 + 間距 + 主播名一行
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
      ),
    );
  }

  /// LIVE 標記（固定高度，避免佈局跳動）
  Widget _buildLiveTag(RadioState state) {
    return SizedBox(
      height: 24,
      child: AnimatedOpacity(
        opacity: state.isPlaying ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
      ),
    );
  }

  /// 狀態行（固定高度，避免佈局跳動）
  Widget _buildStatusBar(
    BuildContext context,
    RadioState state,
    ColorScheme colorScheme,
  ) {
    return SizedBox(
      height: 24, // 固定高度
      child: Text(
        _getStatusText(state),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: state.isReconnecting
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 獲取狀態文字
  String _getStatusText(RadioState state) {
    if (state.isReconnecting) {
      return '重連中...';
    }
    if (state.isBuffering) {
      return '緩衝中...';
    }
    if (!state.isPlaying) {
      return '已暫停';
    }

    final parts = <String>[];
    parts.add(_formatDuration(state.playDuration));
    if (state.viewerCount != null) {
      parts.add('${_formatCount(state.viewerCount!)} 觀眾');
    }
    return parts.join(' · ');
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
        // 播放/暫停按鈕（大）
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
                      controller.pause();
                    } else {
                      controller.resume();
                    }
                  },
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    minimumSize: const Size(buttonSize, buttonSize),
                    maximumSize: const Size(buttonSize, buttonSize),
                    padding: EdgeInsets.zero,
                  ),
                  child: Icon(
                    state.isPlaying ? Icons.pause : Icons.play_arrow,
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
class _LiveInfoDialog extends StatefulWidget {
  final RadioState state;

  const _LiveInfoDialog({required this.state});

  @override
  State<_LiveInfoDialog> createState() => _LiveInfoDialogState();
}

class _LiveInfoDialogState extends State<_LiveInfoDialog> {
  bool _isAnnouncementExpanded = false;
  bool _isDescriptionExpanded = false;
  bool _announcementNeedsExpansion = false;
  bool _descriptionNeedsExpansion = false;
  final GlobalKey _announcementKey = GlobalKey();
  final GlobalKey _descriptionKey = GlobalKey();

  static const int _maxLines = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfNeedsExpansion();
    });
  }

  void _checkIfNeedsExpansion() {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      height: 1.6,
    );

    // 檢查公告是否需要展開
    if (widget.state.announcement != null && widget.state.announcement!.isNotEmpty) {
      final announcementPainter = TextPainter(
        text: TextSpan(text: widget.state.announcement!, style: textStyle),
        maxLines: _maxLines,
        textDirection: TextDirection.ltr,
      );
      final box = _announcementKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        announcementPainter.layout(maxWidth: box.size.width);
        if (mounted) {
          setState(() {
            _announcementNeedsExpansion = announcementPainter.didExceedMaxLines;
          });
        }
      }
    }

    // 檢查簡介是否需要展開
    if (widget.state.description != null && widget.state.description!.isNotEmpty) {
      final descriptionPainter = TextPainter(
        text: TextSpan(text: widget.state.description!, style: textStyle),
        maxLines: _maxLines,
        textDirection: TextDirection.ltr,
      );
      final box = _descriptionKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        descriptionPainter.layout(maxWidth: box.size.width);
        if (mounted) {
          setState(() {
            _descriptionNeedsExpansion = descriptionPainter.didExceedMaxLines;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final station = widget.state.currentStation;
    final screenHeight = MediaQuery.of(context).size.height;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.75,
      ),
      child: Container(
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
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: station == null
                    ? const Text('無法獲取直播間信息')
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 標題（點擊跳轉到直播間）
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => UrlLauncherService.instance.openBilibiliLive(station.sourceId),
                            child: Text(
                              station.title,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                height: 1.3,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 主播信息（點擊跳轉到個人空間）
                        if (station.hostName != null)
                          MouseRegion(
                            cursor: station.hostUid != null
                                ? SystemMouseCursors.click
                                : SystemMouseCursors.basic,
                            child: GestureDetector(
                              onTap: station.hostUid != null
                                  ? () => UrlLauncherService.instance.openBilibiliSpace(station.hostUid!)
                                  : null,
                              child: Row(
                                children: [
                                  ImageLoadingService.loadAvatar(
                                    networkUrl: station.hostAvatarUrl,
                                    size: 40,
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
                                  if (station.hostUid != null)
                                    Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                ],
                              ),
                            ),
                          ),

                        const SizedBox(height: 16),

                        // 統計數據
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            if (widget.state.viewerCount != null)
                              _buildStatItem(
                                context,
                                Icons.visibility_rounded,
                                '${_formatCount(widget.state.viewerCount!)} 觀眾',
                              ),
                            if (widget.state.isPlaying)
                              _buildStatItem(
                                context,
                                Icons.schedule_outlined,
                                '已播放 ${_formatDuration(widget.state.playDuration)}',
                              ),
                            if (widget.state.liveStartTime != null)
                              _buildStatItem(
                                context,
                                Icons.play_circle_outline,
                                '開播於 ${_formatDateTime(widget.state.liveStartTime!)}',
                              ),
                            if (widget.state.areaName != null)
                              _buildStatItem(
                                context,
                                Icons.category_outlined,
                                widget.state.areaName!,
                              ),
                            _buildStatItem(
                              context,
                              widget.state.isPlaying
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              widget.state.isPlaying ? '直播中' : '已停止',
                            ),
                          ],
                        ),

                        // 主播公告
                        if (widget.state.announcement != null &&
                            widget.state.announcement!.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 16),
                          _buildExpandableSection(
                            context,
                            icon: Icons.campaign_outlined,
                            title: '主播公告',
                            content: widget.state.announcement!,
                            textKey: _announcementKey,
                            isExpanded: _isAnnouncementExpanded,
                            needsExpansion: _announcementNeedsExpansion,
                            onToggle: () {
                              setState(() {
                                _isAnnouncementExpanded = !_isAnnouncementExpanded;
                              });
                            },
                          ),
                        ],

                        // 直播間簡介
                        if (widget.state.description != null &&
                            widget.state.description!.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 16),
                          _buildExpandableSection(
                            context,
                            icon: Icons.info_outline_rounded,
                            title: '簡介',
                            content: widget.state.description!,
                            textKey: _descriptionKey,
                            isExpanded: _isDescriptionExpanded,
                            needsExpansion: _descriptionNeedsExpansion,
                            onToggle: () {
                              setState(() {
                                _isDescriptionExpanded = !_isDescriptionExpanded;
                              });
                            },
                          ),
                        ],

                        // 標籤
                        if (widget.state.tags != null &&
                            widget.state.tags!.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 16),
                          _buildTagsSection(context, widget.state.tags!),
                        ],

                        const SizedBox(height: 20),
                      ],
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandableSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String content,
    required GlobalKey textKey,
    required bool isExpanded,
    required bool needsExpansion,
    required VoidCallback onToggle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          content,
          key: textKey,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
          maxLines: isExpanded ? null : _maxLines,
          overflow: isExpanded ? null : TextOverflow.ellipsis,
        ),
        if (needsExpansion)
          Align(
            alignment: Alignment.centerRight,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    isExpanded ? '收起' : '展開',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTagsSection(BuildContext context, String tags) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tagList = tags.split(',').where((t) => t.trim().isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tag, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              '標籤',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tagList.map((tag) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              tag.trim(),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )).toList(),
        ),
      ],
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