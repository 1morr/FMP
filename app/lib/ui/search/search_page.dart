import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/live_play.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/radio/radio_service.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/format/count_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/add_to_playlist.dart';
import 'package:fmp/ui/library/add_to_remote.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/plugins/plugin_onboarding.dart';
import 'package:fmp/ui/radio/radio_status_tag.dart';
import 'package:fmp/ui/search/search_state.dart';
import 'package:fmp/ui/search/source_chips.dart';
import 'package:fmp/ui/search/video_parts.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/track_markers.dart';
import 'package:fmp/ui/tracks/start_mix.dart';
import 'package:fmp/ui/tracks/track_row_menu.dart';
import 'package:fmp/ui/tracks/track_selection.dart';

/// 多選的一列：第 [item] 個結果（影片），或它展開後的第 [part] 個分 P。以位置當鍵：
/// 結果換成新的一份時離開選取模式（`_SearchPageState.build` 的 `ref.listen`）。
typedef _ResultKey = ({int item, int? part});

/// 搜尋頁：輸入框、音源 chip 列、結果列表。點一首是臨時播放（D1）：不動佇列，
/// 播完回到佇列。每首的選單（右鍵、尾端「⋯」）有播放、下一首播放、加入
/// 佇列（design §7.3）、加入歌單…、選取。
///
/// 多選（[TrackSelectionScope]，M4 design §10.7，曲目模式）：長按或選單的「選取」進入，
/// 輸入框留著、音源 chip 列換成選取列（Gmail 網頁版在搜尋結果裡的選取）；影片列與分 P 列
/// 都能選，選了有多個分 P 的影片列就是全部分 P（同「加入歌單…」的取法，還沒取過就先取，取不到
/// 時提示、什麼都不做），同一支影片另外選的分 P 不重複加入。新的搜尋、換音源或模式時離開選取模式。
///
/// 離線（design §5.4）：不在 `online` 時照常送出使用者的搜尋（系統的回報可能
/// 是錯的），失敗時結果區換成離線空狀態與「重試」；已有的結果照常顯示。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({
    super.key,
    required this.fieldFocusNode,
    required this.onOpenPlugins,
  });

  /// 輸入框的焦點；外殼的 Ctrl+F 以它把焦點移到輸入框。
  final FocusNode fieldFocusNode;

  /// 開插件頁（設定頁的「插件」區塊）；沒有音源的空狀態有一個入口。
  final VoidCallback onOpenPlugins;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final _text = TextEditingController(text: ref.read(searchInputProvider));
  final _selection = TrackSelection<_ResultKey>();

  @override
  void dispose() {
    _text.dispose();
    _selection.dispose();
    super.dispose();
  }

  /// 已選的列要加入的曲目，依畫面順序：影片列是它的全部分 P（取不到就整個不做，回 `null`），
  /// 影片列也選了的分 P 列略過（已經在裡面）。
  Future<List<TrackInfo>?> _selectedTracks(List<_ResultKey> keys) async {
    final items = ref.read(searchProvider).items;
    final videos = {
      for (final key in keys)
        if (key.part == null) key.item,
    };
    final tracks = <TrackInfo>[];
    for (final (:item, :part) in keys) {
      if (item >= items.length || !mounted) return null;
      final video = items[item].toTrackInfo();
      if (part == null) {
        final all = await _videoTracks(
          ref,
          video,
          partCount: items[item].partCount,
        );
        if (all == null) return null;
        tracks.addAll(all);
      } else if (!videos.contains(item)) {
        final parts =
            ref
                .read(videoPartsProvider)[VideoParts.keyOf(
                  video.sourceTypeId,
                  video.sourceId,
                )]
                ?.parts ??
            const <MultiPart>[];
        if (part < parts.length) tracks.add(parts[part].toTrackInfo(video));
      }
    }
    return tracks;
  }

  /// 畫面上可選的列，依畫面順序：每個影片列，展開的影片接著它的分 P（同 [_TrackTile]）。
  ///
  /// 插件清單只為展開了的影片看（同 [_TrackTile] 的 `select`）：搜尋頁一直掛在外殼裡，沒有結果
  /// 時也監看整份插件清單的話，測試裡在假時間開始的讀取會擋住真實非同步裡的寫入（drift 的鎖）。
  List<_ResultKey> _keys(SearchState search, {required bool rooms}) {
    if (rooms || search.items.isEmpty) return const [];
    final parts = ref.watch(videoPartsProvider);
    bool showsParts(TrackSummary item, VideoPartsEntry entry) =>
        showsExpandButton(
          plugin: ref.watch(
            pluginRegistryProvider.select(
              (plugins) => plugins.value?[item.sourceTypeId],
            ),
          ),
          partCount: item.partCount,
          entry: entry,
        );
    return [
      for (final (index, item) in search.items.indexed) ...[
        (item: index, part: null),
        if (parts[VideoParts.keyOf(item.sourceTypeId, item.sourceId)]
            case final entry? when entry.expanded && showsParts(item, entry))
          for (var part = 0; part < entry.parts.length; part++)
            (item: index, part: part),
      ],
    ];
  }

  void _changed(String input) =>
      ref.read(searchInputProvider.notifier).set(input);

  void _submit(String keyword) =>
      unawaited(ref.read(searchProvider.notifier).search(keyword));

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).search;
    final tokens = AppTokens.of(context);
    final spacing = tokens.spacing;
    final sources = ref.watch(searchSourcesProvider);
    final search = ref.watch(searchProvider);
    final onboarding = ref.watch(onboardingProvider);
    final network = ref.watch(networkStatusProvider);
    final list = sources.value ?? const [];
    final selected = selectedSourceOf(search.sourceId, list);
    // 直播間模式只在選的音源宣告 `live` 時（ADR 0031 §決定 5）；換到沒宣告的音源時
    // notifier 已退回曲目，這裡再擋一次，畫面不會停在沒有分段鈕的直播間模式。
    final hasLive = hasLiveRooms(selected);
    final rooms = hasLive && search.mode == SearchMode.rooms;
    // 新的一份結果（新的搜尋、換音源、模式或篩選都把 `page` 歸零）：選的位置不再是同一首。
    ref.listen(searchProvider, (previous, next) {
      if (next.page < (previous?.page ?? 0)) _selection.exit();
    });
    return TrackSelectionScope<_ResultKey>(
      selection: _selection,
      keys: _keys(search, rooms: rooms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.x4,
              spacing.x4,
              spacing.x4,
              spacing.x2,
            ),
            // 用 TextField 而不是 M3 的 SearchBar：SearchBar 整條可點的那一層
            // 沒有語意名稱，裡面的輸入框只有文字那一行高（24dp），兩個都過不了
            // 點擊區 guideline。外觀照 SearchBar：填色、全圓角、前面放大鏡。
            child: TextField(
              controller: _text,
              focusNode: widget.fieldFocusNode,
              textInputAction: TextInputAction.search,
              onChanged: _changed,
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: rooms ? t.roomHint : t.hint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: ListenableBuilder(
                  listenable: _text,
                  builder: (context, _) => _text.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: t.clear,
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _text.clear();
                            _changed('');
                            widget.fieldFocusNode.requestFocus();
                          },
                        ),
                ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radius.extraLarge),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          TrackSelectionBar<_ResultKey>(
            tracks: _selectedTracks,
            // 結果列自己的音源，不是選的音源：選的音源停用時會退回別的，結果還是舊的。
            pluginIds: (keys) => {
              for (final (:item, part: _) in keys)
                if (item < search.items.length) search.items[item].sourceTypeId,
            },
            padding: EdgeInsets.fromLTRB(spacing.x4, 0, spacing.x4, spacing.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (list.isNotEmpty) ...[
                  SourceChips(
                    sources: list,
                    selectedId: selected?.manifest.id,
                    onSelected: (id) => unawaited(
                      ref.read(searchProvider.notifier).selectSource(id),
                    ),
                  ),
                  SizedBox(height: spacing.x2),
                  if (hasLive) ...[
                    _ModeBar(rooms: rooms, filter: search.roomFilter),
                    SizedBox(height: spacing.x2),
                  ],
                ],
              ],
            ),
          ),
          Expanded(
            child: switch (sources) {
              // 首次啟動引導（ADR 0030 §決定 12）：沒有音源，或正在裝、還有失敗要看。
              AsyncData()
                  when showOnboarding(
                    hasSource: list.isNotEmpty,
                    state: onboarding,
                  ) =>
                PluginOnboarding(hasSource: list.isNotEmpty),
              AsyncData() when list.isEmpty => _noSources(),
              AsyncData() => _Results(
                state: search,
                rooms: rooms,
                network: network,
                onRetry: _retry,
              ),
              // 插件清單載入失敗時已經 log.report；畫面上等同沒有音源。
              AsyncError() => _noSources(),
              AsyncLoading() => _Loading(label: t.loadingSources),
            },
          ),
        ],
      ),
    );
  }

  /// 沒有音源又不顯示引導（按了「稍後再說」，或插件清單載入失敗）。
  Widget _noSources() {
    final t = ref.watch(translationsProvider);
    return EmptyState(
      icon: Icons.extension_off_outlined,
      title: t.search.noSources,
      body: t.search.noSourcesHint,
      action: FilledButton.tonal(
        onPressed: widget.onOpenPlugins,
        child: Text(t.onboarding.goToPlugins),
      ),
    );
  }

  void _retry() => _submit(ref.read(searchProvider).keyword);
}

