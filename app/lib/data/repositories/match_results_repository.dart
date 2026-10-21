import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/track_info.dart';

/// 一首外部歌曲的匹配結果（`match_results` 的一列，ADR 0033 §決定 1、M4 design §8.4）。
///
/// [selected] 是選定的曲目；`null` 是匹配失敗（[userSelected] 為假）或使用者排除（為真）。
/// [artists] 是插件給的原字串（`TrackSummary.uploader`）。
@immutable
final class MatchResult {
  const MatchResult({
    required this.originPluginId,
    required this.originId,
    required this.title,
    this.artists,
    this.duration,
    this.selected,
    this.score,
    this.userSelected = false,
  });

  /// 外部歌曲所屬的插件（匯入的來源）。
  final String originPluginId;

  /// 外部歌曲在來源裡的 id。
  final String originId;
  final String title;
  final String? artists;
  final Duration? duration;
  final TrackInfo? selected;

  /// 選定那一首的總分（0–1）；沒有選定、或使用者選的不是自動評分過的，可以是 `null`。
  final double? score;

  /// 使用者自己改選或排除過。
  final bool userSelected;

  @override
  bool operator ==(Object other) =>
      other is MatchResult &&
      other.originPluginId == originPluginId &&
      other.originId == originId &&
      other.title == title &&
      other.artists == artists &&
      other.duration == duration &&
      other.selected == selected &&
      other.score == score &&
      other.userSelected == userSelected;

  @override
  int get hashCode => Object.hash(
    originPluginId,
    originId,
    title,
    artists,
    duration,
    selected,
    score,
    userSelected,
  );

  @override
  String toString() =>
      'MatchResult($originPluginId/$originId, selected: ${selected?.key}, '
      'score: $score, userSelected: $userSelected)';
}

/// `match_results` 的讀取。寫入只在外部匯入確認時，跟著建歌單同一個 transaction
/// （`PlaylistRepository.createFromMatches`）。沒有外鍵到 `installed_plugins`。
final class MatchResultsRepository {
  MatchResultsRepository(this._database);

  final AppDatabase _database;

  /// [originIds]（同一個來源插件 [originPluginId]）已有的匹配結果，鍵是外部 id；沒有的不在
  /// 結果裡。選定的曲目以 `tracks` 的資料讀回（`RESTRICT`，所以一定還在）。
  Future<Map<String, MatchResult>> find(
    String originPluginId,
    Iterable<String> originIds,
  ) async {
    final ids = originIds.toSet().toList();
    final results = _database.matchResultsTable;
    final tracks = _database.tracksTable;
    final found = <String, MatchResult>{};
    for (var i = 0; i < ids.length; i += _chunk) {
      final chunk = ids.skip(i).take(_chunk).toList();
      final query =
          _database.select(results).join([
            leftOuterJoin(
              tracks,
              tracks.trackKey.equalsExp(results.selectedTrackKey),
            ),
          ])..where(
            results.originPluginId.equals(originPluginId) &
                results.originId.isIn(chunk),
          );
      for (final row in await query.get()) {
        final result = row.readTable(results);
        found[result.originId] = MatchResult(
          originPluginId: result.originPluginId,
          originId: result.originId,
          title: result.title,
          artists: result.artists,
          duration: switch (result.durationMs) {
            final ms? => Duration(milliseconds: ms),
            null => null,
          },
          selected: switch (row.readTableOrNull(tracks)) {
            final track? => TracksRepository.toTrackInfo(track),
            null => null,
          },
          score: result.score,
          userSelected: result.userSelected,
        );
      }
    }
    return found;
  }

  /// 一次查的 id 數上限，在 SQLite 的變數上限以下。
  static const _chunk = 500;
}
