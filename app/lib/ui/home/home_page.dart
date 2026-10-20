import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/radio/radio_service.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/add_to_playlist.dart';
import 'package:fmp/ui/library/add_to_remote.dart';
import 'package:fmp/ui/library/library_state.dart';
import 'package:fmp/ui/library/playlist_cover.dart';
import 'package:fmp/ui/library/playlist_detail_page.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/plugins/plugin_onboarding.dart';
import 'package:fmp/ui/radio/radio_page.dart';
import 'package:fmp/ui/radio/radio_status_tag.dart';
import 'package:fmp/ui/search/search_state.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/start_mix.dart';
import 'package:fmp/ui/tracks/track_row_menu.dart';

/// 首頁「我的歌單」「電台」兩個區塊的項數上限（ADR 0033 §決定 6）。
const homeShelfCount = 20;

/// 首頁「最近播放」的筆數（ADR 0033 §決定 6）：`play_history` 最新的這麼多筆，不去重。
const recentPlaysCount = 20;

/// 最近播放：與歷史頁同一份資料，歷史表一變動就重讀（先訂閱再讀，讀的期間的變動排在
/// 後面再讀一次）；讀失敗發出錯誤、之後的變動照樣重讀。
final recentPlaysProvider = StreamProvider<List<PlayHistoryEntry>>((
  ref,
) async* {
  final repository = ref.watch(playHistoryRepositoryProvider);
  final changed = StreamController<void>();
  final changes = repository.changes().listen(changed.add);
  ref.onDispose(() {
    unawaited(changes.cancel());
    unawaited(changed.close());
  });
  Stream<List<PlayHistoryEntry>> read() async* {
    try {
      yield await repository.page(limit: recentPlaysCount);
    } on Object catch (error, stackTrace) {
      yield* Stream.error(error, stackTrace);
    }
  }

  yield* read();
  await for (final _ in changed.stream) {
    yield* read();
  }
});

/// 首頁（ADR 0033 §決定 6，M4 design §10.2）。區塊依序：我的歌單（依 `sort_order` 前 20
/// 張，點一下在首頁的巢狀導覽裡開詳情，「查看全部」切到音樂庫）、電台（前 20 個，點一下
/// 收聽，「查看全部」切到電台）、最近播放（一排卡片，點一下臨時播放，「查看全部」在首頁的
/// 巢狀導覽裡開歷史頁）。沒有內容的區塊不顯示，三個都沒有時是說明。排行的區塊之後加在
/// 最前面。
///
/// 沒有任何可搜尋的音源而且還沒按「稍後再說」時，整頁是首次啟動引導（與搜尋頁同一個
/// 元件，ADR 0030 §決定 12）。沒有內容時是說明；沒有音源時說明附「前往插件頁」。本機
/// 資料，離線照常顯示。
class HomePage extends ConsumerWidget {
  const HomePage({
    super.key,
    required this.onOpenPlugins,
    required this.onOpenLibrary,
    required this.onOpenRadio,
  });

  /// 開插件頁（設定頁的「插件」區塊）。
  final VoidCallback onOpenPlugins;

