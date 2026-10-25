import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/dialogs/destructive_confirm.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/history/history_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/add_to_playlist.dart';
import 'package:fmp/ui/library/add_to_remote.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/search/search_state.dart';
import 'package:fmp/ui/shell/open_search.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/now_playing_overlay.dart';
import 'package:fmp/ui/tracks/start_mix.dart';
import 'package:fmp/ui/tracks/track_selection.dart';

/// 在 [context] 所在的 Navigator 開歷史頁：外殼裡是那個目的地的巢狀導覽（音樂庫頂端的
/// 「歷史」、首頁「最近播放」的「查看全部」，ADR 0033 §決定 5），導覽與播放列留著。
Future<void> openHistory(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    // 自己的 Material：理由見 `AppShell` 的根頁。
    builder: (_) =>
        const Material(type: MaterialType.transparency, child: HistoryPage()),
  ),
);

/// 歷史頁（design §9.7；ADR 0035 §決定 1，舊版的完整頁首）：統計卡（今天、本週、全部）、
/// 音源／日期／排序的篩選列、標題列的日期、搜尋與「⋯」（清除全部歷史，先確認、清完提示）。
///
/// 播放過的歌依時間分組成時間軸（今天、昨天、日期，跨年才帶年份），每天可以折疊（折疊狀態只
/// 在這個頁面裡）；排序選「播放次數」時一首一列、不分組。點一首是臨時播放；每筆的選單（右鍵、
/// 尾端「⋯」）有播放、下一首播放、加入佇列、加入歌單…、從歷史移除（只移除這一筆，不確認、
/// 不提示）、刪除此曲所有紀錄（確認、提示筆數）、選取。
///
/// 多選（[TrackSelectionScope]，M4 design §10.7）：長按或選單的「選取」進入，標題列換成選取列
/// （加入佇列、加入歌單…、刪除）；全選只選已載入的紀錄。
///
/// 分頁讀取（[historyProvider]）：捲到底才讀下一頁。全部是本機資料，離線照常
/// 可用；封面讀不到時 [ArtworkImage] 是佔位圖。
///
/// 從別的頁推上來時（[openHistory]）標題前有返回鈕。
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  /// 選的是紀錄的 id。
  final _selection = TrackSelection<int>();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  var _searching = false;

  /// 折疊起來的日期（本地時間的 00:00）；不存、不跨頁面。
  final _collapsed = <DateTime>{};

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _selection.dispose();
    super.dispose();
  }

  /// 已選的紀錄的曲目，依畫面順序。
  Future<List<TrackInfo>?> _tracks(List<int> ids) async => _tracksSync(ids);

  List<TrackInfo> _tracksSync(List<int> ids) {
    final byId = {
      for (final entry
          in ref.read(historyProvider).value?.entries ??
              const <PlayHistoryEntry>[])
        entry.id: entry.track,
    };
    return [for (final id in ids) ?byId[id]];
  }

  void _onQueryChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) ref.read(historyFilterProvider.notifier).setQuery(text);
    });
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _searching = false);
    ref.read(historyFilterProvider.notifier).setQuery('');
  }

  Future<void> _pickDate() async {
    final now = clock.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = ref.read(historyFilterProvider).day;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? today,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    ref.read(historyFilterProvider.notifier).setDay(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).history;
    final history = ref.watch(historyProvider);
    final filter = ref.watch(historyFilterProvider);
    final loaded = history.value;
    final hasEntries = loaded != null && loaded.entries.isNotEmpty;
    return TrackSelectionScope<int>(
      selection: _selection,
      keys: [
        for (final entry in loaded?.entries ?? const <PlayHistoryEntry>[])
          entry.id,
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TrackSelectionBar<int>(
            tracks: _tracks,
            pluginIds: (ids) => {
              for (final track in _tracksSync(ids)) track.sourceTypeId,
            },
            actions: [
              TrackSelectionAction<int>(
                icon: Icons.delete_outline,
                tooltip: t.deleteSelected,
                onPressed: _deleteSelected,
              ),
            ],
            child: _TopBar(
              searching: _searching,
              searchController: _searchController,
              clearEnabled: hasEntries || filter.isFiltering,
              onQueryChanged: _onQueryChanged,
              onPickDate: () => unawaited(_pickDate()),
              onSearch: () => setState(() => _searching = true),
              onCloseSearch: _closeSearch,
              onClearAll: () => unawaited(_clearAll(context, ref)),
            ),
          ),
          const _StatsCard(),
          const _FilterRow(),
          Expanded(
            child: switch (history) {
              // 讀失敗（已在 `HistoryNotifier` 報過）：不是「沒有紀錄」。
              AsyncError(:final error) => EmptyState(
                icon: Icons.error_outline,
                title: errorMessage(
                  ref.watch(translationsProvider),
                  AppError.wrap(error, StackTrace.current),
                ),
                action: FilledButton.icon(
                  onPressed: () => ref.invalidate(historyProvider),
                  icon: const Icon(Icons.refresh),
                  label: Text(t.retry),
                ),
              ),
              _ when loaded != null && loaded.entries.isEmpty =>
                filter.isFiltering
                    ? EmptyState(
                        icon: Icons.search_off,
                        title: t.noMatch,
                        body: t.noMatchHint,
                      )
                    : EmptyState(
                        icon: Icons.history,
                        title: t.empty,
                        body: t.emptyHint,
                        action: FilledButton.icon(
                          onPressed: () => ref.read(openSearchProvider)(),
                          icon: const Icon(Icons.search),
                          label: Text(t.goSearch),
                        ),
                      ),
              _ when loaded != null => _HistoryList(
                state: loaded,
                grouped: filter.sort != HistorySort.mostPlayed,
                collapsed: _collapsed,
                onToggleDay: (day) => setState(() {
                  if (!_collapsed.remove(day)) _collapsed.add(day);
                }),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }

  /// 多選的「刪除」：確認（紅色鈕）、刪、提示筆數。回 `true` 離開選取模式。
  Future<bool> _deleteSelected(List<int> ids) async {
    final t = ref.read(translationsProvider).history;
    final confirmed = await showDestructiveConfirm(
      context,
      title: t.deleteSelectedTitle(count: ids.length),
      body: t.deleteSelectedBody,
      confirmLabel: t.delete,
      cancelLabel: t.cancel,
    );
    if (!confirmed || !mounted) return false;
    final toaster = ref.read(toasterProvider);
    try {
      final deleted = await ref
          .read(playHistoryRepositoryProvider)
          .deleteMany(ids);
      toaster.success(t.deletedCount(count: deleted));
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to delete play history entries',
        tag: 'history',
      );
      return false;
    }
    return true;
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).history;
    final confirmed = await showDestructiveConfirm(
      context,
      title: t.clearTitle,
      body: t.clearBody,
      confirmLabel: t.confirm,
      cancelLabel: t.cancel,
    );
    if (!confirmed) return;
    final toaster = ref.read(toasterProvider);
    try {
      await ref.read(playHistoryRepositoryProvider).clear();
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to clear the play history',
        tag: 'history',
      );
      return;
    }
    toaster.success(t.cleared);
  }
}

/// 標題列：返回鈕、標題（搜尋時換成輸入框）與右側的日期、搜尋、「⋯」。
///
/// 標題列各頁之後會統一換成置中的 `PageAppBar`（ADR 0035 §決定 2），所以這裡只是一個
/// 獨立的小元件：搬走時整個換掉。
class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.searching,
    required this.searchController,
    required this.clearEnabled,
    required this.onQueryChanged,
    required this.onPickDate,
    required this.onSearch,
    required this.onCloseSearch,
    required this.onClearAll,
  });

  final bool searching;
  final TextEditingController searchController;
  final bool clearEnabled;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onPickDate;
  final VoidCallback onSearch;
  final VoidCallback onCloseSearch;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).history;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    // 下面還有頁（巢狀導覽裡的內頁）時才有返回鈕，同 AppBar 的判斷。
    final canGoBack = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.x4,
        spacing.x4,
        spacing.x2,
        spacing.x2,
      ),
      child: Row(
        children: [
          if (canGoBack)
            IconButton(
              tooltip: ref.watch(translationsProvider).shell.backTooltip,
              icon: const BackButtonIcon(),
              onPressed: () => unawaited(Navigator.of(context).maybePop()),
            ),
          Expanded(
            child: searching
                ? TextField(
                    controller: searchController,
                    autofocus: true,
                    onChanged: onQueryChanged,
                    decoration: InputDecoration(
                      hintText: t.searchHint,
                      border: InputBorder.none,
                    ),
                  )
                : Semantics(
                    header: true,
                    child: Text(t.title, style: theme.textTheme.headlineSmall),
                  ),
          ),
          IconButton(
            tooltip: t.selectDate,
            icon: const Icon(Icons.calendar_today),
            onPressed: onPickDate,
          ),
          if (searching)
            IconButton(
              tooltip: t.closeSearch,
              icon: const Icon(Icons.close),
              onPressed: onCloseSearch,
            )
          else
            IconButton(
              tooltip: t.search,
              icon: const Icon(Icons.search),
              onPressed: onSearch,
            ),
          PopupMenuButton<void>(
            tooltip: t.pageMore,
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                enabled: clearEnabled,
                onTap: onClearAll,
                child: Row(
                  children: [
                    const Icon(Icons.delete_sweep_outlined),
                    SizedBox(width: spacing.x3),
                    Flexible(
                      child: Text(t.clearAll, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 統計卡：今天、本週、全部的首數與總時長（不受篩選影響）。讀到之前不出現。
class _StatsCard extends ConsumerWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(historyStatsProvider).value;
    if (stats == null) return const SizedBox.shrink();
    final t = ref.watch(translationsProvider).history;
    final scheme = Theme.of(context).colorScheme;
    final spacing = AppTokens.of(context).spacing;
    final tokens = AppTokens.of(context);
    String duration(Duration value) {
      final hours = value.inHours;
      final minutes = value.inMinutes % 60;
      return hours > 0
          ? t.durationHm(hours: hours, minutes: minutes)
          : t.durationM(minutes: minutes);
    }

    // 一格讀成一句（「今天，2 首，3 分鐘」），不是三個分開的項目。
    Widget item(String label, HistoryPeriodStats period) => Expanded(
      child: MergeSemantics(
        child: Column(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            SizedBox(height: spacing.x1),
            Text(
              t.statsCount(count: period.count),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              duration(period.duration),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.x4,
        vertical: spacing.x2,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(tokens.radius.medium),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.x4,
            vertical: spacing.x3,
          ),
          child: Row(
            children: [
              item(t.statsToday, stats.today),
              item(t.statsWeek, stats.week),
              item(t.statsAll, stats.all),
            ],
          ),
        ),
      ),
    );
  }
}

/// 篩選列：「全部」與每個音源的 chip、選了日期時的日期 chip（可移除），最右邊是排序。
class _FilterRow extends ConsumerWidget {
  const _FilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).history;
    final filter = ref.watch(historyFilterProvider);
    final notifier = ref.read(historyFilterProvider.notifier);
    final sources = ref.watch(searchSourcesProvider).value ?? const [];
    final spacing = AppTokens.of(context).spacing;
    final dates = MaterialLocalizations.of(context);
    final day = filter.day;
    String sortLabel(HistorySort sort) => switch (sort) {
      HistorySort.newest => t.sortNewest,
      HistorySort.oldest => t.sortOldest,
      HistorySort.mostPlayed => t.sortMostPlayed,
    };
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.x4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(t.filterAll),
                    selected: filter.source == null,
                    onSelected: (_) => notifier.setSource(null),
                  ),
                  for (final source in sources) ...[
                    SizedBox(width: spacing.x2),
                    ChoiceChip(
                      label: Text(source.manifest.name),
                      selected: filter.source == source.manifest.id,
                      onSelected: (_) => notifier.setSource(source.manifest.id),
                    ),
                  ],
                  if (day != null) ...[
                    SizedBox(width: spacing.x2),
                    InputChip(
                      avatar: const Icon(Icons.calendar_today),
                      label: Text(dates.formatMediumDate(day)),
                      deleteButtonTooltipMessage: t.clearDate,
                      onDeleted: () => notifier.setDay(null),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(width: spacing.x2),
          MenuAnchor(
            menuChildren: [
              for (final sort in HistorySort.values)
                RadioMenuButton<HistorySort>(
                  value: sort,
                  groupValue: filter.sort,
                  onChanged: (value) {
                    if (value != null) notifier.setSort(value);
                  },
                  child: Text(sortLabel(sort)),
                ),
            ],
            builder: (context, controller, _) => ActionChip(
              tooltip: t.sortTooltip,
              avatar: const Icon(Icons.sort),
              label: Text(sortLabel(filter.sort)),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({
    required this.state,
    required this.grouped,
    required this.collapsed,
    required this.onToggleDay,
  });

  final HistoryState state;

  /// 依日期分組成時間軸；排序選「播放次數」時為假，一首一列。
  final bool grouped;
  final Set<DateTime> collapsed;
  final ValueChanged<DateTime> onToggleDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = AppTokens.of(context).spacing;
    // 折疊起來的日子只留標頭；標頭的首數是已載入的紀錄。
    final rows = <HistoryRow>[];
    final counts = <DateTime, int>{};
    if (grouped) {
      final all = groupByDay(state.entries);
      DateTime? current;
      for (final row in all) {
        switch (row) {
          case HistoryDay(:final day):
            current = day;
            rows.add(row);
          case HistoryItem():
            counts.update(current!, (n) => n + 1, ifAbsent: () => 1);
            if (!collapsed.contains(current)) rows.add(row);
        }
      }
    } else {
      rows.addAll(state.entries.map(HistoryItem.new));
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: spacing.x4),
      itemCount: rows.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == rows.length) {
          // 捲到這裡了：讀下一頁。不在 build 裡改狀態，排到這一幀之後。
          SchedulerBinding.instance.addPostFrameCallback(
            (_) => unawaited(ref.read(historyProvider.notifier).loadMore()),
          );
          return const _LoadingMore();
        }
        return switch (rows[index]) {
          HistoryDay(:final day) => _DayHeader(
            day: day,
            count: counts[day] ?? 0,
            collapsed: collapsed.contains(day),
            onToggle: () => onToggleDay(day),
          ),
          HistoryItem(:final entry) => _HistoryTile(
            key: ValueKey(entry.id),
            entry: entry,
            timeline: grouped,
          ),
        };
      },
    );
  }
}

class _LoadingMore extends StatelessWidget {
  const _LoadingMore();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(AppTokens.of(context).spacing.x4),
    child: const Center(child: CircularProgressIndicator()),
  );
}

/// 時間軸左欄那條貫穿的線；放在 [Stack] 裡畫在一列的後面。
class _TimelineLine extends StatelessWidget {
  const _TimelineLine({this.top = 0});

  final double top;

  @override
  Widget build(BuildContext context) => Positioned(
    left: (AppLayout.timelineColumn - AppLayout.timelineLine) / 2,
    width: AppLayout.timelineLine,
    top: top,
    bottom: 0,
    child: ColoredBox(color: Theme.of(context).colorScheme.outlineVariant),
  );
}

/// 一天的標頭（舊版的時間軸）：主色圓點、日期、「N 首」與折疊的箭頭；點一下折疊或展開。
class _DayHeader extends ConsumerWidget {
  const _DayHeader({
    required this.day,
    required this.count,
    required this.collapsed,
    required this.onToggle,
  });

  final DateTime day;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).history;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = AppTokens.of(context).spacing;
    final dates = MaterialLocalizations.of(context);
    final label = switch (dayKindOf(day)) {
      HistoryDayKind.today => t.today,
      HistoryDayKind.yesterday => t.yesterday,
      // 同一年不帶年份，跨年才帶。
      HistoryDayKind.other when day.year == clock.now().year =>
        dates.formatMediumDate(day),
      HistoryDayKind.other => dates.formatShortDate(day),
    };
    return Semantics(
      header: true,
      button: true,
      expanded: !collapsed,
      excludeSemantics: true,
      label: '$label, ${t.dayCount(count: count)}',
      hint: collapsed ? t.dayExpand(day: label) : t.dayCollapse(day: label),
      onTap: onToggle,
      child: InkWell(
        onTap: onToggle,
        child: SizedBox(
          height: AppLayout.timelineHeaderHeight,
          child: Stack(
            children: [
              // 圓點中心以下才有線。
              if (!collapsed)
                _TimelineLine(top: AppLayout.timelineHeaderHeight / 2),
              Row(
                children: [
                  SizedBox(
                    width: AppLayout.timelineColumn,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(
                          dimension: AppLayout.timelineDot,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(width: spacing.x2),
                  Text(
                    t.dayCount(count: count),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    collapsed ? Icons.expand_more : Icons.expand_less,
                    color: scheme.onSurfaceVariant,
                  ),
                  SizedBox(width: spacing.x4),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 音源的小徽章：插件名稱的第一個字（還沒有插件圖示的元件可用；音源圖示之後統一，見
/// PR 13）。
class _SourceBadge extends ConsumerWidget {
  const _SourceBadge({required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).history;
    final scheme = Theme.of(context).colorScheme;
    final name = ref.watch(pluginNameProvider(pluginId)) ?? pluginId;
    final initial = name.characters.isEmpty ? '?' : name.characters.first;
    return Semantics(
      label: t.sourceIcon(name: name),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: AppLayout.sourceBadge,
          child: Center(
            child: Text(
              initial.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一筆紀錄：封面、曲名、「作者 · 播放時刻」、時長、音源徽章、「⋯」。音源不可用時作者換成
/// 原因。點一下臨時播放；選單在右鍵與「⋯」（[SelectableTrackRow]），長按進入多選。正在
/// 播的那一首封面疊 [NowPlayingOverlay]、曲名主色粗體。
class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({super.key, required this.entry, required this.timeline});

  final PlayHistoryEntry entry;

  /// 左邊有時間軸的欄與貫穿的線。
  final bool timeline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).history;
    final scheme = Theme.of(context).colorScheme;
    final track = entry.track;
    // 音源停用或移除時，「作者」的位置改說原因（ADR 0030 §決定 7、10）。
    final uploader =
        ref.watch(sourceUnavailableProvider(track.sourceTypeId)) ??
        track.uploader;
    final local = entry.playedAt.toLocal();
    // HH:mm：24 小時制，不隨系統的 12 小時設定（日界與時刻都依裝置的本地時間）。
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: true,
    );
    // 依播放次數排序時一首一列，副標的時刻換成次數。
    final detail = timeline ? time : t.playCount(count: entry.playCount);
    final playing = ref.watch(
      playbackQueueProvider.select(
        (queue) => queue.value?.current?.key == track.key,
      ),
    );
    final duration = track.duration;

    final inMix = ref.watch(inMixProvider);
    final canMix = ref.watch(canStartMixProvider(track.sourceTypeId));

    void play() =>
        unawaited(ref.read(playbackControllerProvider).playTemporary(track));

    void playNext() {
      if (ref.read(playbackControllerProvider).playNext([track])) {
        ref.read(toasterProvider).success(t.addedToNext);
      }
    }

    void addToQueue() {
      if (ref.read(playbackControllerProvider).addToQueue([track])) {
        ref.read(toasterProvider).success(t.addedToQueue);
      }
    }

    // 只移除這一筆，不提示（擁有者決定）；失敗才提示。
    Future<void> remove() async {
      final toaster = ref.read(toasterProvider);
      try {
        await ref.read(playHistoryRepositoryProvider).delete(entry.id);
      } on Object catch (error, stackTrace) {
        toaster.error(
          AppError.wrap(error, stackTrace),
          operation: 'Failed to remove a play history entry',
          tag: 'history',
        );
      }
    }

    // 這首的所有紀錄：確認（紅色鈕），之後提示刪了幾筆。
    Future<void> removeAll() async {
      final confirmed = await showDestructiveConfirm(
        context,
        title: t.removeAllTitle,
        body: t.removeAllBody(title: track.displayTitle),
        confirmLabel: t.delete,
        cancelLabel: t.cancel,
      );
      if (!confirmed) return;
      final toaster = ref.read(toasterProvider);
      try {
        final deleted = await ref
            .read(playHistoryRepositoryProvider)
            .deleteAllForTrack('${track.key}');
        toaster.success(t.deletedCount(count: deleted));
      } on Object catch (error, stackTrace) {
        toaster.error(
          AppError.wrap(error, stackTrace),
          operation: 'Failed to delete the plays of a track',
          tag: 'history',
        );
      }
    }

    final row = SelectableTrackRow<int>(
      selectionKey: entry.id,
      moreTooltip: t.more,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.play_arrow),
          onPressed: play,
          child: Text(t.play),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.queue_play_next),
          onPressed: inMix ? null : playNext,
          child: Text(inMix ? t.playNextInMix : t.playNext),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.add_to_queue),
          onPressed: inMix ? null : addToQueue,
          child: Text(inMix ? t.addToQueueInMix : t.addToQueue),
        ),
        if (canMix)
          MenuItemButton(
            leadingIcon: const Icon(Icons.auto_awesome),
            onPressed: () => unawaited(startMixFrom(ref, track)),
            child: Text(t.startMix),
          ),
        AddToPlaylistItem(
          onPressed: () => unawaited(showAddToPlaylist(context, [track])),
        ),
        AddToRemoteItem(
          pluginIds: {track.sourceTypeId},
          onPressed: () => unawaited(showAddToRemote(context, [track])),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline),
          onPressed: () => unawaited(remove()),
          child: Text(t.remove),
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(foregroundColor: scheme.error),
          leadingIcon: Icon(Icons.delete_forever_outlined, color: scheme.error),
          onPressed: () => unawaited(removeAll()),
          child: Text(t.removeAllOfTrack),
        ),
      ],
      builder: (context, slots) => ListTile(
        selected: slots.selected,
        leading: Stack(
          children: [
            ArtworkImage(
              pluginId: track.sourceTypeId,
              artwork: track.artwork,
              size: AppLayout.artworkThumbnail,
            ),
            if (playing)
              const NowPlayingOverlay(size: AppLayout.artworkThumbnail),
          ],
        ),
        title: Text(
          track.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: playing
              ? TextStyle(fontWeight: FontWeight.bold, color: scheme.primary)
              : null,
        ),
        subtitle: Text(
          uploader == null
              ? detail
              : t.subtitle(artist: uploader, time: detail),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: AppLayout.historyDurationColumn,
              child: Text(
                duration == null ? '' : formatDuration(duration),
                textAlign: TextAlign.end,
              ),
            ),
            SizedBox(width: AppTokens.of(context).spacing.x2),
            _SourceBadge(pluginId: track.sourceTypeId),
            slots.trailing,
          ],
        ),
        onTap: slots.onTap ?? play,
        onLongPress: slots.onLongPress,
      ),
    );
    if (!timeline) return row;
    return Stack(
      children: [
        const _TimelineLine(),
        Padding(
          padding: const EdgeInsets.only(left: AppLayout.timelineColumn),
          child: row,
        ),
      ],
    );
  }
}
