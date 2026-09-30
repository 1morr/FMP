import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/player/queue_tracks.dart';
import 'package:fmp/ui/search/search_state.dart';
import 'package:fmp/ui/search/source_chips.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 搜尋頁：輸入框、音源 chip 列、結果列表。點一首就把整份結果交給播放，
/// 從那一首開始依序播。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, required this.fieldFocusNode});

  /// 輸入框的焦點；外殼的 Ctrl+F 以它把焦點移到輸入框。
  final FocusNode fieldFocusNode;

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
            AsyncData() when list.isEmpty => _Message(
              icon: Icons.extension_off_outlined,
              title: t.noSources,
              body: t.noSourcesHint,
            ),
            AsyncData() => _Results(state: search, onRetry: _retry),
            // 插件清單載入失敗時已經 log.report；畫面上等同沒有音源。
            AsyncError() => _Message(
              icon: Icons.extension_off_outlined,
              title: t.noSources,
              body: t.noSourcesHint,
            ),
            AsyncLoading() => _Loading(label: t.loadingSources),
          },
        ),
      ],
    );
  }

  void _retry() => _submit(ref.read(searchProvider).keyword);
}

/// 結果區：依 [SearchPhase] 顯示提示、載入中、失敗、沒有結果或列表。
class _Results extends ConsumerWidget {
  const _Results({required this.state, required this.onRetry});

  final SearchState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).search;
    return switch (state.phase) {
      SearchPhase.idle => _Message(icon: Icons.search, title: t.prompt),
      SearchPhase.loading => _Loading(label: t.loading),
      SearchPhase.failed => _Message(
        icon: Icons.error_outline,
        title: t.failed,
        action: FilledButton.tonal(onPressed: onRetry, child: Text(t.retry)),
      ),
      SearchPhase.loaded when state.items.isEmpty => _Message(
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
          return _TrackTile(
            track: items[index],
            onTap: () => unawaited(playTracks(ref, items, index)),
          );
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

/// 一首搜尋結果：封面、曲名、上傳者、時長。
class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track, required this.onTap});

  final TrackSummary track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final uploader = track.uploader;
    final duration = track.duration;
    return ListTile(
      leading: ArtworkImage(
        artwork: track.artwork,
        size: AppLayout.artworkThumbnail,
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: uploader == null
          ? null
          : Text(uploader, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: duration == null ? null : Text(formatDuration(duration)),
      onTap: onTap,
    );
  }
}

/// 置中的圖示與說明：空狀態與失敗。
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final body = this.body;
    final action = this.action;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(spacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: AppLayout.emptyStateIcon,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: spacing.x4),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              SizedBox(height: spacing.x2),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[SizedBox(height: spacing.x4), action],
          ],
        ),
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
