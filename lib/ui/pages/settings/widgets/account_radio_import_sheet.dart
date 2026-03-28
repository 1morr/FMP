import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/ui_constants.dart';
import '../../../../core/services/image_loading_service.dart';
import '../../../../core/services/toast_service.dart';
import '../../../../data/models/radio_station.dart';
import '../../../../data/models/track.dart';
import '../../../../i18n/strings.g.dart';
import '../../../../providers/account_provider.dart';
import '../../../../services/radio/radio_controller.dart';
import '../../../../services/radio/radio_refresh_service.dart';
import '../../../../services/account/bilibili_account_service.dart';

/// 電台列表項（內部使用）
class _RadioItem {
  final String roomId;
  final String name;
  final String? avatarUrl;
  final int uid;
  final bool isLive;
  final String link;
  final bool isImported;

  const _RadioItem({
    required this.roomId,
    required this.name,
    this.avatarUrl,
    required this.uid,
    required this.isLive,
    required this.link,
    this.isImported = false,
  });
}

/// 帳號電台導入 BottomSheet
class AccountRadioImportSheet extends ConsumerStatefulWidget {
  const AccountRadioImportSheet({super.key});

  @override
  ConsumerState<AccountRadioImportSheet> createState() =>
      _AccountRadioImportSheetState();
}

class _AccountRadioImportSheetState
    extends ConsumerState<AccountRadioImportSheet> {
  List<_RadioItem>? _stations;
  final Set<String> _selectedIds = {};
  bool _isLoading = true;
  bool _isImporting = false;
  String? _error;

  int _importCurrent = 0;
  int _importTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = ref.read(bilibiliAccountServiceProvider);
      final radioRepo = ref.read(radioRepositoryProvider);

      // 並行獲取勳章牆和已存在的電台
      final medalFuture = service.fetchMedalWall();
      final stationsFuture = radioRepo != null
          ? radioRepo.getAll()
          : Future.value(<RadioStation>[]);
      final results = await Future.wait([medalFuture, stationsFuture]);
      final medalItems = results[0] as List<MedalWallItem>;
      final existingStations = results[1] as List<RadioStation>;

      if (!mounted) return;

      // 建立已存在的 sourceId 集合
      final existingSourceIds = <String>{
        for (final s in existingStations)
          if (s.sourceType == SourceType.bilibili) s.sourceId,
      };

      setState(() {
        _stations = medalItems.map((item) => _RadioItem(
          roomId: item.roomId,
          name: item.name,
          avatarUrl: item.avatarUrl,
          uid: item.uid,
          isLive: item.isLive,
          link: item.link,
          isImported: existingSourceIds.contains(item.roomId),
        )).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = t.remote.error.unknown(code: 'LOAD');
        _isLoading = false;
      });
    }
  }

  void _toggleSelection(String roomId) {
    setState(() {
      if (_selectedIds.contains(roomId)) {
        _selectedIds.remove(roomId);
      } else {
        _selectedIds.add(roomId);
      }
    });
  }

  Future<void> _importSelected() async {
    final selected = _stations!
        .where((s) => _selectedIds.contains(s.roomId) && !s.isImported)
        .toList();
    if (selected.isEmpty) return;

    final radioSource = ref.read(radioSourceProvider);
    final radioRepo = ref.read(radioRepositoryProvider);
    if (radioRepo == null) return;

    setState(() {
      _isImporting = true;
      _importCurrent = 0;
      _importTotal = selected.length;
    });

    // Pre-compute sort orders to avoid sequential DB queries
    final baseSortOrder = await radioRepo.getNextSortOrder();

    // Parallel import with progress tracking
    int completed = 0;
    final futures = selected.asMap().entries.map((entry) async {
      final index = entry.key;
      final item = entry.value;

      try {
        final station = await radioSource.createStationFromUrl(item.link);
        station.sortOrder = baseSortOrder + index;
        await radioRepo.save(station);

        // Update progress (debounced setState - every 3 items or on completion)
        if (mounted) {
          completed++;
          if (completed % 3 == 0 || completed == selected.length) {
            setState(() => _importCurrent = completed);
          }
        }
        return true;
      } catch (e) {
        // Single failure doesn't interrupt others
        return false;
      }
    });

    final results = await Future.wait(futures);
    final successCount = results.where((r) => r).length;

    if (!mounted) return;
    Navigator.pop(context);
    if (successCount > 0) {
      ToastService.success(
        context,
        t.account.importRadioComplete(count: successCount.toString()),
      );
      // 立即刷新電台直播狀態，讓電台管理頁面顯示最新狀態
      RadioRefreshService.instance.refreshAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final importedIds = _stations == null
        ? <String>{}
        : {for (final s in _stations!) if (s.isImported) s.roomId};
    final selectedCount =
        _selectedIds.where((id) => !importedIds.contains(id)).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // 拖拽指示條
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outline.withValues(alpha: 0.3),
              borderRadius: AppRadius.borderRadiusXs,
            ),
          ),
          // 標題
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  t.account.selectRadioStations,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(),
          // Content
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              clipBehavior: Clip.hardEdge,
              child: _buildContent(scrollController),
            ),
          ),
          // Bottom action bar
          if (!_isLoading && _error == null && (_stations?.isNotEmpty ?? false))
            _buildBottomBar(selectedCount),
        ],
      ),
    );
  }

  Widget _buildContent(ScrollController scrollController) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_stations == null || _stations!.isEmpty) {
      return Center(child: Text(t.account.noRadioStations));
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _stations!.length,
      itemBuilder: (context, index) {
        final item = _stations![index];
        return _buildStationTile(item);
      },
    );
  }

  Widget _buildStationTile(_RadioItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _selectedIds.contains(item.roomId);

    return ListTile(
      leading: ImageLoadingService.loadAvatar(
        networkUrl: item.avatarUrl,
        size: 40,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (item.isLive) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: AppRadius.borderRadiusXs,
              ),
              child: Text(
                t.account.liveStatus,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: item.isImported
          ? Icon(Icons.check_circle, color: colorScheme.outline)
          : isSelected
              ? Icon(Icons.check_circle, color: colorScheme.primary)
              : Icon(Icons.circle_outlined, color: colorScheme.outline),
      selected: isSelected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusLg),
      onTap: item.isImported || _isImporting
          ? null
          : () => _toggleSelection(item.roomId),
    );
  }

  Widget _buildBottomBar(int selectedCount) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isImporting) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.account.importingRadio,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    '$_importCurrent/$_importTotal',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: _isImporting
                  ? const Center(child: CircularProgressIndicator())
                  : FilledButton(
                      onPressed: selectedCount > 0 ? _importSelected : null,
                      child: Text(
                        t.account.importRadioSelected(
                          count: selectedCount.toString(),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

