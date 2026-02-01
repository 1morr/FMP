import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/toast_service.dart';
import '../../../data/models/radio_station.dart';
import '../../../services/radio/radio_controller.dart';
import '../../widgets/now_playing_indicator.dart';
import '../../widgets/radio/add_radio_dialog.dart';

/// 電台頁面
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
    // 進入頁面時刷新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(radioControllerProvider.notifier).refreshAllLiveStatus();
    });
    // 每分鐘刷新
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
    // 監聽錯誤並顯示 Toast
    ref.listen<RadioState>(radioControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ToastService.show(context, next.error!);
      }
    });

    final radioState = ref.watch(radioControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('電台'),
        actions: [
          // 刷新按鈕
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
            tooltip: '刷新狀態',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加電台',
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.radio,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '還沒有電台',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '點擊右下角按鈕添加直播間',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildStationGrid(
    BuildContext context,
    RadioState radioState,
    ColorScheme colorScheme,
  ) {
    // 排序：正在直播的排前面，同狀態內保持原有順序
    final sortedStations = List<RadioStation>.from(radioState.stations)
      ..sort((a, b) {
        final aLive = radioState.isStationLive(a.id) ? 0 : 1;
        final bLive = radioState.isStationLive(b.id) ? 0 : 1;
        return aLive.compareTo(bLive);
      });

    return Column(
      children: [
        // 重連提示（錯誤已改為 Toast 顯示）
        if (radioState.reconnectMessage != null)
          _buildReconnectBanner(radioState, colorScheme),

        // 網格列表
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.75,
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

    if (isCurrentPlaying && radioState.isPlaying) {
      controller.stop();
    } else {
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
                leading: const Icon(Icons.edit),
                title: const Text('編輯電台'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(context, station);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete, color: colorScheme.error),
                title: Text('刪除電台', style: TextStyle(color: colorScheme.error)),
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

  Future<void> _showEditDialog(
      BuildContext context, RadioStation station) async {
    final titleController = TextEditingController(text: station.title);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('編輯電台'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: '電台名稱',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(titleController.text.trim()),
            child: const Text('確認'),
          ),
        ],
      ),
    );

    titleController.dispose();

    if (result != null && result.isNotEmpty && result != station.title) {
      station.title = result;
      await ref.read(radioControllerProvider.notifier).updateStation(station);
      if (context.mounted) {
        ToastService.show(context, '電台已更新');
      }
    }
  }

  Future<void> _showDeleteConfirm(
      BuildContext context, RadioStation station) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除電台'),
        content: Text('確定要刪除「${station.title}」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(radioControllerProvider.notifier)
          .deleteStation(station.id);
      if (context.mounted) {
        ToastService.show(context, '電台已刪除');
      }
    }
  }
}

/// 電台卡片
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 圓形封面
          Stack(
            children: [
              // 封面圖
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surfaceContainerHighest,
                ),
                clipBehavior: Clip.antiAlias,
                child: station.thumbnailUrl != null
                    ? ColorFiltered(
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
                        child: CachedNetworkImage(
                          imageUrl: station.thumbnailUrl!,
                          fit: BoxFit.cover,
                          width: 100,
                          height: 100,
                          placeholder: (context, url) => _buildPlaceholder(colorScheme),
                          errorWidget: (context, url, error) =>
                              _buildPlaceholder(colorScheme),
                        ),
                      )
                    : _buildPlaceholder(colorScheme),
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
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : NowPlayingIndicator(
                              color: colorScheme.onPrimary,
                              size: 32,
                              isPlaying: true,
                            ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // 標題
          Text(
            station.title,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: isPlaying ? FontWeight.bold : null,
              color: isLive
                  ? (isPlaying ? colorScheme.primary : colorScheme.onSurface)
                  : colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),

          // 主播名稱
          if (station.hostName != null)
            Text(
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
        ],
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.radio,
        size: 40,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}
