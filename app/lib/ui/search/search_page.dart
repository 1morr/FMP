import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/live_play.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/radio/radio_service.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/format/count_text.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/plugins/plugin_onboarding.dart';
import 'package:fmp/ui/radio/radio_status_tag.dart';
import 'package:fmp/ui/search/search_state.dart';
import 'package:fmp/ui/search/source_chips.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/track_row_menu.dart';

/// 搜尋頁：輸入框、音源 chip 列、結果列表。點一首是臨時播放（D1）：不動佇列，
/// 播完回到佇列。每首的選單（右鍵、長按、尾端「⋯」）有播放、下一首播放、加入
/// 佇列（design §7.3）。
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
  late final _text = TextEditingController(
    text: ref.read(searchProvider).keyword,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

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
    return Column(
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
        if (list.isNotEmpty) ...[
          SourceChips(
            sources: list,
            selectedId: selected?.manifest.id,
            onSelected: (id) =>
                unawaited(ref.read(searchProvider.notifier).selectSource(id)),
          ),
          SizedBox(height: spacing.x2),
          if (hasLive) ...[
            _ModeBar(rooms: rooms, filter: search.roomFilter),
            SizedBox(height: spacing.x2),
          ],
        ],
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
    final footer = state.hasMore || state.phase == SearchPhase.loadingMore;
    return ListView.builder(
      padding: EdgeInsets.only(bottom: spacing.x4),
      itemCount: count + (footer ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < count) {
          return rooms
              ? _RoomTile(hit: state.rooms[index])
              : _TrackTile(track: state.items[index].toTrackInfo());
        }
        return Padding(
          padding: EdgeInsets.all(spacing.x2),
          child: Center(
            child: state.phase == SearchPhase.loadingMore
                ? _Spinner(label: t.loading)
                : OutlinedButton(
                    onPressed: () =>
                        unawaited(ref.read(searchProvider.notifier).loadMore()),
                    child: Text(t.loadMore),
                  ),
          ),
        );
      },
    );
  }
}

/// 一首搜尋結果：封面、曲名、上傳者、時長、「⋯」。點一下臨時播放；選單在
/// 右鍵、長按與「⋯」，三處同一份（[TrackRowMenu]）。
class _TrackTile extends ConsumerWidget {
  const _TrackTile({required this.track});

  final TrackInfo track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).search;
    final uploader = track.uploader;
    final duration = track.duration;

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
          onPressed: playNext,
          child: Text(t.playNext),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.add_to_queue),
          onPressed: addToQueue,
          child: Text(t.addToQueue),
        ),
      ],
      builder: (context, more, openMenu) => ListTile(
        leading: ArtworkImage(
          pluginId: track.sourceTypeId,
          artwork: track.artwork,
          size: AppLayout.artworkThumbnail,
        ),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: uploader == null
            ? null
            : Text(uploader, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (duration != null) Text(formatDuration(duration)),
            more,
          ],
        ),
        onTap: play,
        onLongPress: openMenu,
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
            if (online != null)
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
