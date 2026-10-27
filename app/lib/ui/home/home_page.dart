import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/charts/chart_entries.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/radio/radio_service.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/charts/home_charts.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/add_to_playlist.dart';
import 'package:fmp/ui/library/add_to_remote.dart';
import 'package:fmp/ui/library/library_page.dart' show PlaylistMenu;
import 'package:fmp/ui/library/library_state.dart';
import 'package:fmp/ui/library/playlist_cover.dart';
import 'package:fmp/ui/library/playlist_actions.dart';
import 'package:fmp/ui/library/playlist_detail_page.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/plugins/plugin_onboarding.dart';
import 'package:fmp/ui/shell/page_app_bar.dart';
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

/// 首頁（ADR 0033 §決定 6，M4 design §10.2）。區塊依序：排行（每個啟用的榜單前 5 首，
/// [HomeCharts]；全部停用或沒有提供排行的音源就沒有這個區塊）、我的歌單（依 `sort_order` 前 20
/// 張，點一下在首頁的巢狀導覽裡開詳情，「查看全部」切到音樂庫）、電台（前 20 個，點一下
/// 收聽，「查看全部」切到電台）、最近播放（一排卡片，點一下臨時播放，「查看全部」在首頁的
/// 巢狀導覽裡開歷史頁）。沒有內容的區塊不顯示，四個都沒有時是說明（啟用的榜單算內容，
/// 還沒有快取、離線也一樣）。
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
    final spacing = AppTokens.of(context).spacing;
    final sources = ref.watch(searchSourcesProvider);
    final hasSource = sources.value?.isNotEmpty ?? false;
    final onboarding = ref.watch(onboardingProvider);
    final recent = ref.watch(recentPlaysProvider);
    final playlistsState = ref.watch(playlistOverviewsProvider);
    final radioState = ref.watch(radioEntriesProvider);
    final playlists = [...?playlistsState.value?.take(homeShelfCount)];
    // 開播中的排前面（穩定排序），再取前 20 個。
    final stations = [
      ...liveFirst(radioState.value ?? const []).take(homeShelfCount),
    ];
    // `null`＝插件清單、榜單設定或榜單清單還在讀。
    final charts = ref.watch(enabledChartsProvider);
    // 三份資料到齊才判斷「沒有內容」，免得說明一閃而過。
    final loading =
        playlistsState is AsyncLoading || radioState is AsyncLoading;
    // 歌單讀到了而且是空的：「我的歌單」區塊只有「建立歌單」卡（舊版 B-16）。讀失敗不算。
    final noPlaylists = playlistsState is AsyncData && playlists.isEmpty;
    final title = PageAppBar(title: t.title);
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
      // 其他都沒有內容而榜單還在讀：等它，免得說明一閃而過。
      AsyncData(:final value)
          when value.isEmpty &&
              playlists.isEmpty &&
              stations.isEmpty &&
              charts == null =>
        const SizedBox.shrink(),
      AsyncData(:final value)
          when value.isEmpty &&
              playlists.isEmpty &&
              stations.isEmpty &&
              charts!.isEmpty =>
        // 「建立歌單」的入口在說明上方，說明不會把它擠掉。
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (noPlaylists) _createPlaylistShelf(t.myPlaylists),
            Expanded(
              child: EmptyState(
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
            ),
          ],
        ),
      AsyncData(:final value) => ListView(
        padding: EdgeInsets.only(bottom: spacing.x4),
        children: [
          if (charts != null && charts.isNotEmpty) HomeCharts(charts: charts),
          if (noPlaylists) _createPlaylistShelf(t.myPlaylists),
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
        error: true,
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

/// 沒有歌單時的「我的歌單」：沒有「查看全部」，只有「建立歌單」的灰色佔位卡。
Widget _createPlaylistShelf(String title) =>
    _Shelf(title: title, children: const [_CreatePlaylistCard()]);

/// 一個首頁區塊的標題列：標題（語意標題）與尾端的「查看全部」。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

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
          ?action,
        ],
      ),
    );
  }
}

