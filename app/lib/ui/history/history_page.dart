import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/history/history_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/track_row_menu.dart';

/// 歷史頁（design §9.7）：播放過的歌依時間倒序、以本地日期分組（今天、昨天、
/// 日期，跨年才帶年份）。點一首是臨時播放；每筆的選單（右鍵、長按、尾端「⋯」）有
/// 播放、下一首播放、加入佇列、從歷史移除（只移除這一筆，不提示）。標題列的「清除
/// 全部歷史」先確認，清完提示一次。
///
/// 分頁讀取（[historyProvider]）：捲到底才讀下一頁。全部是本機資料，離線照常
/// 可用；封面讀不到時 [ArtworkImage] 是佔位圖。
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).history;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final history = ref.watch(historyProvider);
    final isEmpty = history.value?.entries.isEmpty ?? true;
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
                tooltip: t.clearAll,
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: isEmpty
                    ? null
                    : () => unawaited(_clearAll(context, ref)),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (history) {
            AsyncData(:final value) when value.entries.isEmpty => EmptyState(
              icon: Icons.history,
              title: t.empty,
              body: t.emptyHint,
            ),
            AsyncData(:final value) => _HistoryList(state: value),
            // 讀失敗（已在 `HistoryNotifier` 報過）：不是「沒有紀錄」。
            AsyncError(:final error) => EmptyState(
              icon: Icons.error_outline,
              title: errorMessage(
                ref.watch(translationsProvider),
                AppError.wrap(error, StackTrace.current),
              ),
            ),
            AsyncLoading() => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).history;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.clearTitle),
        content: Text(t.clearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
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

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.state});

  final HistoryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = AppTokens.of(context).spacing;
    final rows = groupByDay(state.entries);
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
          HistoryDay(:final day) => _DayHeader(day: day),
          HistoryItem(:final entry) => _HistoryTile(
            key: ValueKey(entry.id),
            entry: entry,
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

class _DayHeader extends ConsumerWidget {
  const _DayHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).history;
    final theme = Theme.of(context);
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.x4,
        spacing.x4,
        spacing.x4,
        spacing.x1,
      ),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// 一筆紀錄：封面、曲名、「作者 · 播放時刻」、「⋯」。點一下臨時播放；選單在右鍵、
/// 長按與「⋯」，三處同一份（[TrackRowMenu]）。
class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({super.key, required this.entry});

  final PlayHistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).history;
    final track = entry.track;
    final uploader = track.uploader;
    final local = entry.playedAt.toLocal();
    // HH:mm：24 小時制，不隨系統的 12 小時設定（日界與時刻都依裝置的本地時間）。
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: true,
    );

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

    return TrackRowMenu(
      moreTooltip: t.more,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.play_arrow),
          onPressed: play,
          child: Text(t.play),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.queue_play_next),
          onPressed: playNext,
          child: Text(t.playNext),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.add_to_queue),
          onPressed: addToQueue,
          child: Text(t.addToQueue),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline),
          onPressed: () => unawaited(remove()),
          child: Text(t.remove),
        ),
      ],
      builder: (context, more, openMenu) => ListTile(
        leading: ArtworkImage(
          pluginId: track.sourceTypeId,
          artwork: track.artwork,
          size: AppLayout.artworkThumbnail,
        ),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          uploader == null ? time : t.subtitle(artist: uploader, time: time),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: more,
        onTap: play,
        onLongPress: openMenu,
      ),
    );
  }
}