  /// 換到音樂庫、電台目的地（「我的歌單」「電台」的「查看全部」）。
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenRadio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 讀資料庫失敗：報一次（畫面是錯誤狀態，不是「沒有內容」）。
    ref.listen(recentPlaysProvider, (previous, next) {
      if (next case AsyncError(:final error, :final stackTrace)
          when previous is! AsyncError) {
        ref
            .read(logProvider)
            .report(
              'Failed to load the recent plays',
              AppError.wrap(error, stackTrace),
              tag: 'history',
            );
      }
    });
    // 歌單與電台讀失敗：那個區塊不顯示，這裡不報。音樂庫與電台頁一直掛在外殼裡、讀同一個
    // provider，由它們報（顯示錯誤），同一個失敗才只進錯誤歷史一次。
    final translations = ref.watch(translationsProvider);
    final t = translations.home;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final sources = ref.watch(searchSourcesProvider);
    final hasSource = sources.value?.isNotEmpty ?? false;
    final onboarding = ref.watch(onboardingProvider);
    final recent = ref.watch(recentPlaysProvider);
    final playlistsState = ref.watch(playlistOverviewsProvider);
    final radioState = ref.watch(radioEntriesProvider);
    final playlists = [...?playlistsState.value?.take(homeShelfCount)];
    final stations = [...?radioState.value?.take(homeShelfCount)];
    // 三份資料到齊才判斷「沒有內容」，免得說明一閃而過。
    final loading =
        playlistsState is AsyncLoading || radioState is AsyncLoading;
    final title = Padding(
      padding: EdgeInsets.fromLTRB(spacing.x4, spacing.x4, spacing.x4, 0),
      child: Semantics(
        header: true,
        child: Text(t.title, style: theme.textTheme.headlineSmall),
      ),
    );
    // 插件清單還沒載入完時不判斷引導，免得一閃而過。
    if (sources is AsyncData &&
        showOnboarding(hasSource: hasSource, state: onboarding)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          Expanded(child: PluginOnboarding(hasSource: hasSource)),
        ],
      );
    }
    final Widget body = switch (recent) {
      AsyncData() when loading => const SizedBox.shrink(),
      // 圖示不用音樂庫導覽項的那一個：整合測試以圖示找導覽項。
      AsyncData(:final value)
          when value.isEmpty && playlists.isEmpty && stations.isEmpty =>
        EmptyState(
          icon: Icons.music_note_outlined,
          title: t.empty,
          body: t.emptyHint,
          action: sources is AsyncData && !hasSource
              ? FilledButton.tonal(
                  onPressed: onOpenPlugins,
                  child: Text(translations.onboarding.goToPlugins),
                )
              : null,
        ),
      AsyncData(:final value) => ListView(
        padding: EdgeInsets.only(bottom: spacing.x4),
        children: [
          if (playlists.isNotEmpty)
            _Shelf(
              title: t.myPlaylists,
              onViewAll: onOpenLibrary,
              children: [
                for (final overview in playlists)
                  _PlaylistCard(
                    key: ValueKey(overview.playlist.id),
                    overview: overview,
                  ),
              ],
            ),
          if (stations.isNotEmpty)
            _Shelf(
              title: t.radio,
              onViewAll: onOpenRadio,
              children: [
                for (final entry in stations)
                  _StationCard(key: ValueKey(entry.station.id), entry: entry),
              ],
            ),
          if (value.isNotEmpty) _RecentPlays(entries: value),
        ],
      ),
      // 讀失敗（已在 provider 報過）：不是「沒有內容」。
      AsyncError(:final error) => EmptyState(
        icon: Icons.error_outline,
        title: errorMessage(
          translations,
          AppError.wrap(error, StackTrace.current),
        ),
      ),
      AsyncLoading() => const SizedBox.shrink(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        Expanded(child: body),
      ],
    );
  }
}

/// 一個首頁區塊的標題列：標題（語意標題）與尾端的「查看全部」。之後的排行區塊照這個樣子。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action});

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final spacing = AppTokens.of(context).spacing;
    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.x4, spacing.x4, spacing.x2, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          action,
        ],
      ),
    );
  }
}

/// 一個區塊：標題列與一排可橫向捲動的卡片（YouTube Music 首頁的一排卡片）。
class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.title,
    required this.onViewAll,
    required this.children,
  });

  final String title;
  final VoidCallback onViewAll;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spacing = AppTokens.of(context).spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: title,
          action: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: onViewAll,
              child: Text(ref.watch(translationsProvider).home.viewAll),
            ),
          ),
        ),
        // 卡片數有上限（20），整排一起建；Row 取最高那張的高度，字放大時不會被截掉。
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(
            spacing.x3,
            spacing.x2,
            spacing.x3,
            spacing.x3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// 「最近播放」：最新的 [entries] 一排卡片，「查看全部」開歷史頁。
class _RecentPlays extends ConsumerWidget {
  const _RecentPlays({required this.entries});

  final List<PlayHistoryEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).home;
    return _Shelf(
      title: t.recentlyPlayed,
      onViewAll: () => unawaited(openHistory(context)),
      children: [
        for (final entry in entries)
          _RecentCard(key: ValueKey(entry.id), entry: entry),
      ],
    );
  }
}