/// 結果區：依 [SearchPhase] 顯示提示、載入中、失敗、沒有結果或列表。
class _Results extends ConsumerWidget {
  const _Results({
    required this.state,
    required this.rooms,
    required this.network,
    required this.onRetry,
  });

  final SearchState state;

  /// 直播間模式：結果是直播間（[SearchState.rooms]）。
  final bool rooms;
  final NetworkStatus network;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).search;
    final retry = FilledButton.tonal(onPressed: onRetry, child: Text(t.retry));
    return switch (state.phase) {
      SearchPhase.idle => EmptyState(icon: Icons.search, title: t.prompt),
      SearchPhase.loading => _Loading(label: t.loading),
      SearchPhase.failed when network != NetworkStatus.online => OfflineMessage(
        status: network,
        action: retry,
      ),
      SearchPhase.failed => EmptyState(
        icon: Icons.error_outline,
        title: t.failed,
        action: retry,
      ),
      SearchPhase.loaded when state.isEmpty => EmptyState(
        icon: Icons.search_off,
        title: t.noResults(keyword: state.keyword),
      ),
      SearchPhase.loaded ||
      SearchPhase.loadingMore => _ResultList(state: state, rooms: rooms),
    };
  }
}

/// 選的音源宣告 `live` 時搜尋框下的「曲目｜直播間」分段鈕（M3 的 segmented button：在同一頁
/// 切換檢視），直播間模式另有「全部｜開播中｜未開播」篩選（M3 的 filter chip，同音源 chip
/// 列的寫法；舊版 `LiveRoomFilter`）。窄的時候篩選換到下一行。
class _ModeBar extends ConsumerWidget {
  const _ModeBar({required this.rooms, required this.filter});

