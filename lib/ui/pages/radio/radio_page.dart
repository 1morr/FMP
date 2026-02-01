import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/toast_service.dart';
import '../../../data/models/radio_station.dart';
import '../../../services/radio/radio_controller.dart';
import '../../widgets/radio/add_radio_dialog.dart';
import '../../widgets/radio/radio_list_tile.dart';

/// 電台頁面
class RadioPage extends ConsumerStatefulWidget {
  const RadioPage({super.key});

  @override
  ConsumerState<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends ConsumerState<RadioPage> {
  @override
  Widget build(BuildContext context) {
    final radioState = ref.watch(radioControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: radioState.stations.isEmpty
            ? _buildEmptyState(context, colorScheme)
            : _buildStationList(context, radioState, colorScheme),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => AddRadioDialog.show(context),
        tooltip: '添加電台',
        child: const Icon(Icons.add),
      ),
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
          const SizedBox(height: 100), // Space for mini player
        ],
      ),
    );
  }

  Widget _buildStationList(
    BuildContext context,
    RadioState radioState,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 標題欄
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                '電台',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              if (radioState.isPlaying)
                _buildNowPlayingChip(radioState, colorScheme),
            ],
          ),
        ),

        // 錯誤提示
        if (radioState.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Card(
              color: colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: colorScheme.onErrorContainer, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        radioState.error!,
                        style: TextStyle(
                          color: colorScheme.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 重連提示
        if (radioState.reconnectMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Card(
              color: colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
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
              ),
            ),
          ),

        // 電台列表
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: radioState.stations.length,
            onReorder: (oldIndex, newIndex) => _onReorder(
              radioState.stations,
              oldIndex,
              newIndex,
            ),
            itemBuilder: (context, index) {
              final station = radioState.stations[index];
              final isCurrentPlaying =
                  radioState.currentStation?.id == station.id;

              return RadioStationTile(
                key: ValueKey(station.id),
                station: station,
                isPlaying: isCurrentPlaying && radioState.isPlaying,
                isLoading: isCurrentPlaying && radioState.isLoading,
                onTap: () => _onStationTap(station, isCurrentPlaying, radioState),
                onEdit: () => _showEditDialog(context, station),
                onDelete: () => _showDeleteConfirm(context, station),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNowPlayingChip(RadioState radioState, ColorScheme colorScheme) {
    final duration = radioState.playDuration;
    final formatted = _formatDuration(duration);

    return Chip(
      avatar: const Icon(Icons.graphic_eq, size: 16),
      label: Text(formatted),
      side: BorderSide.none,
      backgroundColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        color: colorScheme.onPrimaryContainer,
        fontSize: 12,
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
      // 正在播放此電台 → 停止
      controller.stop();
    } else {
      // 播放此電台
      controller.play(station);
    }
  }

  void _onReorder(List<RadioStation> stations, int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final newOrder = List<RadioStation>.from(stations);
    final item = newOrder.removeAt(oldIndex);
    newOrder.insert(newIndex, item);

    ref
        .read(radioControllerProvider.notifier)
        .reorderStations(newOrder.map((s) => s.id).toList());
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

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
