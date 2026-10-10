import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/plugins/plugin_onboarding.dart';
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
              hintText: t.hint,
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
    required this.network,
    required this.onRetry,
  });

  final SearchState state;
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
      SearchPhase.loaded when state.items.isEmpty => EmptyState(
        icon: Icons.search_off,
        title: t.noResults(keyword: state.keyword),
      ),
      SearchPhase.loaded ||
      SearchPhase.loadingMore => _ResultList(state: state),
    };
  }
}

class _ResultList extends ConsumerWidget {
  const _ResultList({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).search;
    final spacing = AppTokens.of(context).spacing;
    final items = state.items;
    final footer = state.hasMore || state.phase == SearchPhase.loadingMore;
    return ListView.builder(
      padding: EdgeInsets.only(bottom: spacing.x4),
      itemCount: items.length + (footer ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < items.length) {
          return _TrackTile(track: items[index].toTrackInfo());
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