/// 沒有選單的卡片（我的歌單、電台）：封面、名稱（兩行）、[detail]；整張是一個按鈕，點一下
/// 執行 [onTap]。
class _ShelfCard extends StatelessWidget {
  const _ShelfCard({
    required this.cover,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final Widget cover;
  final String title;
  final Widget detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final spacing = tokens.spacing;
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radius.small),
        onTap: onTap,
        // 同 ListTile：可點的卡片是一個按鈕。
        child: Semantics(
          button: true,
          child: Padding(
            padding: EdgeInsets.all(spacing.x1),
            child: SizedBox(
              width: AppLayout.shelfCardWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cover,
                  SizedBox(height: spacing.x2),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  detail,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一張歌單：封面、名稱、「本機 · n 首」（同音樂庫的卡）。點一下在首頁的巢狀導覽裡開詳情。
class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({super.key, required this.overview});

  final PlaylistOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).library;
    final theme = Theme.of(context);
    return _ShelfCard(
      cover: PlaylistCover(
        artwork: overview.playlist.artwork,
        firstTrack: overview.firstTrack,
        size: AppLayout.shelfCardWidth,
      ),
      title: overview.playlist.name,
      detail: Text(
        playlistSubtitleText(t, overview),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () => unawaited(openPlaylist(context, overview.playlist.id)),
    );
  }
}

/// 一個電台：封面、標題、狀態標記（四種）。點一下收聽；音源不能用時不播、提示原因（同電台頁）。
class _StationCard extends ConsumerWidget {
  const _StationCard({super.key, required this.entry});

  final RadioEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = entry.station;
    final unavailable = ref.watch(sourceUnavailableProvider(station.pluginId));
    return _ShelfCard(
      cover: ArtworkImage(
        pluginId: station.pluginId,
        artwork: station.artwork,
        size: AppLayout.shelfCardWidth,
      ),
      title: station.title,
      detail: TaggedLine(tag: RadioStatusTag(status: entry.status)),
      onTap: () {
        if (unavailable != null) {
          final t = ref.read(translationsProvider).radio;
          ref.read(toasterProvider).warning(t.cannotPlay(reason: unavailable));
          return;
        }
        unawaited(
          ref
              .read(playbackControllerProvider)
              .playLive(radioLiveTarget(station)),
        );
      },
    );
  }
}

/// 一首最近播放的歌：封面、曲名（兩行）、作者（音源不可用時是原因）。點一下臨時播放；選單
/// （右鍵、長按、曲名旁的「⋯」，[TrackRowMenu]）有播放、下一首播放、加入佇列、開始 Mix、
/// 加入歌單…（同歷史頁，沒有「從歷史移除」）。
///
/// 「⋯」疊在卡片的曲名旁、不在卡片的點擊區裡：卡片是一個按鈕的語意節點（點一下播放），「⋯」
/// 是另一個，螢幕閱讀器才分得出兩個動作。
class _RecentCard extends ConsumerWidget {
  const _RecentCard({super.key, required this.entry});

  final PlayHistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).home;
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final spacing = tokens.spacing;
    final track = entry.track;
    final uploader =
        ref.watch(sourceUnavailableProvider(track.sourceTypeId)) ??
        track.uploader;
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
      ],
      builder: (context, more, openMenu) => Stack(
        children: [
          MergeSemantics(
            child: InkWell(
              borderRadius: BorderRadius.circular(tokens.radius.small),
              onTap: play,
              onLongPress: openMenu,
              // 同 ListTile：可點的卡片是一個按鈕。
              child: Semantics(
                button: true,
                child: Padding(
                  padding: EdgeInsets.all(spacing.x1),
                  child: SizedBox(
                    width: AppLayout.shelfCardWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ArtworkImage(
                          pluginId: track.sourceTypeId,
                          artwork: track.artwork,
                          size: AppLayout.shelfCardWidth,
                        ),
                        SizedBox(height: spacing.x2),
                        // 曲名與作者讓出「⋯」的寬度。
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            end: kMinInteractiveDimension,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                              if (uploader != null)
                                Text(
                                  uploader,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            end: 0,
            top: spacing.x1 + AppLayout.shelfCardWidth + spacing.x1,
            child: more,
          ),
        ],
      ),
    );
  }
}
