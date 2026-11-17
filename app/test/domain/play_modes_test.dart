import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';

/// 播放模式的規則（brief〈播放〉的隨機與循環）。每個 group 對到 brief 的
/// 一點，group 名稱引那一點的原文開頭。
void main() {
  Track track(String id) => Track(
    ref: TrackRef(pluginId: 'p', trackId: id),
    title: id,
    author: 'a',
  );

  List<String> ids(Queue queue) => [
    for (final entry in queue.entries) entry.track.ref.trackId,
  ];
  String? current(Queue queue) => queue.current?.track.ref.trackId;

  Queue queueOf(List<String> trackIds, {int current = 0}) =>
      Queue.empty.add([for (final id in trackIds) track(id)]).jumpTo(current);

  final letters = [for (var c = 0; c < 20; c++) String.fromCharCode(97 + c)];

  group('開隨機時，正在播的那首移到最上方，其餘的歌打亂排在後面', () {
    test('the current track moves to the top and every other track, played '
        'or not, is shuffled after it', () {
      final queue = queueOf(letters, current: 5).shuffle(Random(1));
      expect(queue.shuffled, isTrue);
      expect(queue.currentIndex, 0);
      expect(current(queue), 'f');
      expect(ids(queue).toSet(), letters.toSet());
      expect(ids(queue), hasLength(letters.length));
      final rest = ids(queue).skip(1).toList();
      expect(rest, isNot(letters.where((id) => id != 'f').toList()));
    });
  });

  group('關閉隨機時，佇列恢復原順序，從正在播的那首在原順序裡的位置繼續', () {
    test('turning shuffle off restores the original order and keeps the '
        'current track at its original position', () {
      final shuffled = queueOf(letters, current: 5).shuffle(Random(1));
      final played = shuffled.next()!.next()!;
      final playing = current(played)!;
      final queue = played.unshuffle();
      expect(queue.shuffled, isFalse);
      expect(ids(queue), letters);
      expect(current(queue), playing);
      expect(queue.currentIndex, letters.indexOf(playing));
    });

    test('turning shuffle on and off without playing changes nothing', () {
      final queue = queueOf(letters, current: 5);
      final back = queue.shuffle(Random(1)).unshuffle();
      expect(ids(back), letters);
      expect(back.currentIndex, 5);
    });
  });

  group('隨機時，「下一首播放」加入的歌一定是下一首', () {
    test('play next while shuffled puts the tracks right after the current '
        'track and keeps shuffle on', () {
      final queue = queueOf(
        letters,
        current: 5,
      ).shuffle(Random(1)).playNext([track('x'), track('y')]);
      expect(queue.shuffled, isTrue);
      expect(ids(queue).take(3), ['f', 'x', 'y']);
      expect(current(queue.next()!), 'x');
    });
  });

  group('隨機時，拖動排序直接改播放順序', () {
    test('dragging while shuffled changes the play order right away and keeps '
        'shuffle on', () {
      final shuffled = queueOf(letters, current: 5).shuffle(Random(1));
      final last = ids(shuffled).last;
      final queue = shuffled.move(letters.length - 1, 1);
      expect(queue.shuffled, isTrue);
      expect(ids(queue)[1], last);
      expect(current(queue.next()!), last);
    });
  });

  group('隨機時拖動過、或用「下一首播放」插進來的曲目，關掉隨機後排在正在播的'
      '那首後面，不回原位', () {
    test('還沒播的那一半：tracks inserted with play next while shuffled land '
        'right after the current track when shuffle is turned off', () {
      final queue = queueOf([
        'a',
        'b',
        'c',
        'd',
      ], current: 1).shuffle(Random(1)).playNext([track('x')]).unshuffle();
      expect(ids(queue), ['a', 'b', 'x', 'c', 'd']);
      expect(current(queue), 'b');
    });

    test('還沒播的那一半：tracks dragged while shuffled leave their original '
        'place and land right after the current track when shuffle is turned '
        'off', () {
      final shuffled = queueOf([
        'a',
        'b',
        'c',
        'd',
        'e',
      ], current: 1).shuffle(Random(1));
      final dIndex = ids(shuffled).indexOf('d');
      final queue = shuffled.move(dIndex, 1).unshuffle();
      expect(ids(queue), ['a', 'b', 'd', 'c', 'e']);
      expect(current(queue), 'b');
    });

    test('已經播過的那一半（對 brief 的解讀）：a track dragged above the '
        'current track while shuffled lands right before it when shuffle is '
        'turned off, still played and not back in its place', () {
      final shuffled = queueOf([
        'a',
        'b',
        'c',
        'd',
        'e',
      ], current: 1).shuffle(Random(1));
      final eIndex = ids(shuffled).indexOf('e');
      final queue = shuffled.move(eIndex, 0).unshuffle();
      expect(ids(queue), ['a', 'e', 'b', 'c', 'd']);
      expect(current(queue), 'b');
    });

    test('已經播過的那一半（對 brief 的解讀）：a track inserted with play next '
        'and already played while shuffled lands right before the current '
        'track and is not played again', () {
      var queue = queueOf([
        'a',
        'b',
        'c',
        'd',
      ], current: 0).shuffle(Random(1)).playNext([track('x')]);
      queue = queue.next()!.next()!;
      final playing = current(queue)!;
      queue = queue.unshuffle();
      expect(current(queue), playing);
      final at = queue.currentIndex!;
      expect(ids(queue)[at - 1], 'x');
      expect(ids(queue).skip(at + 1), isNot(contains('x')));
      expect(ids(queue).where((id) => id != 'x'), ['a', 'b', 'c', 'd']);
    });

    test('還沒播的那一半：several pinned tracks keep their shuffled order after '
        'the current track', () {
      final queue = queueOf(['a', 'b', 'c', 'd'], current: 0)
          .shuffle(Random(1))
          .playNext([track('x')])
          .playNext([track('y')])
          .unshuffle();
      expect(ids(queue), ['a', 'y', 'x', 'b', 'c', 'd']);
    });

    test('a pinned track that is now playing goes after the last original '
        'track played before it', () {
      final queue = queueOf(
        ['a', 'b', 'c', 'd'],
        current: 1,
      ).shuffle(Random(1)).playNext([track('x')]).next()!.unshuffle();
      expect(ids(queue), ['a', 'b', 'x', 'c', 'd']);
      expect(current(queue), 'x');
    });
  });

  group('播放模式是兩個獨立的控制：隨機與循環（不循環、列表循環、單曲循環），'
      '兩者可以同時開', () {
    test('repeat starts off and is independent of shuffle', () {
      final queue = queueOf(['a', 'b']);
      expect(queue.repeat, Repeat.off);
      final both = queue.withRepeat(Repeat.all).shuffle(Random(1));
      expect(both.repeat, Repeat.all);
      expect(both.shuffled, isTrue);
      expect(both.unshuffle().repeat, Repeat.all);
      expect(both.withRepeat(Repeat.one).shuffled, isTrue);
    });

    test('shuffle and repeat can be set on an empty queue and stay on after '
        'clearing', () {
      final queue = Queue.empty.withRepeat(Repeat.one).shuffle();
      expect(queue.shuffled, isTrue);
      final refilled = queue.add([track('a')]).clear();
      expect(refilled.shuffled, isTrue);
      expect(refilled.repeat, Repeat.one);
    });

    test('without repeat, there is no next after the last track', () {
      final queue = queueOf(['a', 'b'], current: 1);
      expect(queue.hasNext, isFalse);
      expect(queue.next(), isNull);
    });

    test('list repeat goes from the last track back to the first, and from '
        'the first back to the last', () {
      final last = queueOf(['a', 'b', 'c'], current: 2).withRepeat(Repeat.all);
      expect(last.hasNext, isTrue);
      expect(current(last.next()!), 'a');
      final first = last.jumpTo(0);
      expect(first.hasPrevious, isTrue);
      expect(current(first.previous()!), 'c');
    });

    test('single repeat does not wrap a manual next or previous', () {
      final queue = queueOf(['a', 'b'], current: 1).withRepeat(Repeat.one);
      expect(queue.next(), isNull);
      expect(current(queue.previous()!), 'a');
      expect(queue.jumpTo(0).previous(), isNull);
    });
  });

  group('隨機加列表循環時，整串播完後重新打亂再播一輪；只開隨機時，播完就停', () {
    test('shuffle with list repeat reshuffles everything for a new round '
        'after the last track', () {
      var queue = queueOf(letters).withRepeat(Repeat.all).shuffle(Random(1));
      final firstRound = ids(queue);
      queue = queue.jumpTo(letters.length - 1);
      final finished = current(queue);
      final round = queue.next(Random(2))!;
      expect(round.shuffled, isTrue);
      expect(round.currentIndex, 0);
      expect(ids(round).toSet(), letters.toSet());
      expect(ids(round), isNot(firstRound));
      expect(current(round), isNot(finished));
    });

    test('a new round never starts with the track that just finished', () {
      for (var seed = 0; seed < 50; seed++) {
        final queue = queueOf(['a', 'b'])
            .withRepeat(Repeat.all)
            .shuffle(Random(seed));
        final last = queue.jumpTo(1);
        expect(
          current(last.next(Random(seed))!),
          isNot(current(last)),
          reason: 'seed $seed',
        );
      }
    });

    test('shuffle without repeat stops after the last track', () {
      final queue = queueOf(letters)
          .shuffle(Random(1))
          .jumpTo(letters.length - 1);
      expect(queue.hasNext, isFalse);
      expect(queue.next(Random(2)), isNull);
    });

    test('a reshuffled round still turns back into the original order', () {
      final round = queueOf(
        ['a', 'b', 'c', 'd'],
        current: 0,
      ).withRepeat(Repeat.all).shuffle(Random(1)).jumpTo(3).next(Random(2))!;
      final queue = round.unshuffle();
      expect(ids(queue), ['a', 'b', 'c', 'd']);
      expect(current(queue), current(round));
    });
  });

  group('用 × 移除正在播的那首時，直接接著播下一首', () {
    test('with list repeat, removing the current last track makes the first '
        'track current', () {
      final queue = queueOf([
        'a',
        'b',
        'c',
      ], current: 2).withRepeat(Repeat.all).remove(2);
      expect(ids(queue), ['a', 'b']);
      expect(current(queue), 'a');
    });

    test('with shuffle and list repeat, removing the current last track '
        'starts a reshuffled round', () {
      final shuffled = queueOf(letters)
          .withRepeat(Repeat.all)
          .shuffle(Random(1));
      final last = shuffled.jumpTo(letters.length - 1);
      final queue = last.remove(letters.length - 1, Random(2));
      expect(queue.currentIndex, 0);
      expect(ids(queue), hasLength(letters.length - 1));
      expect(ids(queue), isNot(ids(shuffled).take(letters.length - 1)));
    });

    test('while shuffled, a removed track does not come back when shuffle is '
        'turned off', () {
      final shuffled = queueOf([
        'a',
        'b',
        'c',
        'd',
      ], current: 0).shuffle(Random(1)).playNext([track('x')]);
      final withoutC = shuffled.remove(ids(shuffled).indexOf('c'));
      final queue = withoutC.remove(ids(withoutC).indexOf('x')).unshuffle();
      expect(ids(queue), ['a', 'b', 'd']);
    });
  });
}
