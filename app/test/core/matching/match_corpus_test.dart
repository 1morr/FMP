import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/matching/matching.dart';

import 'match_corpus.dart';

/// 權重、門檻與詞表的校準語料（M4 design §8.1）。改了 `lib/core/matching/` 的
/// 常數或詞表，這裡要全綠；語料的寫法與已知的限制見 `match_corpus.dart`。
void main() {
  group('pairs', () {
    for (final pair in corpusPairs) {
      test('${pair.matches ? 'selects' : 'rejects'}: ${pair.note}', () {
        final result = score(pair.query, pair.candidate);
        expect(result.autoSelectable, pair.matches, reason: '$result');
      });
    }
  });

  group('rankings', () {
    for (final ranking in corpusRankings) {
      test(ranking.note, () {
        final ranked = rank(ranking.query, [
          for (final (index, candidate) in ranking.candidates.indexed)
            (index, candidate),
        ], limit: ranking.candidates.length);
        expect(
          ranked.first.item,
          ranking.expectedFirst,
          reason: [for (final entry in ranked) '${entry.item}: ${entry.score}']
              .join('\n'),
        );
      });
    }
  });

  group('known false matches', () {
    for (final pair in corpusKnownFalseMatches) {
      test('still selected: ${pair.note}', () {
        // 這裡紅了是好事：改進了評分，把這一對移到 corpusPairs 的「不該選」。
        expect(score(pair.query, pair.candidate).autoSelectable, isTrue);
      });
    }
  });

  group('known misses', () {
    for (final pair in corpusKnownMisses) {
      test('not auto-selected: ${pair.note}', () {
        // 接受的取捨（見 corpusKnownMisses）：由綠轉紅可以重新檢視。
        final result = score(pair.query, pair.candidate);
        expect(result.artistConflict, isTrue);
        expect(result.autoSelectable, isFalse);
      });
    }
  });
}
