import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/i18n/strings.g.dart';

/// 音樂庫的歌單卡（依 `sort_order`），本機資料，離線照常顯示。歌單或項目一變動就重讀
/// （先訂閱再讀，讀的期間的變動排在後面再讀一次）；讀失敗發出錯誤、之後的變動照樣重讀。
/// 「加入歌單…」的對話框也讀它（只列本機歌單）。
final playlistOverviewsProvider = StreamProvider<List<PlaylistOverview>>((
  ref,
) async* {
  final repository = ref.watch(playlistRepositoryProvider);
  yield* _rereadOnChange(ref, repository, repository.overviews);
});

/// 歌單的首數（英文的單複數由 slang 的複數語法處理）。
String trackCountText(Translations$library$zh_TW t, int count) =>
    t.trackCount(count: count);

/// 歌單卡的副標題：「本機／匯入 · n 首」；Mix 不存曲目，只寫「Mix」（音樂庫的卡片；首頁的卡片窄，只寫首數）。
String playlistSubtitleText(
  Translations$library$zh_TW t,
  PlaylistOverview overview,
) {
  final kind = switch (overview.playlist.kind) {
    PlaylistKind.local => t.local,
    PlaylistKind.imported => t.imported,
    PlaylistKind.mix => null,
  };
  if (kind == null) return t.mix;
  return '$kind · ${trackCountText(t, overview.trackCount)}';
}

/// 歌單詳情頁要的一張歌單：歌單本身、匯入歌單的遠端資料、全部項目。
@immutable
final class PlaylistDetail {
  const PlaylistDetail({
    required this.playlist,
    required this.entries,
    this.remote,
    this.seedTrack,
  });

  final Playlist playlist;

  /// 匯入歌單才有。
  final PlaylistRemote? remote;

  /// Mix 歌單的種子曲目；沒有 `tracks` 列（或不是 Mix 歌單）是 `null`。
  final TrackInfo? seedTrack;

  /// 依（`position`, `id`）。
  final List<PlaylistEntry> entries;
}

/// 歌單詳情（[playlistId]）；歌單已刪除是 `null`。寫法同 [playlistOverviewsProvider]：
/// 歌單、項目或遠端資料一變動就重讀（`changes()`，不用 `watch()`：join 了 `tracks`）。
/// 頁面關掉就放開。
final playlistDetailProvider = StreamProvider.autoDispose
    .family<PlaylistDetail?, int>((ref, playlistId) async* {
      final repository = ref.watch(playlistRepositoryProvider);
      yield* _rereadOnChange(ref, repository, () async {
        final playlist = await repository.find(playlistId);
        if (playlist == null) return null;
        return PlaylistDetail(
          playlist: playlist,
          remote: await repository.remote(playlistId),
          entries: await repository.entries(playlistId),
          seedTrack: await repository.mixSeedTrack(playlist),
        );
      });
    });

/// 先訂閱 [repository] 的變動、再讀一次，之後每次變動再讀（依序）；讀失敗發出錯誤、之後的
/// 變動照樣重讀。
Stream<T> _rereadOnChange<T>(
  Ref ref,
  PlaylistRepository repository,
  Future<T> Function() read,
) async* {
  final changed = StreamController<void>();
  final changes = repository.changes().listen(changed.add);
  ref.onDispose(() {
    unawaited(changes.cancel());
    unawaited(changed.close());
  });
  Stream<T> once() async* {
    try {
      yield await read();
    } on Object catch (error, stackTrace) {
      yield* Stream.error(error, stackTrace);
    }
  }

  yield* once();
  await for (final _ in changed.stream) {
    yield* once();
  }
}

/// 詳情頁清單的一列：分 P 群組的標題，或一個項目。
sealed class PlaylistRow {
  const PlaylistRow();
}

/// 同一支影片的連續分 P（兩個以上）上面的標題列（影片標題、上傳者、封面取第一個分 P 的）。
final class PlaylistGroupRow extends PlaylistRow {
  const PlaylistGroupRow(this.parts);

  final List<PlaylistEntry> parts;
}

/// 一個項目；[inGroup] 是收在群組標題下的分 P（縮排、只顯示分 P 的標籤）。
final class PlaylistEntryRow extends PlaylistRow {
  const PlaylistEntryRow(this.entry, {required this.inGroup});

  final PlaylistEntry entry;
  final bool inGroup;
}

/// 依歌單順序排出清單（M4 design §10.4）：同一支影片（`TrackKey.formatGroup`）的**連續**分 P
/// 有兩個以上時收在一個群組標題下；只有一個的分 P、不連續的分 P 與其他曲目照常一列（標題是
/// `displayTitle`，「影片標題 · P2 分 P 標題」）。不重排：群組只看相鄰。
List<PlaylistRow> groupParts(List<PlaylistEntry> entries) {
  String? groupOf(PlaylistEntry entry) => entry.track.partIndex == null
      ? null
      : TrackKey.formatGroup(entry.track.sourceTypeId, entry.track.sourceId);

  final rows = <PlaylistRow>[];
  var start = 0;
  while (start < entries.length) {
    final group = groupOf(entries[start]);
    var end = start + 1;
    if (group != null) {
      while (end < entries.length && groupOf(entries[end]) == group) {
        end++;
      }
    }
    if (end - start > 1) {
      final parts = entries.sublist(start, end);
      rows
        ..add(PlaylistGroupRow(parts))
        ..addAll([
          for (final part in parts) PlaylistEntryRow(part, inGroup: true),
        ]);
    } else {
      rows.add(PlaylistEntryRow(entries[start], inGroup: false));
    }
    start = end;
  }
  return rows;
}

/// 清單 [rows] 的第 [from] 列（一個項目）拖到 [to]（`onReorderItem` 的位置：已扣掉被拿起
/// 的那一格）之後，項目 id 的新順序。放在某個群組標題與它的第一個分 P 之間，等於放在那個
/// 分 P 之前（標題跟著重算）。
List<int> reorderedEntryIds(List<PlaylistRow> rows, int from, int to) {
  final moved = switch (rows[from]) {
    PlaylistEntryRow(:final entry) => entry.id,
    PlaylistGroupRow() => throw ArgumentError.value(from, 'from', 'a header'),
  };
  final rest = [...rows]..removeAt(from);
  final ids = [
    for (final row in rest)
      if (row case PlaylistEntryRow(:final entry)) entry.id,
  ];
  final before = rest.take(to).whereType<PlaylistEntryRow>().length;
  return ids..insert(before, moved);
}
