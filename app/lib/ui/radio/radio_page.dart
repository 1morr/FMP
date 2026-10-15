import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/playback/live_play.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/radio/radio_service.dart';
import 'package:fmp/radio/radio_status_jobs.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/player/live_widgets.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/radio/radio_status_tag.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/track_row_menu.dart';

/// 電台頁（ADR 0031 §決定 4，M3 design §9.3）：使用者存的直播間清單。
///
/// - 標題列（同歷史頁）：「以網址新增」「刷新狀態」；新增或刷新進行中時頂端有進度條，兩個鈕停用
///   （同插件頁）。
/// - 每列：封面、標題、狀態標記與主播（音源停用或未安裝時是原因）、開播中時的直播標題、
///   「⋯」選單（刪除，先確認）與拖曳把手（同佇列）。點一下收聽；音源不能用的列不播，提示原因。
///   正在收聽的那一列以主色標示。
/// - 本機資料：離線照常顯示存的狀態。手動刷新時排程器說離線（不發請求）就在清單上方說明
///   「沒有刷新」，附重試；回到線上就收起。
class RadioPage extends ConsumerStatefulWidget {
  const RadioPage({super.key});

  @override
  ConsumerState<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends ConsumerState<RadioPage> {
  /// 新增或刷新進行中（一次只做一件事）。
  var _busy = false;

  /// 上一次手動刷新因為離線沒有發請求。
  var _refreshedOffline = false;

  /// 拖曳後還沒從資料庫回來的順序（電台 id）；回來之前照它畫，清單才不會跳回去。
  List<int>? _pendingOrder;

  Future<void> _work(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFromUrl() async {
    // 對話框期間外殼可能重建這一頁：要用的先讀好。
    final t = ref.read(translationsProvider).radio;
    final service = ref.read(radioServiceProvider);
    final toaster = ref.read(toasterProvider);
    final url = await showDialog<String>(
      context: context,
      builder: (context) => const _AddUrlDialog(),
    );
    if (url == null || url.trim().isEmpty || !mounted) return;
    await _work(() async {
      try {
        switch (await service.addFromUrl(url)) {
          case AddRadioResult.added:
            toaster.success(t.added);
          case AddRadioResult.alreadyAdded:
            toaster.info(t.alreadyAdded);
          case AddRadioResult.unrecognizedUrl:
            toaster.warning(t.unrecognizedUrl);
        }
      } on AppError catch (error) {
        toaster.error(
          error,
          operation: 'Failed to add a radio station',
          tag: 'radio',
          sentence: (reason) => t.addFailed(reason: reason),
        );
      }
    });
  }

  Future<void> _refresh() async {
    final t = ref.read(translationsProvider).radio;
    final service = ref.read(radioServiceProvider);
    final toaster = ref.read(toasterProvider);
    setState(() => _refreshedOffline = false);
    await _work(() async {
      try {
        switch (await service.refresh()) {
          case RadioRefreshResult.completed:
            toaster.success(t.refreshed);
          case RadioRefreshResult.offline:
            if (mounted) setState(() => _refreshedOffline = true);
          case RadioRefreshResult.nothingToRefresh:
            toaster.info(t.nothingToRefresh);
        }
      } on Object catch (error, stackTrace) {
        toaster.error(
          AppError.wrap(error, stackTrace),
          operation: 'Radio status refresh failed',
          tag: 'radio',
          sentence: (reason) => t.refreshFailed(reason: reason),
        );
      }
    });
  }

  void _reorder(List<RadioEntry> shown, int from, int to) {
    final ids = [for (final entry in shown) entry.station.id];
    ids.insert(to, ids.removeAt(from));
    setState(() => _pendingOrder = ids);
    final toaster = ref.read(toasterProvider);
    final t = ref.read(translationsProvider).radio;
    unawaited(
      ref.read(radioServiceProvider).reorder(ids).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        if (mounted) setState(() => _pendingOrder = null);
        toaster.error(
          AppError.wrap(error, stackTrace),
          operation: 'Failed to reorder the radio stations',
          tag: 'radio',
          sentence: (reason) => t.reorderFailed(reason: reason),
        );
      }),
    );
  }