/// 一個區塊：標題列與一排可橫向捲動的卡片（YouTube Music 首頁的一排卡片）。
class _Shelf extends StatelessWidget {
  const _Shelf({required this.title, this.onViewAll, required this.children});

  final String title;

  /// 沒有就不放「查看全部」（沒有歌單時的「我的歌單」）。
  final VoidCallback? onViewAll;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: title,
          action: onViewAll == null
              ? null
              : Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: onViewAll,
                    child: Text(ref.watch(translationsProvider).home.viewAll),
                  ),
                ),
        ),
        _ShelfRow(children: children),
      ],
    );
  }
}

/// 一排橫向捲動的卡片（ADR 0035，R6.6）。
///
/// - 滑鼠可以按住拖曳捲動（只開在這一排：`dragDevices` 加上滑鼠，其他捲動區不受影響）。
/// - 滑鼠移入時，兩端出現漸層與左右箭頭（觸控沒有：手指直接滑）；該方向捲到底就不出現。
/// - 卡片數有上限（20），整排一起建；Row 取最高那張的高度，字放大時不會被截掉。
class _ShelfRow extends ConsumerStatefulWidget {
  const _ShelfRow({required this.children});

  final List<Widget> children;

  @override
  ConsumerState<_ShelfRow> createState() => _ShelfRowState();
}

class _ShelfRowState extends ConsumerState<_ShelfRow> {
  final _controller = ScrollController();