  final bool rooms;
  final LiveRoomStatus? filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).search;
    final spacing = AppTokens.of(context).spacing;
    final notifier = ref.read(searchProvider.notifier);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.x4),
      child: Wrap(
        spacing: spacing.x4,
        runSpacing: spacing.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<SearchMode>(
            segments: [
              ButtonSegment(
                value: SearchMode.tracks,
                icon: const Icon(Icons.music_note_outlined),
                label: Text(t.modeTracks),
              ),
              ButtonSegment(
                value: SearchMode.rooms,
                icon: const Icon(Icons.sensors),
                label: Text(t.modeRooms),
              ),
            ],
            selected: {rooms ? SearchMode.rooms : SearchMode.tracks},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                unawaited(notifier.selectMode(selection.single)),
          ),
          if (rooms)
            Wrap(
              spacing: spacing.x2,
              children: [
                for (final (value, label) in [
                  (null, t.filterAll),
                  (LiveRoomStatus.live, t.filterLive),
                  (LiveRoomStatus.offline, t.filterOffline),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: filter == value,
                    onSelected: (_) =>
                        unawaited(notifier.selectRoomFilter(value)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ResultList extends ConsumerWidget {
  const _ResultList({required this.state, required this.rooms});

  final SearchState state;
  final bool rooms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).search;
    final spacing = AppTokens.of(context).spacing;
    final count = rooms ? state.rooms.length : state.items.length;
    // 有下一頁，或已經到底（有結果才顯示「已載入全部」）。
    final footer =
        state.hasMore || state.phase == SearchPhase.loadingMore || count > 0;
    return ListView.builder(
      padding: EdgeInsets.only(bottom: spacing.x4),
      itemCount: count + (footer ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < count) {
          return rooms
              ? _RoomTile(hit: state.rooms[index])
              : _TrackTile(
                  index: index,
                  track: state.items[index].toTrackInfo(),
                  partCount: state.items[index].partCount,
                );
        }
        final notifier = ref.read(searchProvider.notifier);
        return Padding(
          padding: EdgeInsets.all(spacing.x2),
          child: Center(
            child: switch (state) {
              SearchState(phase: SearchPhase.loadingMore) => _Spinner(
                label: t.loading,
              ),
              // 自動載入失敗後留著按鈕當重試；一頁沒帶來新結果時也停止自動載入，手動載一頁。
              SearchState(hasMore: true, loadMoreFailed: true) ||
              SearchState(
                hasMore: true,
                autoLoadPaused: true,
              ) => OutlinedButton(
                onPressed: () => unawaited(notifier.loadMore()),
                child: Text(t.loadMore),
              ),
              // 最後一列出現（建出來）就載入下一頁；每一頁只會建一次這個元件。
              SearchState(hasMore: true) => _AutoLoad(
                onVisible: () => unawaited(notifier.loadMore()),
                child: _Spinner(label: t.loading),
              ),
              _ => Text(
                t.loadedAll,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            },
          ),
        );
      },
    );
  }
}

/// 影片 [track] 要加入的曲目（加入佇列、下一首播放、加入歌單…、多選的動作）：有多個分 P 時是
/// 全部分 P（還沒取過就先取），否則就是影片本身。取分 P 失敗時以統一提示顯示，回 `null`
/// （什麼都不加）。
Future<List<TrackInfo>?> _videoTracks(
  WidgetRef ref,
  TrackInfo track, {
  required int? partCount,
}) async {
  final toaster = ref.read(toasterProvider);
  final parts = ref.read(videoPartsProvider.notifier);
  final plugin = ref.read(pluginRegistryProvider).value?[track.sourceTypeId];
  final entry = ref.read(
    videoPartsProvider,
  )[VideoParts.keyOf(track.sourceTypeId, track.sourceId)];
  if (plugin == null ||
      !showsExpandButton(plugin: plugin, partCount: partCount, entry: entry)) {
    return [track];
  }
  try {
    final loaded = await parts.load(plugin, track.sourceId);
    return loaded.length > 1
        ? [for (final part in loaded) part.toTrackInfo(track)]
        : [track];
  } on AppError catch (error) {
    toaster.error(error, operation: 'Failed to load the parts', tag: 'search');
    return null;
  }
}

/// 一首搜尋結果：封面、曲名、上傳者、時長、「⋯」。點一下臨時播放；選單在
/// 右鍵與「⋯」（[SelectableTrackRow]），最後兩項是「加入歌單…」「選取」；長按進入多選。
///
/// 分 P（design §11.1）：插件宣告 `multiPart` 時，列尾多一個展開鈕（[partCount] 是
/// 提示：空是不知道，照樣顯示；1 是確定單 P，不顯示），展開時列出分 P，每個分 P 是
/// 一首曲目（[_PartTile]）。選單的「下一首播放」「加入佇列」「加入歌單…」在有多個分 P 時
/// 套用到全部（還沒取過就先取）。點影片本身照舊臨時播放：不帶 cid，插件取第一 P。
/// 選取模式裡展開鈕留著（展開後才選得到單一分 P）。
class _TrackTile extends ConsumerWidget {
  const _TrackTile({
    required this.index,
    required this.track,
    required this.partCount,
  });

  /// 第幾個結果（多選的鍵）。
  final int index;
  final TrackInfo track;

  /// 搜尋結果知道的分 P 數；空是不知道。
  final int? partCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).search;
    final uploader = track.uploader;
    final duration = track.duration;

    // 影片列：它的任何一個分 P 在播都標示（分 P 展開時分 P 列另外標示）。
    final playing = watchIsPlaying(ref, track, group: true);
    final inMix = ref.watch(inMixProvider);
    final canMix = ref.watch(canStartMixProvider(track.sourceTypeId));
    final plugin = ref.watch(
      pluginRegistryProvider.select(
        (plugins) => plugins.value?[track.sourceTypeId],
      ),
    );
    final entry = ref.watch(
      videoPartsProvider.select(
        (entries) =>
            entries[VideoParts.keyOf(track.sourceTypeId, track.sourceId)],
      ),
    );
    final expandable = showsExpandButton(
      plugin: plugin,
      partCount: partCount,
      entry: entry,
    );
    final expanded = expandable && (entry?.expanded ?? false);

    void play() =>
        unawaited(ref.read(playbackControllerProvider).playTemporary(track));

    Future<List<TrackInfo>?> tracksToAdd() =>
        _videoTracks(ref, track, partCount: partCount);

    Future<void> addWith({required bool next, required String added}) async {
      final controller = ref.read(playbackControllerProvider);
      final toaster = ref.read(toasterProvider);
      final tracks = await tracksToAdd();
      if (tracks == null) return;
      if (next ? controller.playNext(tracks) : controller.addToQueue(tracks)) {
        toaster.success(added);
      }
    }

    Future<void> addToPlaylist() async {
      final tracks = await tracksToAdd();
      if (tracks == null || !context.mounted) return;
      await showAddToPlaylist(context, tracks);
    }

    // 同「加入歌單…」：影片列是它的全部分 P。
    Future<void> addToRemote() async {
      final tracks = await tracksToAdd();
      if (tracks == null || !context.mounted) return;
      await showAddToRemote(context, tracks);
    }

    Future<void> toggleParts() async {
      final toaster = ref.read(toasterProvider);
      final error = await ref
          .read(videoPartsProvider.notifier)
          .toggle(plugin!, track.sourceId);
      if (error != null) {
        toaster.error(
          error,
          operation: 'Failed to load the parts',
          tag: 'search',
        );
      }
    }

    final tile = SelectableTrackRow<_ResultKey>(
      selectionKey: (item: index, part: null),
      moreTooltip: t.more,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.play_arrow),
          onPressed: play,
          child: Text(t.play),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.queue_play_next),
          onPressed: inMix
              ? null
              : () => unawaited(addWith(next: true, added: t.addedToNext)),
          child: Text(inMix ? t.playNextInMix : t.playNext),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.add_to_queue),
          onPressed: inMix
              ? null
              : () => unawaited(addWith(next: false, added: t.addedToQueue)),
          child: Text(inMix ? t.addToQueueInMix : t.addToQueue),
        ),
        if (canMix)
          MenuItemButton(
            leadingIcon: const Icon(Icons.auto_awesome),
            onPressed: () => unawaited(startMixFrom(ref, track)),
            child: Text(t.startMix),
          ),
        AddToPlaylistItem(onPressed: () => unawaited(addToPlaylist())),
        AddToRemoteItem(
          pluginIds: {track.sourceTypeId},
          onPressed: () => unawaited(addToRemote()),
        ),
      ],
      builder: (context, row) => ListTile(
        selected: row.selected,
        leading: TrackCover(track: track, playing: playing),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: playingTitleStyle(context, playing: playing),
        ),
        subtitle: uploader == null
            ? null
            : Text(uploader, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TrackDuration(duration: duration),
            if (expandable)
              entry?.phase == PartsPhase.loading
                  ? _PartsSpinner(label: t.loadingParts)
                  : IconButton(
                      tooltip: expanded ? t.hideParts : t.showParts,
                      icon: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      onPressed: () => unawaited(toggleParts()),
                    ),
            row.trailing,
          ],
        ),
        onTap: row.onTap ?? play,
        onLongPress: row.onLongPress,
      ),
    );
    if (!expanded || entry == null) return tile;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        if (entry.phase == PartsPhase.failed)
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(t.partsFailed),
            trailing: TextButton(
              onPressed: () => unawaited(toggleParts()),
              child: Text(t.retry),
            ),
          ),
        for (final (part, info) in entry.parts.indexed)
          _PartTile(
            selectionKey: (item: index, part: part),
            track: info.toTrackInfo(track),
            canMix: canMix,
            inMix: inMix,
          ),
      ],
    );
  }
}

