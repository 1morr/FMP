/// 匹配的評分核心（ADR 0019 §決定 5、6，M4 design §8.1）：外部匯入與 M7 的歌詞
/// 共用。純函式，輸入是自己的值型別；不看播放量等來源特有的訊號。
///
/// 權重與門檻以 `test/core/matching/match_corpus.dart` 的語料校準，改了要語料全綠。
library;

import 'dart:math' as math;

import 'package:string_similarity/string_similarity.dart';

import 'normalize.dart';

/// 標題分的權重。
const titleWeight = 0.6;

/// 歌手分的權重。
const artistWeight = 0.3;

/// 時長分的權重。
const durationWeight = 0.1;

/// 第一名的總分到這裡才自動選，否則是「匹配失敗」。
const autoSelectThreshold = 0.6;

/// 時長差距的門檻：超過 max(這個值, 原時長 × [durationToleranceRatio]) 直接淘汰。
const durationToleranceFloor = Duration(seconds: 10);

/// 見 [durationToleranceFloor]。
const durationToleranceRatio = 0.05;

/// 兩邊的版本標記（Live、伴奏、Remix……）不同時，標題分乘上它。不整首否決：
/// 只有 Live 版時仍可能選它，有原版時原版排前面。
const versionMismatchFactor = 0.8;

/// 歌手分低於它，而且兩邊的歌手名寫成同一種文字，才算歌手衝突（[MatchScore.artistConflict]）。
const artistConflictBelow = 0.5;

/// 任一邊缺時長時的時長分（不設門檻）。
const unknownDurationScore = 0.5;

/// 原曲沒有歌手時的歌手分。
const unknownArtistScore = 0.5;

/// 要找的歌：外部歌單的一首、要配歌詞的曲目。
final class MatchQuery {
  const MatchQuery({required this.title, this.artist, this.duration});

  final String title;

  /// 歌手；多位可以用 ` / `、`、`、`,`、`&`、`feat.` 等連在一起。
  final String? artist;

  final Duration? duration;
}

/// 一個搜尋結果。
final class MatchCandidate {
  const MatchCandidate({required this.title, this.uploader, this.duration});

  /// 上傳標題或歌名。
  final String title;

  /// 上傳者（B 站、YouTube 常是頻道而不是歌手）或歌手。
  final String? uploader;

  final Duration? duration;
}

/// 一個候選的分數。各分項在 0–1。
final class MatchScore {
  const MatchScore({
    required this.title,
    required this.artist,
    required this.duration,
    required this.withinDuration,
    this.artistConflict = false,
  });

  final double title;
  final double artist;
  final double duration;

  /// 時長差距在門檻內（或任一邊缺時長）。`false` 是淘汰：[total] 為 0，
  /// [rank] 不列出。
  final bool withinDuration;

  /// 總分，0–1。
  double get total => withinDuration
      ? titleWeight * title + artistWeight * artist + durationWeight * duration
      : 0;

  /// 歌手衝突：原曲有歌手、候選有上傳者、歌手分低於 [artistConflictBelow]，而且
  /// 某位原歌手與上傳者的某一段名字用同一種文字寫（Latin、漢字、假名、諺文、其他）
  /// 卻對不上，是「另一個人唱的」的證據。不同文字（譯名、羅馬字）無從判斷，不算。
  /// 不影響 [total] 與排序，只讓 [autoSelectable] 為假。
  final bool artistConflict;

  /// 第一名是它時自動選。
  bool get autoSelectable => total >= autoSelectThreshold && !artistConflict;

  @override
  String toString() =>
      'MatchScore(total: ${total.toStringAsFixed(3)}, '
      'title: ${title.toStringAsFixed(3)}, '
      'artist: ${artist.toStringAsFixed(3)}, '
      'duration: ${duration.toStringAsFixed(3)}, '
      'withinDuration: $withinDuration, '
      'artistConflict: $artistConflict)';
}

/// [rank] 的一項。
final class Ranked<T> {
  const Ranked(this.item, this.score);

  final T item;
  final MatchScore score;
}

/// [artists]（插件給的歌手原字串，多位以 ` / ` 等連接）的第一位，原文；沒有字是 `null`。
/// 外部匯入的搜尋關鍵字是「原標題 空白 第一位歌手」（M4 design §8.4）。
String? firstArtist(String? artists) => switch (artists) {
  final raw? => splitRawArtists(raw).firstOrNull,
  null => null,
};

/// 一個候選對 [query] 的分數。只看這兩個參數：同一對在自動匹配與手動重搜
/// 得到同一個分數。
MatchScore score(MatchQuery query, MatchCandidate candidate) =>
    _PreparedQuery(query).score(candidate);