  /// 滑鼠在這一排上。
  var _hovering = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollBy(double direction) {
    final position = _controller.position;
    final target =
        (position.pixels + direction * position.viewportDimension * 0.8).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    unawaited(
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacing = AppTokens.of(context).spacing;
    final t = ref.watch(translationsProvider).home;
    final behavior = ScrollConfiguration.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Stack(
        children: [
          ScrollConfiguration(
            behavior: behavior.copyWith(
              dragDevices: {...behavior.dragDevices, PointerDeviceKind.mouse},
            ),
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.fromLTRB(
                spacing.x3,
                spacing.x2,
                spacing.x3,
                spacing.x3,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.children,
              ),
            ),
          ),
          if (_hovering)
            // 捲動位置一變就重畫箭頭（到頭的那一端收起來）。
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final hasClients = _controller.hasClients;
                final position = hasClients ? _controller.position : null;
                final canLeft =
                    position != null &&
                    position.pixels > position.minScrollExtent;
                final canRight =
                    position != null &&
                    position.pixels < position.maxScrollExtent;
                return Positioned.fill(
                  child: Row(
                    children: [
                      if (canLeft)
                        _ShelfArrow(
                          icon: Icons.chevron_left,
                          tooltip: t.scrollLeft,
                          start: true,
                          onPressed: () => _scrollBy(-1),
                        ),
                      const Spacer(),
                      if (canRight)
                        _ShelfArrow(
                          icon: Icons.chevron_right,
                          tooltip: t.scrollRight,
                          start: false,
                          onPressed: () => _scrollBy(1),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// 一排卡片一端的漸層與箭頭鈕。漸層只是遮罩（`IgnorePointer`：點擊、滾輪與拖曳穿過去落在卡片上），
/// 鈕本身才吃。
class _ShelfArrow extends StatelessWidget {
  const _ShelfArrow({
    required this.icon,
    required this.tooltip,
    required this.start,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;

  /// 在左端（寫入方向的起點）。
  final bool start;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final fade = start
        ? [surface, surface.withValues(alpha: 0)]
        : [surface.withValues(alpha: 0), surface];
    return SizedBox(
      width: AppLayout.shelfEdgeFade,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: fade,
                ),
              ),
            ),
          ),
          Center(
            child: IconButton.filledTonal(
              tooltip: tooltip,
              icon: Icon(icon),
              onPressed: onPressed,
            ),
          ),
        ],
      ),
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

/// 一排裡的一張卡片（我的歌單、電台、最近播放共用）：有底色的 `Card`，封面在上、[text] 在下；
/// 整張是一個按鈕，點一下執行 [onTap]，長按執行 [onLongPress]。
///
/// [more]（選單的「⋯」）疊在文字旁、不在卡片的點擊區裡：卡片是一個按鈕的語意節點（點一下
/// 播放或開啟），「⋯」是另一個，螢幕閱讀器才分得出兩個動作。
class _ShelfCard extends StatelessWidget {
  const _ShelfCard({
    required this.cover,
    required this.text,
    required this.onTap,
    this.onLongPress,
    this.more,
  });

  final Widget cover;
  final Widget text;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? more;

  @override
  Widget build(BuildContext context) {
    final spacing = AppTokens.of(context).spacing;
    final more = this.more;
    return Card(
      margin: EdgeInsets.all(spacing.x1),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: AppLayout.shelfCardWidth,
        child: Stack(
          children: [
            MergeSemantics(
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                // 同 ListTile：可點的卡片是一個按鈕。
                child: Semantics(
                  button: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      cover,
                      Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: spacing.x2,
                          end: more == null
                              ? spacing.x2
                              : kMinInteractiveDimension,
                          top: spacing.x2,
                          bottom: spacing.x2,
                        ),
                        child: text,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (more != null)
              PositionedDirectional(
                end: 0,
                top: AppLayout.shelfCardWidth,
                child: more,
              ),
          ],
        ),
      ),
    );
  }
}

/// 卡片文字一行的樣式：行高固定（`forceStrutHeight`），中英文、後備字型的行都一樣高，
/// [_linesHeight] 算得出確切的高度。
TextStyle _cardLineStyle(TextStyle style) =>
    style.copyWith(height: style.height ?? _defaultLineHeight);

/// 主題的字級角色沒有行高時的行高倍數（M3 的字級角色都有，這只是保底）。
const _defaultLineHeight = 1.4;

/// [lines] 行 [style]（[_cardLineStyle] 過的）在目前的字級縮放下的高度。
double _linesHeight(BuildContext context, TextStyle style, int lines) =>
    MediaQuery.textScalerOf(context).scale(style.fontSize!) *
    style.height! *
    lines;

/// 卡片上固定行數的一段字：不論內容幾行都佔 [lines] 行的高度、超過的截斷，同一排的卡片才一樣高
/// （舊版的卡片是固定大小）。高度隨字級縮放，放大字也不會溢出。
class _CardLines extends StatelessWidget {
  const _CardLines({
    required this.text,
    required this.style,
    required this.lines,
    this.leading,
  });

  final String? text;
  final TextStyle style;
  final int lines;

  /// 字前面的小圖示（匯入歌單的連結圖示）。
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final style = _cardLineStyle(this.style);
    final text = this.text;
    final leading = this.leading;
    final paragraph = text == null
        ? null
        : Text(
            text,
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
            style: style,
            strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
          );
    return SizedBox(
      height: _linesHeight(context, style, lines),
      child: leading == null || paragraph == null
          ? paragraph
          : Row(
              children: [
                Icon(
                  leading,
                  size: MediaQuery.textScalerOf(context).scale(style.fontSize!),
                  color: style.color,
                ),
                SizedBox(width: AppTokens.of(context).spacing.x1),
                Flexible(child: paragraph),
              ],
            ),
    );
  }
}

/// 卡片上的文字：名稱（固定 [titleLines] 行）與 [detail]。同一排的卡片給同樣的行數與同一種
/// [detail]（[_CardLines] 或狀態標記），高度才一樣。
class _CardText extends StatelessWidget {
  const _CardText({required this.title, this.titleLines = 1, this.detail});

  final String title;
  final int titleLines;
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardLines(
          text: title,
          lines: titleLines,
          style: Theme.of(context).textTheme.bodyMedium!,
        ),
        ?detail,
      ],
    );
  }
}

/// 卡片的副標一行（bodySmall、次要色）：[text] 是 `null` 時仍佔一行。
Widget _cardDetail(
  BuildContext context,
  String? text, {
  IconData? leading,
  String? leadingLabel,
}) {
  final theme = Theme.of(context);
  final line = _CardLines(
    text: text,
    lines: 1,
    leading: leading,
    style: theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    ),
  );
  // 圖示是裝飾，意思（「匯入」）給螢幕閱讀器。
  return leadingLabel == null
      ? line
      : Semantics(label: leadingLabel, child: line);
}

/// 「建立歌單」佔位卡（沒有歌單時「我的歌單」唯一的內容）：灰底、大「＋」，走音樂庫同一條建立流程
/// （[createPlaylist]），不是切到音樂庫。
class _CreatePlaylistCard extends ConsumerWidget {
  const _CreatePlaylistCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).home;
    final scheme = Theme.of(context).colorScheme;
    return _ShelfCard(
      cover: SizedBox.square(
        dimension: AppLayout.shelfCardWidth,
        child: Icon(
          Icons.add,
          size: AppLayout.emptyStateIcon,
          color: scheme.primary,
        ),
      ),
      text: _CardText(title: t.createPlaylist),
      onTap: () => unawaited(createPlaylist(context, ref)),
    );
  }
}

