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

    test('removing the current last track makes the new last one current', () {
      final queue = queueOf(['a', 'b'], current: 1).remove(1);
      expect(ids(queue), ['a']);
      expect(current(queue), 'a');
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
}
