import 'dart:async';

import '../../../core/services/image_loading_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/toast_service.dart';
import '../../../data/models/radio_station.dart';
import '../../../services/radio/radio_controller.dart';
import '../../widgets/now_playing_indicator.dart';
import '../../widgets/radio/add_radio_dialog.dart';

/// 电台页面
class RadioPage extends ConsumerStatefulWidget {
  const RadioPage({super.key});

  @override
  ConsumerState<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends ConsumerState<RadioPage> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // 进入页面时刷新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(radioControllerProvider.notifier).refreshAllLiveStatus();
    });
    // 每分钟刷新
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => ref.read(radioControllerProvider.notifier).refreshAllLiveStatus(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 监听错误并显示 Toast
    ref.listen<RadioState>(radioControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ToastService.show(context, next.error!);
      }
    });

    final radioState = ref.watch(radioControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('电台'),
        actions: [
          // 刷新按钮
          IconButton(
            onPressed: radioState.isRefreshingStatus
                ? null
                : () => ref
                    .read(radioControllerProvider.notifier)
                    .refreshAllLiveStatus(),
            icon: radioState.isRefreshingStatus
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: '刷新状态',
          ),
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: '添加电台',
            onPressed: () => AddRadioDialog.show(context),
          ),
        ],
      ),
      body: radioState.stations.isEmpty
          ? _buildEmptyState(context, colorScheme)
          : _buildStationGrid(context, radioState, colorScheme),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.radio,
              size: 80,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 24),
            Text(
              '还没有电台',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '添加 Bilibili 直播间来收听',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.outline,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => AddRadioDialog.show(context),
              icon: const Icon(Icons.add_link),
              label: const Text('添加电台'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationGrid(
    BuildContext context,
    RadioState radioState,
    ColorScheme colorScheme,
  ) {
    // 排序：正在直播的排前面，同状态内保持原有顺序
    final sortedStations = List<RadioStation>.from(radioState.stations)
      ..sort((a, b) {
        final aLive = radioState.isStationLive(a.id) ? 0 : 1;
        final bLive = radioState.isStationLive(b.id) ? 0 : 1;
        return aLive.compareTo(bLive);
      });

    return Column(
      children: [
        // 重连提示（错误已改为 Toast 显示）
        if (radioState.reconnectMessage != null)
          _buildReconnectBanner(radioState, colorScheme),

        // 网格列表
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.8,
            ),
            itemCount: sortedStations.length,
            itemBuilder: (context, index) {
              final station = sortedStations[index];
              final isLive = radioState.isStationLive(station.id);
              final isCurrentPlaying =
                  radioState.currentStation?.id == station.id;

              return _RadioStationCard(
                station: station,
                isLive: isLive,
                isPlaying: isCurrentPlaying && radioState.isPlaying,
                isLoading: radioState.loadingStationId == station.id,
                onTap: () => _onStationTap(station, isCurrentPlaying, radioState),
                onLongPress: () => _showOptionsMenu(context, station),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReconnectBanner(RadioState radioState, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            radioState.reconnectMessage!,
            style: TextStyle(
              color: colorScheme.onSecondaryContainer,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _onStationTap(
    RadioStation station,
    bool isCurrentPlaying,
    RadioState radioState,
  ) {
    final controller = ref.read(radioControllerProvider.notifier);

    if (isCurrentPlaying) {
      // 点击当前电台：切换播放/暂停
      if (radioState.isPlaying) {
        controller.pause();
      } else {
        controller.resume();
      }
    } else {
      // 点击其他电台：播放该电台
      controller.play(station);
    }
  }

  void _showOptionsMenu(BuildContext context, RadioStation station) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.delete, color: colorScheme.error),
                title: Text('删除电台', style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirm(context, station);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteConfirm(
      BuildContext context, RadioStation station) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除电台'),
        content: Text('确定要删除「${station.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(radioControllerProvider.notifier)
          .deleteStation(station.id);
      if (context.mounted) {
        ToastService.show(context, '电台已删除');
      }
    }
  }
}

/// 电台卡片
class _RadioStationCard extends StatelessWidget {
  final RadioStation station;
  final bool isLive;
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _RadioStationCard({
    required this.station,
    required this.isLive,
    required this.isPlaying,
    required this.isLoading,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 封面大小 = 卡片宽度 - 水平padding
          final coverSize = constraints.maxWidth - 40; // 20 * 2

          return Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // 圆形封面
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 20),
                child: SizedBox(
                  width: coverSize,
                  height: coverSize,
                  child: Stack(
                    children: [
                      // 封面图
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.surfaceContainerHighest,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ColorFiltered(
                          colorFilter: isLive
                              ? const ColorFilter.mode(
                                  Colors.transparent,
                                  BlendMode.multiply,
                                )
                              : const ColorFilter.matrix(<double>[
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0, 0, 0, 1, 0,
                                ]),
                          child: ImageLoadingService.loadImage(
                            networkUrl: station.thumbnailUrl,
                            placeholder: _buildPlaceholder(colorScheme),
                            fit: BoxFit.cover,
                            width: coverSize,
                            height: coverSize,
                          ),
                        ),
                      ),

                      // 正在直播红点
                      if (isLive)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.surface,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.5),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),

                      // 播放中指示器
                      if (isPlaying || isLoading)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.primary.withValues(alpha: 0.4),
                            ),
                            child: Center(
                              child: isLoading
                                  ? SizedBox(
                                      width: coverSize * 0.32,
                                      height: coverSize * 0.32,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: colorScheme.onPrimary,
                                      ),
                                    )
                                  : NowPlayingIndicator(
                                      color: colorScheme.onPrimary,
                                      size: coverSize * 0.32,
                                      isPlaying: true,
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 标题
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  station.title,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: isPlaying ? FontWeight.bold : null,
                    color: isLive
                        ? (isPlaying ? colorScheme.primary : colorScheme.onSurface)
                        : colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),

              // 主播名称
              if (station.hostName != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    station.hostName!,
                    style: textTheme.bodySmall?.copyWith(
                      color: isLive
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.radio,
        size: 40,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}