/// 載入分 P 時取代展開鈕的轉圈（和鈕同大，列不會跳動）。
class _PartsSpinner extends StatelessWidget {
  const _PartsSpinner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: kMinInteractiveDimension,
    child: Center(
      child: SizedBox.square(
        dimension: AppLayout.partsSpinner,
        child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: label),
      ),
    ),
  );
}

/// 展開後的一個分 P（一首曲目）：「P2 分 P 標題」、時長、「⋯」。縮排在影片列之下；
/// 點一下臨時播放，選單照曲目列。
class _PartTile extends ConsumerWidget {
  const _PartTile({
    required this.selectionKey,
    required this.track,
    required this.canMix,
    required this.inMix,
  });

  final _ResultKey selectionKey;
  final TrackInfo track;
  final bool canMix;
  final bool inMix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).search;
    final spacing = AppTokens.of(context).spacing;
    final duration = track.duration;
    final playing = watchIsPlaying(ref, track);

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

    return SelectableTrackRow<_ResultKey>(
      selectionKey: selectionKey,
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
      builder: (context, row) => ListTile(
        selected: row.selected,
        contentPadding: EdgeInsetsDirectional.only(
          start: AppLayout.artworkThumbnail + spacing.x4,
          end: spacing.x4,
        ),
        dense: true,
        title: Text(
          track.partLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: playingTitleStyle(context, playing: playing),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TrackDuration(duration: duration),
            row.trailing,
          ],
        ),
        onTap: row.onTap ?? play,
        onLongPress: row.onLongPress,
      ),
    );
  }
}

