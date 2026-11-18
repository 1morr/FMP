import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';

/// 佇列的規則（brief〈播放〉，`GLOSSARY.md`〈佇列〉）：不隨機、不循環。
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

  Queue queueOf(List<String> trackIds, {int current = 0}) {
    var queue = Queue.empty.add([for (final id in trackIds) track(id)]);
    for (var i = 0; i < current; i++) {
      queue = queue.next()!;
    }
    return queue;
  }

  group('add', () {
    test('an empty queue makes the first added track current', () {
      final queue = Queue.empty.add([track('a'), track('b')]);
      expect(ids(queue), ['a', 'b']);
      expect(current(queue), 'a');
    });

    test('appends after the last track without moving current', () {
      final queue = queueOf(['a', 'b'], current: 1).add([track('c')]);
      expect(ids(queue), ['a', 'b', 'c']);
      expect(current(queue), 'b');
    });

    test('the same track can be queued twice as separate entries', () {
      final queue = Queue.empty.add([track('a')]).add([track('a')]);
      expect(ids(queue), ['a', 'a']);
      expect(queue.entries.first.id, isNot(queue.entries.last.id));
    });
  });

  group('playNext', () {
    test('inserts right after the current track, in order', () {
      final queue = queueOf(['a', 'b', 'c']).playNext([track('x'), track('y')]);
      expect(ids(queue), ['a', 'x', 'y', 'b', 'c']);
      expect(current(queue), 'a');
    });

    test('an empty queue makes the inserted track current', () {
      final queue = Queue.empty.playNext([track('x')]);
      expect(ids(queue), ['x']);
      expect(current(queue), 'x');
    });
  });

  group('next and previous', () {
    test('next moves to the following track', () {
      expect(current(queueOf(['a', 'b']).next()!), 'b');
    });

    test('there is no next after the last track', () {
      final queue = queueOf(['a', 'b'], current: 1);
      expect(queue.hasNext, isFalse);
      expect(queue.next(), isNull);
    });

    test('previous moves to the track before', () {
      expect(current(queueOf(['a', 'b'], current: 1).previous()!), 'a');
    });

    test('there is no previous before the first track', () {
      final queue = queueOf(['a', 'b']);
      expect(queue.hasPrevious, isFalse);
      expect(queue.previous(), isNull);
    });

    test('an empty queue has neither', () {
      expect(Queue.empty.current, isNull);
      expect(Queue.empty.hasNext, isFalse);
      expect(Queue.empty.hasPrevious, isFalse);
    });
  });

  group('upcoming (the track next will play, for preloading)', () {
    String? upcoming(Queue queue) => queue.upcoming?.track.ref.trackId;

    test('is the following track', () {
      expect(upcoming(queueOf(['a', 'b', 'c'])), 'b');
    });

    test('is nothing after the last track', () {
      expect(upcoming(queueOf(['a', 'b'], current: 1)), isNull);
    });

    test('wraps to the first track with list repeat', () {
      final queue = queueOf(['a', 'b'], current: 1).withRepeat(Repeat.all);
      expect(upcoming(queue), 'a');
    });

    test('is unknown at the end of a shuffled list repeat: the next round is '
        'shuffled again', () {
      var queue = queueOf(['a', 'b', 'c']).withRepeat(Repeat.all);
      queue = queue.shuffle(Random(1));
      queue = queue.jumpTo(queue.entries.length - 1);
      expect(queue.upcoming, isNull);
    });

    test('is nothing in an empty queue', () {
      expect(Queue.empty.upcoming, isNull);
    });
  });

  test('jumpTo makes any entry current', () {
    expect(current(queueOf(['a', 'b', 'c']).jumpTo(2)), 'c');
  });

  group('move', () {
    test('moving a later track up keeps the same current track', () {
      final queue = queueOf(['a', 'b', 'c', 'd'], current: 1).move(3, 0);
      expect(ids(queue), ['d', 'a', 'b', 'c']);
      expect(current(queue), 'b');
    });

    test('moving the current track carries current with it', () {
      final queue = queueOf(['a', 'b', 'c'], current: 0).move(0, 2);
      expect(ids(queue), ['b', 'c', 'a']);
      expect(current(queue), 'a');
      expect(queue.hasNext, isFalse);
    });

    test('dragging a track above current makes it played', () {
      final queue = queueOf(['a', 'b', 'c'], current: 1).move(2, 0);
      expect(ids(queue), ['c', 'a', 'b']);
      expect(queue.currentIndex, 2);
      expect(queue.hasNext, isFalse);
    });
  });

  group('moveToNext', () {
    test('a later track lands right after current', () {
      final queue = queueOf(['a', 'b', 'c', 'd'], current: 1).moveToNext(3);
      expect(ids(queue), ['a', 'b', 'd', 'c']);
      expect(current(queue), 'b');
    });

    test('a played track lands right after current and stays behind it', () {
      final queue = queueOf(['a', 'b', 'c', 'd'], current: 2).moveToNext(0);
      expect(ids(queue), ['b', 'c', 'a', 'd']);
      expect(current(queue), 'c');
      expect(queue.currentIndex, 1);
    });

    test('the current track and the track right after it stay put', () {
      final queue = queueOf(['a', 'b', 'c'], current: 1);
      expect(ids(queue.moveToNext(1)), ['a', 'b', 'c']);
      expect(ids(queue.moveToNext(2)), ['a', 'b', 'c']);
    });
  });

  group('remove', () {
    test('removing another track keeps current', () {
      final queue = queueOf(['a', 'b', 'c'], current: 2).remove(0);
      expect(ids(queue), ['b', 'c']);
      expect(current(queue), 'c');
    });

    test('removing the current track makes the next one current', () {
      final queue = queueOf(['a', 'b', 'c'], current: 1).remove(1);
      expect(ids(queue), ['a', 'c']);
      expect(current(queue), 'c');
    });

    test('removing the current last track leaves no current track, the '
        'rest played', () {
      final queue = queueOf(['a', 'b'], current: 1).remove(1);
      expect(ids(queue), ['a']);
      expect(queue.current, isNull);
      expect(queue.isEmpty, isFalse);
      expect(queue.hasNext, isFalse);
      expect(queue.hasPrevious, isFalse);
    });

    test('without a current track, adding appends and makes the first added '
        'track current', () {
      final queue = queueOf([
        'a',
        'b',
      ], current: 1).remove(1).add([track('c'), track('d')]);
      expect(ids(queue), ['a', 'c', 'd']);
      expect(current(queue), 'c');
    });

    test(
      'without a current track, play next goes last and becomes current',
      () {
        final queue = queueOf([
          'a',
          'b',
        ], current: 1).remove(1).playNext([track('x')]);
        expect(ids(queue), ['a', 'x']);
        expect(current(queue), 'x');
      },
    );

    test('without a current track, move to next does nothing', () {
      final queue = queueOf(['a', 'b', 'c'], current: 2).remove(2);
      expect(ids(queue.moveToNext(0)), ['a', 'b']);
    });

    test('removing the only track empties the queue', () {
      final queue = queueOf(['a']).remove(0);
      expect(queue.isEmpty, isTrue);
      expect(queue.current, isNull);
    });
  });

  test('clear empties the queue', () {
    final queue = queueOf(['a', 'b'], current: 1).clear();
    expect(queue.isEmpty, isTrue);
    expect(queue.current, isNull);
  });

  test('entries cannot be changed from outside', () {
    final queue = queueOf(['a']);
    expect(
      () => queue.entries.add(queue.entries.first),
      throwsUnsupportedError,
    );
  });

  group('restore', () {
    QueueEntry entry(int id) => QueueEntry(id, track('t$id'));

    Queue restore({
      List<int> ids = const [0, 1],
      int? current = 0,
      int next = 2,
      List<int>? originalOrder,
    }) => Queue.restore(
      entries: [for (final id in ids) entry(id)],
      currentEntryId: current,
      nextEntryId: next,
      repeat: Repeat.off,
      originalOrder: originalOrder,
    );

    test('rejects saved entries that share an id', () {
      expect(() => restore(ids: [0, 0]), throwsFormatException);
    });

    test('rejects a current entry that is not in the queue', () {
      expect(() => restore(current: 5), throwsFormatException);
    });

    test('rejects an entry id that the next added entry would reuse', () {
      expect(() => restore(next: 1), throwsFormatException);
    });

    test('rejects an original order with entries that are not in the '
        'queue or appear twice', () {
      expect(() => restore(originalOrder: [0, 7]), throwsFormatException);
      expect(() => restore(originalOrder: [0, 0]), throwsFormatException);
    });
  });
}