/// 一張歌單：封面、名稱、首數（同舊版首頁的歌單卡）。點一下在首頁的巢狀導覽裡開詳情；
/// 選單（右鍵、長按、「⋯」）同音樂庫的卡片。
class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({super.key, required this.overview});

  final PlaylistOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).library;
    return PlaylistMenu(
      overview: overview,
      builder: (context, more, openMenu) => _ShelfCard(
        cover: PlaylistCover(
          artwork: overview.playlist.artwork,
          firstTrack: overview.firstTrack,
          size: AppLayout.shelfCardWidth,
        ),
        // 同舊版首頁的歌單卡：名稱一行，副標只有首數（匯入的前面一個連結圖示），窄卡片上
        // 「匯入 · n 首」會把有用的首數截掉。Mix 不存曲目，寫「Mix」。
        text: _CardText(
          title: overview.playlist.name,
          detail: switch (overview.playlist.kind) {
            PlaylistKind.mix => _cardDetail(context, t.mix),
            PlaylistKind.local => _cardDetail(
              context,
              trackCountText(t, overview.trackCount),
            ),
            PlaylistKind.imported => _cardDetail(
              context,
              trackCountText(t, overview.trackCount),
              leading: Icons.link,
              leadingLabel: t.imported,
            ),
          },
        ),
        onTap: () => unawaited(openPlaylist(context, overview.playlist.id)),
        onLongPress: openMenu,
        more: more,
      ),
    );
  }
}

/// 一個電台：封面、標題、狀態標記（四種）。點一下收聽；音源不能用時不播、提示原因（同電台頁）。
/// 選單同電台頁（刪除，先確認）。
class _StationCard extends ConsumerWidget {
  const _StationCard({super.key, required this.entry});

  final RadioEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = entry.station;
    final unavailable = ref.watch(sourceUnavailableProvider(station.pluginId));
    final t = ref.watch(translationsProvider).radio;
    return TrackRowMenu(
      moreTooltip: t.more,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline),
          onPressed: () => unawaited(removeStation(context, ref, station)),
          child: Text(t.remove),
        ),
      ],
      builder: (context, more, openMenu) => _ShelfCard(
        cover: ArtworkImage(
          pluginId: station.pluginId,
          artwork: station.artwork,
          size: AppLayout.shelfCardWidth,
          rounded: false,
        ),
        text: _CardText(
          title: station.title,
          detail: TaggedLine(tag: RadioStatusTag(status: entry.status)),
        ),
        onTap: () {
          if (unavailable != null) {
            ref
                .read(toasterProvider)
                .warning(t.cannotPlay(reason: unavailable));
            return;
          }
          unawaited(
            ref
                .read(playbackControllerProvider)
                .playLive(radioLiveTarget(station)),
          );
        },
        onLongPress: openMenu,
        more: more,
      ),
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
      builder: (context, more, openMenu) => _ShelfCard(
        cover: ArtworkImage(
          pluginId: track.sourceTypeId,
          artwork: track.artwork,
          size: AppLayout.shelfCardWidth,
          rounded: false,
        ),
        // 同舊版：曲名兩行；作者一行（沒有作者也佔著，同一排才一樣高）。
        text: _CardText(
          title: track.displayTitle,
          titleLines: 2,
          detail: _cardDetail(context, uploader),
        ),
        onTap: play,
        onLongPress: openMenu,
        more: more,
      ),
    );
  }
}