/// 一個直播間結果：封面、標題、狀態與主播、人數、「⋯」（收聽、加為電台）。點一下收聽
/// （`playLive`）；選單照曲目列的 [TrackRowMenu]。
class _RoomTile extends ConsumerWidget {
  const _RoomTile({required this.hit});

  final LiveRoomHit hit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    final t = translations.search;
    final room = hit.room;
    final host = room.hostName;
    final online = room.online;
    final artwork = [
      for (final image in room.artwork)
        TrackArtwork(url: image.url, width: image.width),
    ];

    void listen() => unawaited(
      ref
          .read(playbackControllerProvider)
          .playLive(
            LiveTarget(
              pluginId: hit.pluginId,
              roomId: room.roomId,
              title: room.title,
              hostName: host,
              artwork: artwork,
            ),
          ),
    );

    Future<void> addToRadio() async {
      final radio = ref.read(translationsProvider).radio;
      final toaster = ref.read(toasterProvider);
      try {
        switch (await ref
            .read(radioServiceProvider)
            .addRoom(hit.pluginId, room)) {
          case AddRadioResult.added:
            toaster.success(radio.added);
          case AddRadioResult.alreadyAdded:
            toaster.info(radio.alreadyAdded);
          // 以 LiveRoom 直接寫入，沒有網址要認。
          case AddRadioResult.unrecognizedUrl:
            break;
        }
      } on AppError catch (error) {
        toaster.error(
          error,
          operation: 'Failed to add a radio station',
          tag: 'radio',
          sentence: (reason) => radio.addFailed(reason: reason),
        );
      }
    }

