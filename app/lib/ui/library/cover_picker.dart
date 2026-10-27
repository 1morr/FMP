import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/empty_state/loading_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 一張可以當歌單封面的曲目封面：封面本身，與它所屬的音源（讀圖要經那個插件的媒體 client）。
typedef PickableCover = ({String pluginId, TrackArtwork artwork});

/// 歌單裡曲目的封面，依歌單順序、網址相同的只留第一個（沒有封面的曲目略過）。
///
/// 每首取最大的一張（歌單封面要放得比縮圖大）。
List<PickableCover> distinctTrackCovers(List<PlaylistEntry> entries) {
  final seen = <Uri>{};
  final covers = <PickableCover>[];
  for (final entry in entries) {
    final artwork = pickArtwork(entry.track.artwork, _wantedPixels);
    if (artwork == null || !seen.add(artwork.url)) continue;
    covers.add((pluginId: entry.track.sourceTypeId, artwork: artwork));
  }
  return covers;
}

/// 挑封面時要求的像素寬度：夠大的裡面最小的那張，都不夠就取沒標寬度或最大的（`pickArtwork`）。
const _wantedPixels = 512.0;

/// 「從歌曲封面選」（ADR 0035，R7.7，舊版 L-17 的 `CoverPickerDialog`「歌曲封面」分頁）：格狀列出
/// 歌單 [playlistId] 內不重複的曲目封面；選一張回傳它（取消回 `null`）。呼叫端把它當成
/// 一般的自訂封面網址，照原本的檢查與儲存路徑走。
Future<TrackArtwork?> showCoverPicker(BuildContext context, int playlistId) =>
    showDialog<TrackArtwork>(
      context: context,
      builder: (_) => _CoverPicker(playlistId: playlistId),
    );

class _CoverPicker extends ConsumerStatefulWidget {
  const _CoverPicker({required this.playlistId});

  final int playlistId;

  @override
  ConsumerState<_CoverPicker> createState() => _CoverPickerState();
}

class _CoverPickerState extends ConsumerState<_CoverPicker> {
  late final Future<List<PickableCover>> _covers = ref
      .read(playlistRepositoryProvider)
      .entries(widget.playlistId)
      .then(distinctTrackCovers);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).library;
    final spacing = AppTokens.of(context).spacing;
    return AlertDialog(
      title: Text(t.coverFromTracksTitle),
      content: SizedBox(
        width: AppLayout.coverPickerDialogWidth,
        height: AppLayout.coverPickerDialogHeight,
        child: FutureBuilder<List<PickableCover>>(
          future: _covers,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return EmptyState(
                icon: Icons.error_outline,
                error: true,
                title: t.coverFromTracksFailed,
              );
            }
            final covers = snapshot.data;
            if (covers == null) {
              return LoadingState(message: t.coverFromTracksLoading);
            }
            if (covers.isEmpty) {
              return EmptyState(
                icon: Icons.image_not_supported_outlined,
                title: t.coverFromTracksEmpty,
              );
            }
            return GridView.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: AppLayout.coverPickerTile,
                mainAxisSpacing: spacing.x2,
                crossAxisSpacing: spacing.x2,
              ),
              itemCount: covers.length,
              itemBuilder: (context, index) {
                final cover = covers[index];
                return Semantics(
                  button: true,
                  label: t.coverFromTracksItem(index: index + 1),
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(
                      AppTokens.of(context).radius.small,
                    ),
                    onTap: () => Navigator.of(context).pop(cover.artwork),
                    child: LayoutBuilder(
                      builder: (context, constraints) => ArtworkImage(
                        pluginId: cover.pluginId,
                        artwork: [cover.artwork],
                        size: constraints.maxWidth,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
      ],
    );
  }
}
