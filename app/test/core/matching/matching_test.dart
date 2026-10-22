import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/matching/matching.dart';

/// 評分核心（ADR 0019 §如何確認：全半形、繁簡、括號、時長門檻、多歌手；自動與
/// 手動重搜同分）。權重與門檻的校準在 `match_corpus_test.dart`。
void main() {
  Duration seconds(num value) => Duration(milliseconds: (value * 1000).round());

  group('full-width and half-width', () {
    test('full-width letters and digits equal half-width ones', () {
      final result = score(
        const MatchQuery(title: 'Love Story 2'),
        const MatchCandidate(title: 'Ｌｏｖｅ Ｓｔｏｒｙ ２'),
      );
      expect(result.title, 1);
    });

    test('full-width brackets are brackets', () {
      final result = score(
        const MatchQuery(title: '晴天'),
        const MatchCandidate(title: '晴天（Live）'),
      );
      expect(result.title, versionMismatchFactor);
    });
  });

  group('traditional and simplified', () {
    test('titles and artists compare after folding', () {
      final result = score(
        const MatchQuery(title: '後來', artist: '劉若英'),
        const MatchCandidate(title: '后来', uploader: '刘若英'),
      );
      expect(result.title, 1);
      expect(result.artist, 1);
    });
  });

  group('brackets', () {
    test('a different version in brackets discounts the title', () {
      const query = MatchQuery(title: '七里香');
      for (final title in ['七里香 (Live)', '七里香【伴奏】', '七里香 [Remix]']) {
        expect(
          score(query, MatchCandidate(title: title)).title,
          versionMismatchFactor,
          reason: title,
        );
      }
    });

    test('a version outside brackets counts the same as inside', () {
      final result = score(
        const MatchQuery(title: '七里香'),
        const MatchCandidate(title: '七里香 live'),
      );
      expect(result.title, versionMismatchFactor);
    });

    test('the same version on both sides is not discounted', () {
      final result = score(
        const MatchQuery(title: '晴天 (Live)'),
        const MatchCandidate(title: '晴天 现场版'),
      );
      expect(result.title, 1);
    });

    test('decorations are ignored, in brackets or not', () {
      const query = MatchQuery(title: '夜曲');
      for (final title in [
        '夜曲【MV】',
        '夜曲 (Official Video)',
        '夜曲【中字】【4K】',
        '夜曲 官方 高清',
      ]) {
        expect(
          score(query, MatchCandidate(title: title)).title,
          1,
          reason: title,
        );
      }
    });

    test('the title may be the bracket content', () {
      final result = score(
        const MatchQuery(title: '晴天', artist: '周杰倫'),
        const MatchCandidate(title: '周杰倫 Jay Chou【晴天 Sunny Day】Official MV'),
      );
      expect(result.title, 1);
    });

    test('『』 and 〖〗 are brackets', () {
      for (final (query, candidate) in [
        ('紅蓮華', '『紅蓮華』アニメ主題歌'),
        ('晴天', '〖晴天〗周董经典'),
      ]) {
        expect(
          score(
            MatchQuery(title: query),
            MatchCandidate(title: candidate),
          ).title,
          1,
          reason: candidate,
        );
      }
    });

    test('a version word that is part of the title is on both sides', () {
      final result = score(
        const MatchQuery(title: 'Live Forever', artist: 'Oasis'),
        const MatchCandidate(title: 'Oasis - Live Forever (Official Video)'),
      );
      expect(result.title, 1);
    });

    test('a longer title that only starts with the query is not a match', () {
      final result = score(
        const MatchQuery(title: '晴天'),
        const MatchCandidate(title: '晴天娃娃'),
      );
      expect(result.title, lessThan(0.6));
    });
  });

  group('title pieces', () {
    test('the original artist is taken out of the candidate title', () {
      final result = score(
        const MatchQuery(title: '恋', artist: '星野源'),
        const MatchCandidate(title: '星野源 恋'),
      );
      expect(result.title, 1);
    });

    test('each piece between separators is compared', () {
      // 歌手名寫法不同（Jay Chou／周杰伦），拿不掉，靠 ` - `、`|` 切開。
      final result = score(
        const MatchQuery(title: '稻香', artist: 'Jay Chou'),
        const MatchCandidate(title: '周杰伦 - 稻香 | 2008 魔杰座'),
      );
      expect(result.title, 1);
    });

    test('the original title stops at a Spotify suffix', () {
      final result = score(
        const MatchQuery(title: 'Let It Go - From "Frozen"/Soundtrack Version'),
        const MatchCandidate(title: 'Let It Go'),
      );
      expect(result.title, 1);
    });

    test('a title of only keywords or the artist name is the title', () {
      for (final (query, candidate) in [
        (
          const MatchQuery(title: 'Karaoke', artist: 'Drake'),
          const MatchCandidate(title: 'Drake - Karaoke'),
        ),
        (
          const MatchQuery(title: 'Audio', artist: 'LSD, Sia, Diplo, Labrinth'),
          const MatchCandidate(
            title: 'LSD - Audio (Official Video) ft. Sia, Diplo, Labrinth',
          ),
        ),
        (
          const MatchQuery(title: 'Black Sabbath', artist: 'Black Sabbath'),
          const MatchCandidate(
            title: 'Black Sabbath - Black Sabbath (Official Audio)',
          ),
        ),
      ]) {
        expect(score(query, candidate).title, 1, reason: candidate.title);
      }
      // 版本標記照樣找：另一個版本仍打折。
      expect(
        score(
          const MatchQuery(title: 'Karaoke', artist: 'Drake'),
          const MatchCandidate(title: 'Drake - Karaoke (Live)'),
        ).title,
        versionMismatchFactor,
      );
    });
  });

  group('duration', () {
    test('the threshold is 10 seconds for short songs', () {
      final query = MatchQuery(title: 'a', duration: seconds(180));
      expect(
        score(
          query,
          MatchCandidate(title: 'a', duration: seconds(190)),
        ).withinDuration,
        isTrue,
      );
      expect(
        score(
          query,
          MatchCandidate(title: 'a', duration: seconds(190.001)),
        ).withinDuration,
        isFalse,
      );
    });

    test('the threshold is 5% when that is wider', () {
      // 400 秒的 5% 是 20 秒。
      final query = MatchQuery(title: 'a', duration: seconds(400));
      expect(
        score(
          query,
          MatchCandidate(title: 'a', duration: seconds(380)),
        ).withinDuration,
        isTrue,
      );
      expect(
        score(
          query,
          MatchCandidate(title: 'a', duration: seconds(379.9)),
        ).withinDuration,
        isFalse,
      );
    });

    test('the score falls linearly inside the threshold', () {
      final query = MatchQuery(title: 'a', duration: seconds(180));
      expect(
        score(
          query,
          MatchCandidate(title: 'a', duration: seconds(180)),
        ).duration,
        1,
      );
      expect(
        score(
          query,
          MatchCandidate(title: 'a', duration: seconds(185)),
        ).duration,
        closeTo(0.5, 1e-9),
      );
      expect(
        score(
          query,
          MatchCandidate(title: 'a', duration: seconds(190)),
        ).duration,
        0,
      );
    });

    test(
      'outside the threshold the candidate is out, whatever else matches',
      () {
        final result = score(
          MatchQuery(title: '晴天', artist: '周杰倫', duration: seconds(269)),
          MatchCandidate(title: '晴天', uploader: '周杰伦', duration: seconds(300)),
        );
        expect(result.withinDuration, isFalse);
        expect(result.total, 0);
        expect(result.autoSelectable, isFalse);
      },
    );

    test('a missing duration on either side sets no threshold', () {
      for (final (query, candidate) in [
        (
          const MatchQuery(title: 'a'),
          MatchCandidate(title: 'a', duration: seconds(1)),
        ),
        (
          MatchQuery(title: 'a', duration: seconds(500)),
          const MatchCandidate(title: 'a'),
        ),
      ]) {
        final result = score(query, candidate);
        expect(result.withinDuration, isTrue);
        expect(result.duration, unknownDurationScore);
      }
    });
  });

  group('several artists', () {
    test('every separator splits the original artists', () {
      for (final separator in [
        ' / ',
        '/',
        '、',
        ', ',
        '，',
        ' & ',
        '; ',
        ' feat. ',
        ' ft. ',
        ' featuring ',
        ' × ',
        ' x ',
      ]) {
        final result = score(
          MatchQuery(title: 'a', artist: 'Wiz Khalifa${separator}Charlie Puth'),
          const MatchCandidate(title: 'a', uploader: 'Charlie Puth'),
        );
        expect(result.artist, 1, reason: separator);
      }
    });

    test('an artist named in the candidate title counts in full', () {
      final result = score(
        const MatchQuery(title: '晴天', artist: '周杰倫'),
        const MatchCandidate(title: '【周杰伦】晴天', uploader: '音乐搬运'),
      );
      expect(result.artist, 1);
    });

    test('in another version only the uploader counts, not the title', () {
      const query = MatchQuery(title: '晴天', artist: '周杰倫');
      // 版本標記下標題裡的歌手名是原唱。
      for (final title in ['【翻唱】周杰伦《晴天》', '【伴奏】晴天 - 周杰伦']) {
        expect(
          score(query, MatchCandidate(title: title, uploader: '翻唱小站')).artist,
          0,
          reason: title,
        );
      }
      // 上傳者是原歌手時照算；原曲帶同一個版本標記時標題照算。
      expect(
        score(
          query,
          const MatchCandidate(title: '晴天 (Live)', uploader: '周杰伦'),
        ).artist,
        1,
      );
      expect(
        score(
          const MatchQuery(title: '晴天 (Live)', artist: '周杰倫'),
          const MatchCandidate(title: '周杰伦 晴天 现场版', uploader: '演唱会合集'),
        ).artist,
        1,
      );
    });

    test('artist names match across punctuation but not inside a word', () {
      expect(
        score(
          const MatchQuery(title: 'a', artist: 'G.E.M.鄧紫棋'),
          const MatchCandidate(title: 'a', uploader: 'GEM鄧紫棋'),
        ).artist,
        1,
      );
      // 標題裡的名字有標點、空白，原曲的沒有（沒有上傳者可比）。
      for (final (artist, title) in [
        ('GEM鄧紫棋', 'G.E.M.鄧紫棋 - a'),
        ('Ed Sheeran', 'Ed Sheeran - a'),
      ]) {
        expect(
          score(
            MatchQuery(title: 'a', artist: artist),
            MatchCandidate(title: title),
          ).artist,
          1,
          reason: title,
        );
      }
      expect(
        score(
          const MatchQuery(title: 'a', artist: 'Sia'),
          const MatchCandidate(title: 'Asia', uploader: 'Asia'),
        ).artist,
        lessThan(1),
      );
    });

    test('Topic and VEVO channels are the artist', () {
      for (final uploader in ['Billie Eilish - Topic', 'BillieEilishVEVO']) {
        expect(
          score(
            const MatchQuery(title: 'a', artist: 'Billie Eilish'),
            MatchCandidate(title: 'a', uploader: uploader),
          ).artist,
          1,
          reason: uploader,
        );
      }
    });

    test('no original artist gives the neutral score', () {
      final result = score(
        const MatchQuery(title: 'a'),
        const MatchCandidate(title: 'a', uploader: 'b'),
      );
      expect(result.artist, unknownArtistScore);
    });
  });

  group('total', () {
    test('is the weighted sum of the parts', () {
      final result = score(
        const MatchQuery(title: '稻香', artist: 'Jay Chou'),
        const MatchCandidate(title: '稻香', uploader: '周杰伦'),
      );
      expect(
        result.total,
        closeTo(
          titleWeight * result.title +
              artistWeight * result.artist +
              durationWeight * result.duration,
          1e-12,
        ),
      );
      expect(titleWeight + artistWeight + durationWeight, closeTo(1, 1e-12));
    });

    test('auto-selects from the threshold up', () {
      const exactly = MatchScore(
        title: 1,
        artist: 0,
        duration: 0,
        withinDuration: true,
      );
      // 0.6 × 1 = 0.6，正好是門檻。
      expect(exactly.total, autoSelectThreshold);
      expect(exactly.autoSelectable, isTrue);
      const below = MatchScore(
        title: 0.99,
        artist: 0,
        duration: 0,
        withinDuration: true,
      );
      expect(below.autoSelectable, isFalse);
    });
  });

  group('automatic and manual searches', () {
    final query = MatchQuery(
      title: '晴天',
      artist: '周杰倫',
      duration: seconds(269),
    );
    final original = MatchCandidate(
      title: '【周杰伦】晴天 无损音质',
      uploader: '无损音乐搬运',
      duration: seconds(269),
    );

    test('give a candidate the same score whatever else was found', () {
      final alone = score(query, original).total;
      // 自動匹配：各音源合併的結果。
      final automatic = rank(query, [
        ('live', MatchCandidate(title: '晴天 (Live)', duration: seconds(275))),
        ('original', original),
        ('other', MatchCandidate(title: '稻香', duration: seconds(223))),
      ], limit: 5);
      // 手動重搜：自訂關鍵字、別的音源、不同順序。
      final manual = rank(query, [
        ('cover', MatchCandidate(title: '晴天 翻唱', duration: seconds(268))),
        ('original', original),
      ], limit: 5);
      for (final ranked in [automatic, manual]) {
        final found = ranked.singleWhere((entry) => entry.item == 'original');
        expect(found.score.total, alone);
      }
    });
  });

  group('rank', () {
    const query = MatchQuery(title: '晴天', artist: '周杰倫');

    test('orders by total, highest first, and keeps at most limit', () {
      final ranked = rank(query, [
        ('weak', const MatchCandidate(title: '晴天娃娃')),
        ('best', const MatchCandidate(title: '晴天', uploader: '周杰伦')),
        ('live', const MatchCandidate(title: '晴天 (Live)', uploader: '周杰伦')),
      ], limit: 2);
      expect([for (final entry in ranked) entry.item], ['best', 'live']);
    });

    test('keeps the input order for equal totals', () {
      const same = MatchCandidate(title: '晴天', uploader: '周杰伦');
      // 超過 32 個：List.sort 在短清單用插入排序（剛好穩定），長的才不穩定。
      final items = [
        for (var page = 1; page <= 15; page++)
          for (final source in ['bilibili', 'youtube', 'netease'])
            '$source-$page',
      ];
      expect([
        for (final entry in rank(query, [
          for (final item in items) (item, same),
        ], limit: items.length))
          entry.item,
      ], items);
      expect([
        for (final entry in rank(query, [
          for (final item in items.reversed) (item, same),
        ], limit: items.length))
          entry.item,
      ], items.reversed);
    });

    test('leaves out candidates outside the duration threshold', () {
      // limit 1：淘汰的不佔名額。
      final ranked = rank(MatchQuery(title: '晴天', duration: seconds(269)), [
        ('mv', MatchCandidate(title: '晴天', duration: seconds(320))),
        ('audio', MatchCandidate(title: '晴天', duration: seconds(269))),
      ], limit: 1);
      expect([for (final entry in ranked) entry.item], ['audio']);
    });
  });

  // 外部匯入的搜尋關鍵字取第一位歌手的原文（M4 design §8.4）。
  group('first artist', () {
    test('takes the first of several, as written', () {
      expect(firstArtist('Jay Chou / Lara Liang'), 'Jay Chou');
      expect(firstArtist('周杰倫、費玉清'), '周杰倫');
      expect(firstArtist('A FEAT. B'), 'A');
      expect(firstArtist('A，B'), 'A');
      expect(firstArtist('Solo'), 'Solo');
    });

    test('nothing to take is null', () {
      expect(firstArtist(null), isNull);
      expect(firstArtist(''), isNull);
      expect(firstArtist(' / '), isNull);
    });
  });

  group('artist conflict', () {
    const query = MatchQuery(
      title: 'Hello',
      artist: 'Adele',
      duration: Duration(minutes: 4, seconds: 55),
    );
    const sameLength = Duration(minutes: 4, seconds: 55);

    test('the same script that does not match blocks auto-select only', () {
      final result = score(
        query,
        const MatchCandidate(
          title: 'Hello',
          uploader: 'Lionel Richie',
          duration: sameLength,
        ),
      );
      expect(result.artistConflict, isTrue);
      expect(result.total, greaterThanOrEqualTo(autoSelectThreshold));
      expect(result.autoSelectable, isFalse);
      expect(result.toString(), contains('artistConflict: true'));
    });

    test('Han against Han conflicts, Kana against Han does not', () {
      const han = MatchQuery(title: '晴天', artist: '周杰倫');
      expect(
        score(
          han,
          const MatchCandidate(title: '晴天', uploader: '谭咏麟'),
        ).artistConflict,
        isTrue,
      );
      const kana = MatchQuery(title: 'マリーゴールド', artist: 'あいみょん');
      expect(
        score(
          kana,
          const MatchCandidate(title: 'マリーゴールド', uploader: '爱缪'),
        ).artistConflict,
        isFalse,
      );
    });

    test('a different script is no conflict', () {
      final result = score(
        const MatchQuery(title: '稻香', artist: 'Jay Chou'),
        const MatchCandidate(title: '稻香', uploader: '周杰伦'),
      );
      expect(result.artistConflict, isFalse);
    });

    test('no uploader is no conflict', () {
      final result = score(query, const MatchCandidate(title: 'Hello'));
      expect(result.artistConflict, isFalse);
    });

    test('a Topic uploader that is empty after stripping is no conflict', () {
      final result = score(
        query,
        const MatchCandidate(title: 'Hello', uploader: ' - Topic'),
      );
      expect(result.artistConflict, isFalse);
    });

    test('no original artist is no conflict', () {
      final result = score(
        const MatchQuery(title: 'Hello'),
        const MatchCandidate(title: 'Hello', uploader: 'Lionel Richie'),
      );
      expect(result.artistConflict, isFalse);
    });

    test('an artist score of 0.5 or more is no conflict', () {
      final result = score(
        const MatchQuery(title: 'Hello', artist: 'Adele'),
        const MatchCandidate(title: 'Hello', uploader: 'Adele Official'),
      );
      expect(result.artist, greaterThanOrEqualTo(artistConflictBelow));
      expect(result.artistConflict, isFalse);
    });

    test('rank keeps the conflicting candidate and its order', () {
      final ranked = rank(query, [
        (
          'other',
          const MatchCandidate(
            title: 'Hello',
            uploader: 'Lionel Richie',
            duration: sameLength,
          ),
        ),
      ], limit: 5);
      expect(ranked.single.item, 'other');
      expect(ranked.single.score.autoSelectable, isFalse);
    });
  });
}