/// 依總分由高到低排出前 [limit] 個；時長淘汰的不列出。同分依 [candidates] 的
/// 順序（呼叫端排好的音源順序）。
List<Ranked<T>> rank<T>(
  MatchQuery query,
  Iterable<(T, MatchCandidate)> candidates, {
  required int limit,
}) {
  final prepared = _PreparedQuery(query);
  final scored = [
    for (final (index, (item, candidate)) in candidates.indexed)
      if (prepared.score(candidate) case final score when score.withinDuration)
        (index: index, ranked: Ranked(item, score)),
  ];
  // List.sort 不保證穩定，同分以輸入的位置排。
  scored.sort((a, b) {
    final byScore = b.ranked.score.total.compareTo(a.ranked.score.total);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });
  return [for (final entry in scored.take(limit)) entry.ranked];
}

final class _PreparedQuery {
  factory _PreparedQuery(MatchQuery query) {
    final artists = [
      if (query.artist case final artist?) ...splitArtists(foldText(artist)),
    ];
    final patterns = artists.map(namePattern).nonNulls.toList();
    return _PreparedQuery._(
      query,
      artists.map(compact).toList(),
      patterns,
      parseQueryTitle(query.title, patterns),
    );
  }

  _PreparedQuery._(this.query, this.artists, this.artistPatterns, this.title);

  final MatchQuery query;

  /// 原曲的每位歌手，[compact] 過。
  final List<String> artists;

  /// 每位歌手的 [namePattern]（太短的沒有）。
  final List<RegExp> artistPatterns;

  final ({String core, Set<String> versions, TitleCleaning cleaning}) title;

  MatchScore score(MatchCandidate candidate) {
    final (:within, :value) = _durationScore(candidate.duration);
    final parsed = parseCandidateTitle(
      candidate.title,
      artistPatterns,
      title.cleaning,
    );
    final uploader = stripUploaderDecoration(
      foldText(candidate.uploader ?? ''),
    );
    final artist = _artistScore(
      candidate,
      uploader,
      otherVersion: !title.versions.containsAll(parsed.versions),
    );
    return MatchScore(
      title: _titleScore(parsed),
      artist: artist,
      duration: value,
      withinDuration: within,
      artistConflict: _artistConflict(artist, uploader),
    );
  }

  bool _artistConflict(double artistScore, String uploader) {
    if (artists.isEmpty || artistScore >= artistConflictBelow) return false;
    final uploaderScripts = {
      for (final name in splitArtists(uploader)) scriptSet(name),
    }..remove('');
    return artists.any(
      (artist) =>
          uploaderScripts.contains(scriptSet(artist)) && artist.isNotEmpty,
    );
  }

  double _titleScore(({List<String> variants, Set<String> versions}) parsed) {
    var best = 0.0;
    for (final variant in parsed.variants) {
      best = math.max(
        best,
        StringSimilarity.compareTwoStrings(title.core, variant),
      );
    }
    final sameVersion =
        parsed.versions.length == title.versions.length &&
        parsed.versions.containsAll(title.versions);
    return sameVersion ? best : best * versionMismatchFactor;
  }

  /// 原歌手出現在候選的上傳者或標題裡算 1.0；否則每位原歌手與上傳者的每一段取
  /// Dice，取最佳。
  ///
  /// [otherVersion]（候選有原曲沒有的版本標記）時標題不算：`【翻唱】周杰伦《晴天》`、
  /// `【伴奏】晴天 - 周杰伦` 裡的歌手名是原唱，不是這個上傳者。原歌手自己上傳的
  /// Live、伴奏由上傳者對上。
  double _artistScore(
    MatchCandidate candidate,
    String uploader, {
    required bool otherVersion,
  }) {
    if (artists.isEmpty) return unknownArtistScore;
    final title = otherVersion ? '' : foldText(candidate.title);
    for (final pattern in artistPatterns) {
      if (pattern.hasMatch(title) || pattern.hasMatch(uploader)) return 1;
    }
    final uploaders = splitArtists(uploader).map(compact);
    var best = 0.0;
    for (final artist in artists) {
      for (final name in uploaders) {
        best = math.max(best, StringSimilarity.compareTwoStrings(artist, name));
      }
    }
    return best;
  }

  ({bool within, double value}) _durationScore(Duration? candidate) {
    final expected = query.duration;
    if (expected == null || candidate == null) {
      return (within: true, value: unknownDurationScore);
    }
    final tolerance = math.max(
      durationToleranceFloor.inMilliseconds,
      expected.inMilliseconds * durationToleranceRatio,
    );
    final difference = (expected - candidate).inMilliseconds.abs();
    if (difference > tolerance) return (within: false, value: 0);
    return (within: true, value: 1 - difference / tolerance);
  }
}