    return TrackRowMenu(
      moreTooltip: t.more,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.play_arrow),
          onPressed: listen,
          child: Text(t.listen),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.radio),
          onPressed: () => unawaited(addToRadio()),
          child: Text(t.addToRadio),
        ),
      ],
      builder: (context, more, openMenu) => ListTile(
        leading: ArtworkImage(
          pluginId: hit.pluginId,
          artwork: artwork,
          size: AppLayout.artworkThumbnail,
        ),
        title: Text(room.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: TaggedLine(
          tag: RadioStatusTag(
            status: switch (room.status) {
              LiveRoomStatus.live => RadioStatus.live,
              LiveRoomStatus.offline => RadioStatus.offline,
            },
          ),
          text: host,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 未開播的直播間沒有人數，各插件給的值不一致（0、舊值），宿主統一不顯示。
            if (online != null && room.status == LiveRoomStatus.live)
              Text(
                translations.player.liveOnline(
                  count: formatCount(ref.watch(uiLocaleProvider), online),
                ),
              ),
            more,
          ],
        ),
        onTap: listen,
        onLongPress: openMenu,
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(child: _Spinner(label: label));
}

/// 帶語意標籤的轉圈：螢幕閱讀器念得出在等什麼。
class _Spinner extends StatelessWidget {
  const _Spinner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) =>
      CircularProgressIndicator(semanticsLabel: label);
}

/// 列表最後一列出現時呼叫 [onVisible] 一次（建出來才算出現：`ListView.builder` 只建看得到
/// 與接近看得到的列）。
class _AutoLoad extends StatefulWidget {
  const _AutoLoad({required this.onVisible, required this.child});

  final VoidCallback onVisible;
  final Widget child;

  @override
  State<_AutoLoad> createState() => _AutoLoadState();
}

class _AutoLoadState extends State<_AutoLoad> {
  @override
  void initState() {
    super.initState();
    // 不在 build 裡改 provider 的狀態：排到這一幀之後。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisible();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
