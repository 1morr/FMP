import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/charts/chart_cache.dart';
import 'package:fmp/charts/chart_entries.dart';
import 'package:fmp/charts/chart_jobs.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 設定頁的「音樂庫」區（M4 design §10.10、ADR 0033 §決定 14）：「首頁排行」。之後的
/// 「匹配目標音源」（M4 PR 19）接在它下面。
class LibraryControls extends StatelessWidget {
  const LibraryControls({super.key});

  @override
  Widget build(BuildContext context) => const HomeChartsSettings();
}

/// 「首頁排行」：所有宣告 `charts` 的已啟用插件的榜單（含停用的），可勾選、可拖曳排序
/// （舊版首頁排行設定頁的樣式）。每列是榜單名稱與音源。
///
/// - 拖曳放開後整批寫 `chart_settings.sort_order`（清單上全部的榜單，依新的順序）；資料庫追上
///   之前照拖曳後的順序畫，寫入失敗回到資料庫的順序並提示（同電台頁）。
/// - 勾選與取消寫 `chart_settings.enabled`；停用的榜單由 `ChartJobs` 刪快取並重新登記工作。
///   全部取消也可以（首頁就沒有排行區塊，ADR 0033 不保留「至少留一個」）。
/// - 沒有任何榜單時是說明。
class HomeChartsSettings extends ConsumerStatefulWidget {
  const HomeChartsSettings({super.key});

  @override
  ConsumerState<HomeChartsSettings> createState() => _HomeChartsSettingsState();
}

class _HomeChartsSettingsState extends ConsumerState<HomeChartsSettings> {
  /// 拖曳後、資料庫追上之前的順序。
  List<ChartKey>? _pendingOrder;

  void _reorder(List<ChartEntry> shown, int from, int to) {
    final order = [for (final entry in shown) entry.key];
    order.insert(to, order.removeAt(from));
    setState(() => _pendingOrder = order);
    final toaster = ref.read(toasterProvider);
    final t = ref.read(translationsProvider).librarySettings;
    unawaited(
      ref.read(chartSettingsRepositoryProvider).setOrder(order).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        // 連續拖曳時只清自己這一次：之後的拖曳已經換成新的順序，交給它的寫入結果。
        if (mounted && identical(_pendingOrder, order)) {
          setState(() => _pendingOrder = null);
        }
        toaster.error(
          AppError.wrap(error, stackTrace),
          operation: 'Failed to reorder the charts',
          tag: chartsLogTag,
          sentence: (reason) => t.reorderFailed(reason: reason),
        );
      }),
    );
  }

  Future<void> _setEnabled(ChartEntry entry, bool enabled) async {
    final toaster = ref.read(toasterProvider);
    final t = ref.read(translationsProvider).librarySettings;
    try {
      await ref
          .read(chartSettingsRepositoryProvider)
          .setEnabled(entry.pluginId, entry.chartId, enabled: enabled);
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to change a chart on Home',
        tag: chartsLogTag,
        sentence: (reason) => t.toggleFailed(reason: reason),
      );
    }
  }

  /// [entries] 依拖曳後的順序；資料庫已經追上（或清單變了）就照資料庫的。
  List<ChartEntry> _ordered(List<ChartEntry> entries) {
    final pending = _pendingOrder;
    if (pending == null) return entries;
    final keys = [for (final entry in entries) entry.key];
    if (listEquals(keys, pending) ||
        !setEquals(keys.toSet(), pending.toSet())) {
      _pendingOrder = null;
      return entries;
    }
    final byKey = {for (final entry in entries) entry.key: entry};
    return [for (final key in pending) byKey[key]!];
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).librarySettings;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final entries = ref.watch(chartEntriesProvider);
    final hintStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.homeCharts, style: theme.textTheme.titleSmall),
        SizedBox(height: spacing.x1),
        switch (entries) {
          // 插件清單或榜單還在讀。
          null => const SizedBox.shrink(),
          [] => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.noCharts, style: theme.textTheme.bodyLarge),
              SizedBox(height: spacing.x1),
              Text(t.noChartsHint, style: hintStyle),
            ],
          ),
          final entries => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.homeChartsHint, style: hintStyle),
              SizedBox(height: spacing.x2),
              _ChartList(
                entries: _ordered(entries),
                onReorder: _reorder,
                onToggle: (entry, enabled) =>
                    unawaited(_setEnabled(entry, enabled)),
              ),
            ],
          ),
        },
      ],
    );
  }
}

class _ChartList extends ConsumerWidget {
  const _ChartList({
    required this.entries,
    required this.onReorder,
    required this.onToggle,
  });

  final List<ChartEntry> entries;
  final void Function(List<ChartEntry> shown, int from, int to) onReorder;
  final void Function(ChartEntry entry, bool enabled) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).librarySettings;
    final spacing = AppTokens.of(context).spacing;
    // 清單在設定組那個捲動的欄裡：自己不捲動，高度跟著內容。
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: entries.length,
      // `onReorderItem` 的 `newIndex` 已扣掉被拿起來的那一格（同電台頁）。
      onReorderItem: (from, to) => onReorder(entries, from, to),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return CheckboxListTile(
          key: ValueKey(entry.key),
          contentPadding: EdgeInsetsDirectional.only(start: 0, end: spacing.x1),
          controlAffinity: ListTileControlAffinity.leading,
          value: entry.enabled,
          onChanged: (value) {
            if (value != null) onToggle(entry, value);
          },
          title: Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            entry.sourceName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          secondary: ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Tooltip(
                message: t.reorder,
                triggerMode: TooltipTriggerMode.manual,
                child: Padding(
                  padding: EdgeInsets.all(spacing.x3),
                  child: const Icon(Icons.drag_handle),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
