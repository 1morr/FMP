import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/radio_station.dart';
import '../../../i18n/strings.g.dart';
import '../../../services/radio/radio_controller.dart';
import '../../widgets/menus/context_menu_region.dart';
import '../../widgets/menus/menu_action.dart';
import '../../widgets/dialogs/confirm_destructive_dialog.dart';
import '../../widgets/feedback/error_display.dart';
import '../../widgets/radio/add_radio_dialog.dart';
import '../../widgets/radio/radio_station_card.dart';

/// 电台页面
class RadioPage extends ConsumerStatefulWidget {
  const RadioPage({super.key});

  @override
  ConsumerState<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends ConsumerState<RadioPage> {
  bool _isSortMode = false;

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
        leading: radioState.stations.length > 1
            ? IconButton(
                onPressed: () {
                  setState(() {
                    _isSortMode = !_isSortMode;
                  });
                },
                icon: Icon(_isSortMode ? Icons.check : Icons.swap_vert),
                tooltip: _isSortMode ? t.radio.finishSort : t.radio.sortTitle,
              )
            : null,
        title: Text(_isSortMode ? t.radio.sortTitle : t.radio.title),
        actions: [
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
              tooltip: t.radio.refreshStatus,
            ),
          if (!_isSortMode)
            IconButton(
              icon: const Icon(Icons.link),
              tooltip: t.radio.importFromUrl,
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
    return ErrorDisplay.empty(
      icon: Icons.radio,
      title: t.radio.emptyTitle,
      message: t.radio.emptySubtitle,
      action: FilledButton.icon(
        onPressed: () => AddRadioDialog.show(context),
        icon: const Icon(Icons.add_link),
        label: Text(t.radio.addStation),
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
      // 预加载视口外 500px 的卡片，减少快速滚动时封面图空白
      scrollCacheExtent: const ScrollCacheExtent.pixels(500),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: AppSizes.cardAspectRatio,
      ),
      itemCount: stations.length,
      itemBuilder: (context, index) {
        final station = stations[index];
        final isLive = radioState.isStationLive(station.id);
        final isCurrentPlaying = radioState.currentStation?.id == station.id;

        return ContextMenuRegion(
          key: ValueKey(station.id),
          menuBuilder: (_) => buildMenuActionPopupEntries(
            _stationMenuActions(),
            Theme.of(context).colorScheme.error,
          ),
          onSelected: (value) => _onStationMenuAction(context, station, value),
          child: RadioStationCard(
            station: station,
            isLive: isLive,
            isPlaying: isCurrentPlaying && radioState.isPlaying,
            isLoading: radioState.loadingStationId == station.id,
            showAnchor: true,
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
        childAspectRatio: AppSizes.cardAspectRatio,
      ),
      itemCount: stations.length,
      dragStartDelay: Duration.zero,
      onReorder: (oldIndex, newIndex) async {
        final controller = ref.read(radioControllerProvider.notifier);
        final previousStations = List<RadioStation>.from(stations);

        // 樂觀更新 UI
        final updatedStations = List<RadioStation>.from(stations);
        final station = updatedStations.removeAt(oldIndex);
        updatedStations.insert(newIndex, station);

        // 直接更新狀態（避免閃爍）
        controller.updateStationsOrder(updatedStations);

        try {
          // 保存到數據庫
          final newOrder = updatedStations.map((s) => s.id).toList();
          await controller.reorderStations(newOrder);
        } catch (_) {
          controller.updateStationsOrder(previousStations);
        }
      },
      itemBuilder: (context, index) {
        final station = stations[index];
        final isLive = radioState.isStationLive(station.id);
        final isCurrentPlaying = radioState.currentStation?.id == station.id;

        return RadioStationCard(
          key: ValueKey(station.id),
          station: station,
          isLive: isLive,
          isPlaying: isCurrentPlaying && radioState.isPlaying,
          isLoading: radioState.loadingStationId == station.id,
          showAnchor: true,
          trailing: const RadioStationDragHandle(),
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
        borderRadius: AppRadius.borderRadiusMd,
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

  List<MenuAction> _stationMenuActions() => [
        MenuAction(
          id: 'delete',
          icon: Icons.delete,
          label: t.radio.deleteStation,
          destructive: true,
        ),
      ];

  void _onStationMenuAction(
    BuildContext context,
    RadioStation station,
    String value,
  ) {
    if (value == 'delete') _showDeleteConfirm(context, station);
  }

  void _showOptionsMenu(BuildContext context, RadioStation station) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: buildMenuActionListTiles(
              sheetContext,
              _stationMenuActions(),
              (value) => _onStationMenuAction(context, station, value),
              colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteConfirm(
      BuildContext context, RadioStation station) async {
    final confirmed = await showConfirmDestructiveDialog(
      context,
      title: t.radio.deleteStation,
      content: t.radio.deleteConfirm(title: station.title),
      confirmLabel: t.radio.delete,
    );

    if (confirmed == true) {
      await ref
          .read(radioControllerProvider.notifier)
          .deleteStation(station.id);
      if (context.mounted) {
        ToastService.success(context, t.radio.stationDeleted);
      }
    }
  }
}

