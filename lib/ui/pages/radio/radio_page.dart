import 'dart:async';

import '../../../core/services/image_loading_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../../core/services/toast_service.dart';
import '../../../data/models/radio_station.dart';
import '../../../services/radio/radio_controller.dart';
import '../../widgets/context_menu_region.dart';
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
  bool _isSortMode = false;

  @override
  void initState() {
    super.initState();
    // 每分钟自动刷新直播状态
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
        ToastService.error(context, next.error!);
      }
    });

    final radioState = ref.watch(radioControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSortMode ? '排列电台' : '电台'),
        actions: [
          // 排序模式切换
          if (radioState.stations.length > 1)
            IconButton(
              onPressed: () {
                setState(() {
                  _isSortMode = !_isSortMode;
                });
              },
              icon: Icon(_isSortMode ? Icons.check : Icons.swap_vert),
              tooltip: _isSortMode ? '完成排序' : '排列电台',
            ),
          // 刷新按钮（排序模式下隐藏）
          if (!_isSortMode)
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
          if (!_isSortMode)
            IconButton(
              icon: const Icon(Icons.link),
              tooltip: '从 URL 导入',
              onPressed: () => AddRadioDialog.show(context),
            ),
          const SizedBox(width: 8),
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
    // 排序模式：保持用戶自定義順序，不按直播狀態排序
    final displayStations = _isSortMode
        ? radioState.stations
        : (List<RadioStation>.from(radioState.stations)
          ..sort((a, b) {
            final aLive = radioState.isStationLive(a.id) ? 0 : 1;
            final bLive = radioState.isStationLive(b.id) ? 0 : 1;
            return aLive.compareTo(bLive);
          }));

    return Column(
      children: [
        // 重连提示（错误已改为 Toast 显示）
        if (radioState.reconnectMessage != null && !_isSortMode)
          _buildReconnectBanner(radioState, colorScheme),

        // 网格列表
        Expanded(
          child: _isSortMode
              ? _buildReorderableGrid(displayStations, radioState, colorScheme)
              : _buildNormalGrid(displayStations, radioState, colorScheme),
        ),
      ],
    );
  }

  Widget _buildNormalGrid(
    List<RadioStation> stations,
    RadioState radioState,
    ColorScheme colorScheme,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: stations.length,
      itemBuilder: (context, index) {
        final station = stations[index];
        final isLive = radioState.isStationLive(station.id);
        final isCurrentPlaying = radioState.currentStation?.id == station.id;

        return ContextMenuRegion(
          menuBuilder: (_) => [
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 12),
                  Text('删除电台', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'delete') _showDeleteConfirm(context, station);
          },
          child: _RadioStationCard(
            station: station,
            isLive: isLive,
            isPlaying: isCurrentPlaying && radioState.isPlaying,
            isLoading: radioState.loadingStationId == station.id,
            onTap: () => _onStationTap(station, isCurrentPlaying, radioState),
            onLongPress: () => _showOptionsMenu(context, station),
          ),
        );
      },
    );
  }

  Widget _buildReorderableGrid(
    List<RadioStation> stations,
    RadioState radioState,
    ColorScheme colorScheme,
  ) {
    return ReorderableGridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: stations.length,
      dragStartDelay: Duration.zero,
      onReorder: (oldIndex, newIndex) async {
        // 樂觀更新 UI
        final updatedStations = List<RadioStation>.from(stations);
        final station = updatedStations.removeAt(oldIndex);
        updatedStations.insert(newIndex, station);

        // 直接更新狀態（避免閃爍）
        ref.read(radioControllerProvider.notifier).updateStationsOrder(updatedStations);

        // 保存到數據庫
        final newOrder = updatedStations.map((s) => s.id).toList();
        await ref.read(radioControllerProvider.notifier).reorderStations(newOrder);
      },
      itemBuilder: (context, index) {
        final station = stations[index];
        final isLive = radioState.isStationLive(station.id);
        final isCurrentPlaying = radioState.currentStation?.id == station.id;

        return _ReorderableRadioStationCard(
          key: ValueKey(station.id),
          station: station,
          isLive: isLive,
          isPlaying: isCurrentPlaying && radioState.isPlaying,
          isLoading: radioState.loadingStationId == station.id,
        );
      },
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
        ToastService.success(context, '电台已删除');
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

/// 可拖動排序的電台卡片（保持與原卡片相同的顯示樣式）
class _ReorderableRadioStationCard extends StatelessWidget {
  final RadioStation station;
  final bool isLive;
  final bool isPlaying;
  final bool isLoading;

  const _ReorderableRadioStationCard({
    super.key,
    required this.station,
    required this.isLive,
    required this.isPlaying,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Stack(
      children: [
        // 主體內容（與原卡片相同）
        LayoutBuilder(
          builder: (context, constraints) {
            final coverSize = constraints.maxWidth - 40;

            return Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // 圓形封面
                Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 20),
                  child: SizedBox(
                    width: coverSize,
                    height: coverSize,
                    child: Stack(
                      children: [
                        // 封面圖
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

                        // 正在直播紅點
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

                // 標題
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

                // 主播名稱
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

        // 拖動把手
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.drag_indicator,
              size: 16,
              color: colorScheme.onPrimary,
            ),
          ),
        ),
      ],
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