  /// 畫面上的順序：拖曳後的順序在資料庫追上之前優先；清單在這期間增減了就以資料庫為準。
  List<RadioEntry> _shown(List<RadioEntry> entries) {
    final pending = _pendingOrder;
    if (pending == null) return entries;
    final ids = [for (final entry in entries) entry.station.id];
    if (listEquals(ids, pending) || !setEquals(ids.toSet(), pending.toSet())) {
      _pendingOrder = null;
      return entries;
    }
    final byId = {for (final entry in entries) entry.station.id: entry};
    return [for (final id in pending) byId[id]!];
  }

  @override
  Widget build(BuildContext context) {
    // 讀資料庫失敗：報一次（畫面是錯誤狀態，不是「還沒有電台」）。
    ref.listen(radioStationsProvider, (previous, next) {
      if (next case AsyncError(:final error, :final stackTrace)
          when previous is! AsyncError) {
        ref
            .read(logProvider)
            .report(
              'Failed to read the radio stations',
              AppError.wrap(error, stackTrace),
              tag: 'radio',
            );
      }
    });
    ref.listen(networkStatusProvider, (_, status) {
      if (status == NetworkStatus.online && _refreshedOffline) {
        setState(() => _refreshedOffline = false);
      }
    });
    final translations = ref.watch(translationsProvider);
    final t = translations.radio;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final entries = ref.watch(radioEntriesProvider);
    final hasStations = entries.value?.isNotEmpty ?? false;
    final network = ref.watch(networkStatusProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.x4,
            spacing.x4,
            spacing.x2,
            spacing.x2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(t.title, style: theme.textTheme.headlineSmall),
                ),
              ),
              IconButton(
                tooltip: t.addFromUrl,
                icon: const Icon(Icons.add_link),
                onPressed: _busy ? null : () => unawaited(_addFromUrl()),
              ),
              IconButton(
                tooltip: t.refresh,
                icon: const Icon(Icons.refresh),
                onPressed: _busy || !hasStations
                    ? null
                    : () => unawaited(_refresh()),
              ),
            ],
          ),
        ),
        // 不忙時是透明的空條（value 0，不動）：出現與消失不改變下方的位置（同插件頁）。
        Opacity(
          opacity: _busy ? 1 : 0,
          child: LinearProgressIndicator(
            value: _busy ? null : 0,
            semanticsLabel: t.working,
          ),
        ),
        if (_refreshedOffline && hasStations && network != NetworkStatus.online)
          _OfflineNotice(onRetry: _busy ? null : () => unawaited(_refresh())),
        Expanded(
          child: switch (entries) {
            AsyncData(:final value) when value.isEmpty => EmptyState(
              icon: Icons.radio,
              title: t.empty,
              body: t.emptyHint,
              action: FilledButton.tonal(
                onPressed: _busy ? null : () => unawaited(_addFromUrl()),
                child: Text(t.addFromUrl),
              ),
            ),
            AsyncData(:final value) => _StationList(
              entries: _shown(value),
              onReorder: _reorder,
            ),
            AsyncError(:final error) => EmptyState(
              icon: Icons.error_outline,
              title: errorMessage(
                translations,
                AppError.wrap(error, StackTrace.current),
              ),
            ),
            AsyncLoading() => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}

/// 手動刷新時離線（ADR 0016 §決定 7）：清單照常顯示存的狀態，這一行說明沒有刷新。外殼頂端
/// 已有離線提示，這裡不再用警告色。
class _OfflineNotice extends ConsumerWidget {
  const _OfflineNotice({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).radio;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: spacing.x4, end: spacing.x2),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: color),
          SizedBox(width: spacing.x3),
          Expanded(
            child: Text(
              t.refreshOffline,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(t.retry)),
        ],
      ),
    );
  }
}

class _StationList extends ConsumerWidget {
  const _StationList({required this.entries, required this.onReorder});

  final List<RadioEntry> entries;
  final void Function(List<RadioEntry> shown, int from, int to) onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listening = ref.watch(
      nowPlayingLiveProvider.select((live) => live?.target),
    );
    return ReorderableListView.builder(
      padding: EdgeInsets.only(bottom: AppTokens.of(context).spacing.x4),
      buildDefaultDragHandles: false,
      itemCount: entries.length,
      // `onReorderItem` 的 `newIndex` 已扣掉被拿起來的那一格（同佇列）。
      onReorderItem: (from, to) => onReorder(entries, from, to),
      itemBuilder: (context, index) {
        final station = entries[index].station;
        return _StationRow(
          key: ValueKey(station.id),
          index: index,
          entry: entries[index],
          listening:
              listening?.pluginId == station.pluginId &&
              listening?.roomId == station.roomId,
        );
      },
    );
  }
}

/// 收聽 [station] 的目標（電台頁與首頁的電台區塊）：標題取最近一次查到的直播標題，`live-info`
/// 之後會更新它。
LiveTarget radioLiveTarget(RadioStation station) => LiveTarget(
  pluginId: station.pluginId,
  roomId: station.roomId,
  title: station.liveTitle ?? station.title,
  hostName: station.hostName,
  artwork: station.artwork,
);

class _StationRow extends ConsumerWidget {
  const _StationRow({
    super.key,
    required this.index,
    required this.entry,
    required this.listening,
  });

  final int index;
  final RadioEntry entry;

  /// 正在收聽這一台。
  final bool listening;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).radio;
    final tokens = AppTokens.of(context);
    final station = entry.station;
    // 音源停用或移除時，主播的位置改說原因（同佇列與歷史，ADR 0030 §決定 7、10）。
    final unavailable = ref.watch(sourceUnavailableProvider(station.pluginId));
    final host = unavailable ?? station.hostName;
    final liveTitle = entry.status == RadioStatus.live
        ? station.liveTitle
        : null;
    final showLiveTitle = liveTitle != null && liveTitle != station.title;

    void play() {
      if (unavailable != null) {
        ref.read(toasterProvider).warning(t.cannotPlay(reason: unavailable));
        return;
      }
      unawaited(
        ref.read(playbackControllerProvider).playLive(radioLiveTarget(station)),
      );
    }

    return TrackRowMenu(
      moreTooltip: t.more,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline),
          onPressed: () => unawaited(_remove(context, ref)),
          child: Text(t.remove),
        ),
      ],
      builder: (context, more, openMenu) => ListTile(
        selected: listening,
        isThreeLine: showLiveTitle,
        leading: ArtworkImage(
          pluginId: station.pluginId,
          artwork: station.artwork,
          size: AppLayout.artworkThumbnail,
        ),
        title: Text(
          station.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TaggedLine(
              tag: RadioStatusTag(status: entry.status),
              text: host,
            ),
            if (showLiveTitle)
              Text(liveTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            more,
            ReorderableDragStartListener(
              index: index,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Tooltip(
                  message: t.reorder,
                  triggerMode: TooltipTriggerMode.manual,
                  child: Padding(
                    padding: EdgeInsets.all(tokens.spacing.x3),
                    child: const Icon(Icons.drag_handle),
                  ),
                ),
              ),
            ),
          ],
        ),
        onTap: play,
        onLongPress: openMenu,
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).radio;
    final service = ref.read(radioServiceProvider);
    final toaster = ref.read(toasterProvider);
    final station = entry.station;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.removeTitle),
        content: Text(t.removeBody(title: station.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.remove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await service.remove(station.id);
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to remove a radio station',
        tag: 'radio',
        sentence: (reason) => t.removeFailed(reason: reason),
      );
      return;
    }
    toaster.success(t.removed);
  }
}

/// 「以網址新增」：輸入直播間網址；按「新增」或 Enter 回傳輸入的字，取消回 `null`。
class _AddUrlDialog extends ConsumerStatefulWidget {
  const _AddUrlDialog();

  @override
  ConsumerState<_AddUrlDialog> createState() => _AddUrlDialogState();
}

class _AddUrlDialogState extends ConsumerState<_AddUrlDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (_text.text.trim().isEmpty) return;
    Navigator.of(context).pop(_text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).radio;
    return AlertDialog(
      title: Text(t.urlTitle),
      content: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: t.urlLabel),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        ListenableBuilder(
          listenable: _text,
          builder: (context, _) => FilledButton(
            onPressed: _text.text.trim().isEmpty ? null : _submit,
            child: Text(t.add),
          ),
        ),
      ],
    );
  }
}
