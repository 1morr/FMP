import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/queue_model.dart';

TrackInfo track(String id) =>
    TrackInfo(sourceTypeId: 'fmp-test', sourceId: id, title: 'Song $id');

List<TrackInfo> tracks(Iterable<String> ids) => [
  for (final id in ids) track(id),
];

List<TrackInfo> numbered(int count) => [
  for (var i = 0; i < count; i++) track('$i'),
];

/// 清單上的曲目 id。
List<String> ids(QueueState state) => [
  for (final entry in state.entries) entry.track.sourceId,
];

String? currentId(QueueState state) => state.current?.sourceId;

/// 目前這首之後、本輪還會播的曲目 id，依播放順序。
List<String> upcoming(QueueState state) {
  final order =
      state.shuffleOrder ?? [for (var i = 0; i < state.entries.length; i++) i];
  return [
    for (final position in order.skip(order.indexOf(state.currentIndex!) + 1))
      state.entries[position].track.sourceId,
  ];
}

/// 本輪已播的曲目 id（不含目前這首）。
List<String> played(QueueState state) {
  final order = state.shuffleOrder!;
  return [
    for (final position in order.take(order.indexOf(state.currentIndex!)))
      state.entries[position].track.sourceId,
  ];
}

/// 一直往下一首直到停下，回傳播到的曲目 id。
List<String> playToEnd(QueueModel queue) {
  final played = <String>[];
  while (queue.moveNext() is MovedToTrack) {
    played.add(currentId(queue.state)!);
  }
  return played;
}

QueueModel shuffled(int count, {int seed = 1, int start = 0}) =>
    QueueModel(random: Random(seed))
      ..replace(numbered(count), startIndex: start)
      ..setShuffle(true);

/// 隨機挑一個不是目前這首的位置（[length] 至少 2）。
int otherPosition(Random random, int current, int length) {
  final index = random.nextInt(length - 1);
  return index >= current ? index + 1 : index;
}

void main() {
  group('in order', () {
    test('an empty queue has no current track and cannot move', () {
      final queue = QueueModel();
      expect(queue.state.current, isNull);
      expect(queue.state.hasNext, isFalse);
      expect(queue.next, isNull);
      expect(queue.moveNext(), isA<QueueUnchanged>());
      expect(
        queue.movePrevious(position: Duration.zero),
        isA<QueueUnchanged>(),
      );
    });

    test('plays in order from the start index', () {
      final queue = QueueModel()
        ..replace(tracks(['a', 'b', 'c']), startIndex: 1);

      expect(currentId(queue.state), 'b');
      expect(queue.state.mode, QueueMode.queue);
      expect(queue.next, (index: 2, track: track('c')));
      expect(queue.moveNext(), isA<MovedToTrack>());
      expect(queue.state.currentIndex, 2);
    });

    test('next stops at the last track when loop is off', () {
      final queue = QueueModel()..replace(tracks(['a', 'b']), startIndex: 1);

      expect(queue.state.hasNext, isFalse);
      expect(queue.next, isNull);
      expect(queue.moveNext(), isA<QueueUnchanged>());
      expect(currentId(queue.state), 'b');
    });

    test('loop all wraps from the last track to the first', () {
      final queue = QueueModel()
        ..replace(tracks(['a', 'b']), startIndex: 1)
        ..cycleLoopMode();

      expect(queue.state.loopMode, LoopMode.all);
      expect(queue.state.hasNext, isTrue);
      expect(queue.next, (index: 0, track: track('a')));
      expect(queue.moveNext(), isA<MovedToTrack>());
      expect(currentId(queue.state), 'a');
    });

    test('loop one leaves next and previous to the queue order', () {
      final queue = QueueModel()..replace(tracks(['a', 'b']));
      queue
        ..cycleLoopMode()
        ..cycleLoopMode();
      expect(queue.state.loopMode, LoopMode.one);

      expect(queue.moveNext(), isA<MovedToTrack>());
      expect(currentId(queue.state), 'b');
      expect(queue.moveNext(), isA<QueueUnchanged>());

      expect(queue.movePrevious(position: Duration.zero), isA<MovedToTrack>());
      expect(currentId(queue.state), 'a');
      expect(queue.movePrevious(position: Duration.zero), isA<RestartTrack>());
      expect(currentId(queue.state), 'a');
    });

    test('loop cycles off, all, one and back to off', () {
      final queue = QueueModel();
      expect(queue.state.loopMode, LoopMode.off);
      expect(
        [for (var i = 0; i < 3; i++) queue.cycleLoopMode()],
        [LoopMode.all, LoopMode.one, LoopMode.off],
      );
    });

    test('the same track can appear twice, told apart by position', () {
      final queue = QueueModel()..replace(tracks(['a', 'a']));
      expect(queue.next, (index: 1, track: track('a')));
    });

    test('replacing with an empty list empties the queue', () {
      final queue = QueueModel()
        ..replace(tracks(['a']))
        ..replace([]);
      expect(queue.state.currentIndex, isNull);
      expect(queue.state.entries, isEmpty);
    });

    test('a start index outside the list is rejected', () {
      expect(
        () => QueueModel().replace(tracks(['a']), startIndex: 1),
        throwsRangeError,
      );
    });

    test('the snapshot does not change when the caller edits its list', () {
      final list = tracks(['a']);
      final queue = QueueModel()..replace(list);
      list.add(track('b'));
      expect(ids(queue.state), ['a']);
    });

    test(
      'each change publishes a new snapshot; old ones stay as they were',
      () {
        final queue = QueueModel()..replace(tracks(['a', 'b']));
        final before = queue.state;
        queue.append(tracks(['c']));
        expect(ids(before), ['a', 'b']);
        expect(ids(queue.state), ['a', 'b', 'c']);
        expect(
          () => queue.state.entries.add(QueueEntry(track('d'))),
          throwsUnsupportedError,
        );
      },
    );
  });

  group('previous', () {
    test('restarts after more than 3 seconds, goes back at 3 seconds', () {
      final queue = QueueModel()..replace(tracks(['a', 'b']), startIndex: 1);

      expect(
        queue.movePrevious(
          position: const Duration(seconds: 3, milliseconds: 1),
        ),
        isA<RestartTrack>(),
      );
      expect(currentId(queue.state), 'b');

      expect(
        queue.movePrevious(position: const Duration(seconds: 3)),
        isA<MovedToTrack>(),
      );
      expect(currentId(queue.state), 'a');
    });

    test('at the first track restarts it; loop all goes to the last', () {
      final queue = QueueModel()..replace(tracks(['a', 'b']));
      expect(queue.movePrevious(position: Duration.zero), isA<RestartTrack>());
      expect(currentId(queue.state), 'a');

      queue.cycleLoopMode();
      expect(queue.movePrevious(position: Duration.zero), isA<MovedToTrack>());
      expect(currentId(queue.state), 'b');
    });

    test('with shuffle goes back along the order, not the list', () {
      final queue = shuffled(6)..cycleLoopMode();
      final order = queue.state.shuffleOrder!;
      queue
        ..moveNext()
        ..moveNext();
      expect(queue.state.currentIndex, order[2]);

      expect(queue.movePrevious(position: Duration.zero), isA<MovedToTrack>());
      expect(queue.state.currentIndex, order[1]);
      expect(queue.state.shuffleOrder, order);
      queue.movePrevious(position: Duration.zero);
      // 一輪的開頭不往回繞，即使循環全部。
      expect(queue.movePrevious(position: Duration.zero), isA<RestartTrack>());
      expect(queue.state.currentIndex, order[0]);
    });
  });

  group('shuffle', () {
    test('turning it on orders every position with the current one first', () {
      final queue = shuffled(8, start: 3);
      final order = queue.state.shuffleOrder!;

      expect(queue.state.shuffleEnabled, isTrue);
      expect(order.first, 3);
      expect([...order]..sort(), [for (var i = 0; i < 8; i++) i]);
      expect(queue.state.currentIndex, 3);
    });

    test('turning it off continues down the list from the current track', () {
      final queue = shuffled(6)..moveNext();
      final current = queue.state.currentIndex!;

      queue.setShuffle(false);
      expect(queue.state.shuffleOrder, isNull);
      expect(queue.next?.index, current + 1);
    });

    test('a round plays every position once, then stops when loop is off', () {
      final queue = shuffled(6);
      final order = queue.state.shuffleOrder!;

      expect(
        [currentId(queue.state)!, ...playToEnd(queue)],
        [for (final position in order) '$position'],
      );
      expect(queue.state.hasNext, isFalse);
      expect(queue.state.currentIndex, order.last);
    });

    test('loop all starts a new order, not with the track that just ended', () {
      for (var seed = 0; seed < 20; seed++) {
        final queue = shuffled(4, seed: seed)..cycleLoopMode();
        while (upcoming(queue.state).isNotEmpty) {
          queue.moveNext();
        }
        final last = queue.state.currentIndex!;
        final peeked = queue.next!;

        expect(queue.moveNext(), isA<MovedToTrack>());
        final order = queue.state.shuffleOrder!;
        expect(queue.state.currentIndex, peeked.index);
        expect(order.first, peeked.index);
        expect(order.first, isNot(last));
        expect([...order]..sort(), [0, 1, 2, 3]);
      }
    });

    test('a single track with loop all plays again', () {
      final queue = QueueModel(random: Random(1))
        ..replace(tracks(['a']))
        ..setShuffle(true)
        ..cycleLoopMode();
      expect(queue.next, (index: 0, track: track('a')));
      expect(queue.moveNext(), isA<MovedToTrack>());
      expect(queue.state.shuffleOrder, [0]);
    });

    test('dragging moves the song, not the order of positions', () {
      final queue = shuffled(6);
      final order = queue.state.shuffleOrder!;

      // 目前這首在位置 0，拖曳不經過它。
      queue.move(2, 4);
      expect(ids(queue.state), ['0', '1', '3', '4', '2', '5']);
      expect(queue.state.shuffleOrder, order);
      expect(queue.state.currentIndex, 0);
      // 位置 4 輪到時播的是拖過去的歌。
      final played = playToEnd(queue);
      expect(played[order.indexOf(4) - 1], '2');
    });

    test('a song dragged into a played position is not played this round', () {
      final queue = shuffled(6, seed: 7)
        ..moveNext()
        ..moveNext();
      final state = queue.state;
      final order = state.shuffleOrder!;
      final playedPosition = order[0];
      final song = upcoming(state).last;
      final from = state.entries.indexWhere((e) => e.track.sourceId == song);

      queue.move(from, playedPosition);
      expect(played(queue.state), contains(song));
      expect(playToEnd(queue), isNot(contains(song)));
    });

    test('dragging the current song keeps it current at the same point of the '
        'round', () {
      final queue = shuffled(6, seed: 3)..moveNext();
      final before = queue.state;
      final cursor = before.shuffleOrder!.indexOf(before.currentIndex!);
      final from = before.currentIndex!;
      final to = from == 0 ? 5 : 0;

      queue.move(from, to);
      final after = queue.state;
      expect(after.currentIndex, to);
      expect(currentId(after), currentId(before));
      expect(after.shuffleOrder!.indexOf(to), cursor);
      expect([...after.shuffleOrder!]..sort(), [0, 1, 2, 3, 4, 5]);
    });

    test('play next goes right after the current track, in the order added; '
        'the rest keep their order', () {
      final queue = shuffled(6);
      final rest = upcoming(queue.state);

      queue
        ..playNext(tracks(['x']))
        ..playNext(tracks(['y', 'z']));
      expect(upcoming(queue.state), ['x', 'y', 'z', ...rest]);
      expect(ids(queue.state).sublist(1, 4), ['x', 'y', 'z']);
    });

    test('play next starts over after the current track changes', () {
      final queue = shuffled(6)..playNext(tracks(['x', 'y']));
      queue.moveNext();
      expect(currentId(queue.state), 'x');
      final rest = upcoming(queue.state);

      queue.playNext(tracks(['z']));
      expect(upcoming(queue.state), ['z', ...rest]);
    });

    test('play next starts over after a drag', () {
      final queue = shuffled(6, seed: 6)..playNext(tracks(['x', 'y']));
      final current = queue.state.currentIndex!;
      final last = queue.state.entries.length - 1;
      expect(ids(queue.state)[last], isNot(anyOf('x', 'y')));
      queue.move(last, current + 1);
      final rest = upcoming(queue.state);

      queue.playNext(tracks(['z']));
      expect(upcoming(queue.state), ['z', ...rest]);
      expect(ids(queue.state)[current + 1], 'z');
    });

    test('removing a play-next track keeps the rest of the run', () {
      final queue = shuffled(6)..playNext(tracks(['x', 'y']));
      final rest = upcoming(queue.state).sublist(2);

      queue
        ..remove(ids(queue.state).indexOf('x'))
        ..playNext(tracks(['z']));
      expect(upcoming(queue.state), ['y', 'z', ...rest]);
    });

    test('append lands somewhere unplayed after the play-next tracks; the rest '
        'keep their order', () {
      final queue = shuffled(6, seed: 5)
        ..moveNext()
        ..playNext(tracks(['p']));
      final playedBefore = played(queue.state);
      var rest = upcoming(queue.state);

      for (var i = 0; i < 20; i++) {
        queue.append(tracks(['a$i']));
        final state = queue.state;
        final next = upcoming(state);
        expect(next.first, 'p');
        expect(next.where((id) => id != 'a$i').toList(), rest);
        expect(played(state), playedBefore);
        expect(ids(state).last, 'a$i');
        rest = next;
      }
      // 不是都排在最後。
      expect(
        rest.sublist(rest.length - 20),
        isNot([for (var i = 0; i < 20; i++) 'a$i']),
      );
    });

    test('jumping to a track plays it next in the order; the rest keep their '
        'order', () {
      final queue = shuffled(6, seed: 2);
      final rest = upcoming(queue.state);
      final target = rest[2];

      queue.jumpTo(ids(queue.state).indexOf(target));
      expect(currentId(queue.state), target);
      expect(upcoming(queue.state), [...rest]..remove(target));
    });

    test('a seeded run of edits plays every position once per round', () {
      for (var seed = 0; seed < 5; seed++) {
        final random = Random(seed);
        final queue = shuffled(8, seed: seed + 100)..cycleLoopMode();
        var nextId = 8;
        // 每個位置的身分：插入、移除跟著清單；拖曳讓目前這首換了位置時，
        // 目前這首的身分跟著它（模型交換兩個位置的排序）。
        final slots = [for (var i = 0; i < 8; i++) i];
        var nextSlot = 8;
        var round = <int>[slots[queue.state.currentIndex!]];
        var rounds = 0;

        void expectFullRound() {
          expect(round.toSet(), hasLength(round.length), reason: 'seed $seed');
          expect(round.toSet(), slots.toSet(), reason: 'seed $seed');
        }

        for (var step = 0; step < 1500; step++) {
          final state = queue.state;
          final current = state.currentIndex!;
          final order = state.shuffleOrder!;
          final length = state.entries.length;
          switch (random.nextInt(7)) {
            case 0 || 1 || 2:
              final endOfRound = order.indexOf(current) == length - 1;
              final peeked = queue.next!.index;
              expect(queue.moveNext(), isA<MovedToTrack>());
              expect(queue.state.currentIndex, peeked);
              if (endOfRound) {
                expectFullRound();
                round = [];
                rounds++;
              }
              round.add(slots[queue.state.currentIndex!]);
            case 3:
              queue.move(random.nextInt(length), random.nextInt(length));
              final moved = queue.state.currentIndex!;
              if (moved != current) {
                final slot = slots[current];
                slots[current] = slots[moved];
                slots[moved] = slot;
              }
            case 4 when length < 30:
              final added = [
                for (var i = random.nextInt(3); i >= 0; i--)
                  track('${nextId++}'),
              ];
              if (random.nextBool()) {
                queue.append(added);
              } else {
                queue.playNext(added);
              }
              final at = queue.state.entries.indexWhere(
                (entry) => entry.track == added.first,
              );
              slots.insertAll(at, [for (final _ in added) nextSlot++]);
            case 5 when length > 3:
              final index = random.nextInt(length);
              final endOfRound =
                  index == current && order.indexOf(current) == length - 1;
              queue.remove(index);
              round.remove(slots.removeAt(index));
              if (index == current) {
                // 移除目前這首就往下一首，和播完一樣算進本輪。
                if (endOfRound) {
                  expectFullRound();
                  round = [];
                  rounds++;
                }
                round.add(slots[queue.state.currentIndex!]);
              }
            case 6:
              final index = otherPosition(random, current, length);
              final entry = state.entries[index];
              queue.moveToNext(index);
              expect(upcoming(queue.state), contains(entry.track.sourceId));
              final at = queue.state.entries.indexWhere(
                (candidate) => identical(candidate, entry),
              );
              // 排到目前這首之後：本輪已播過的這首要再播一次，和移除再加入一樣
              // 先從本輪的紀錄拿掉，再播到它時算一次。
              final slot = slots.removeAt(index);
              slots.insert(at, slot);
              round.remove(slot);
            default:
              break;
          }
          final after = queue.state;
          expect([...after.shuffleOrder!]..sort(), [
            for (var i = 0; i < after.entries.length; i++) i,
          ]);
        }
        expect(rounds, greaterThan(10), reason: 'seed $seed');
      }
    });
  });

  group('play next and append without shuffle', () {
    test('play next goes after the current track in the order added', () {
      final queue = QueueModel()..replace(tracks(['a', 'b', 'c']));
      queue
        ..playNext(tracks(['x']))
        ..playNext(tracks(['y']));
      expect(ids(queue.state), ['a', 'x', 'y', 'b', 'c']);

      queue.moveNext();
      queue.playNext(tracks(['z']));
      expect(ids(queue.state), ['a', 'x', 'z', 'y', 'b', 'c']);
    });

    test('removing a play-next track keeps the rest of the run', () {
      final queue = QueueModel()
        ..replace(tracks(['a', 'b']))
        ..playNext(tracks(['x', 'y']))
        ..remove(1)
        ..playNext(tracks(['z']));
      expect(ids(queue.state), ['a', 'y', 'z', 'b']);
    });

    test('adding to an empty queue makes the first added track current', () {
      final appended = QueueModel()..append(tracks(['a', 'b']));
      expect(currentId(appended.state), 'a');

      final next = QueueModel()
        ..playNext(tracks(['a', 'b']))
        ..playNext(tracks(['c']));
      expect(ids(next.state), ['a', 'b', 'c']);
      expect(currentId(next.state), 'a');
    });
  });

  group('move to next', () {
    test('without shuffle it goes after the current track and the run', () {
      final queue = QueueModel()..replace(tracks(['a', 'b', 'c', 'd', 'e']));
      queue.playNext(tracks(['x']));
      expect(ids(queue.state), ['a', 'x', 'b', 'c', 'd', 'e']);

      queue.moveToNext(4);
      expect(ids(queue.state), ['a', 'x', 'd', 'b', 'c', 'e']);
      expect(currentId(queue.state), 'a');
      queue.playNext(tracks(['y']));
      expect(ids(queue.state), ['a', 'x', 'd', 'y', 'b', 'c', 'e']);
    });

    test('a song before the current one moves past it', () {
      final queue = QueueModel()
        ..replace(tracks(['a', 'b', 'c', 'd']), startIndex: 2);
      final entry = queue.state.entries[0];

      queue.moveToNext(0);

      expect(ids(queue.state), ['b', 'c', 'a', 'd']);
      expect(currentId(queue.state), 'c');
      expect(queue.state.currentIndex, 1);
      expect(identical(queue.state.entries[2], entry), isTrue);
    });

    test('a song in the play-next run goes to the end of the run', () {
      final queue = QueueModel()..replace(tracks(['a', 'b']));
      queue.playNext(tracks(['x', 'y', 'z']));

      queue.moveToNext(1);

      expect(ids(queue.state), ['a', 'y', 'z', 'x', 'b']);
      queue.playNext(tracks(['w']));
      expect(ids(queue.state), ['a', 'y', 'z', 'x', 'w', 'b']);
    });

    test('two in a row play in the order they were chosen', () {
      final queue = shuffled(8, seed: 7);
      queue.moveToNext(ids(queue.state).indexOf('5'));
      queue.moveToNext(ids(queue.state).indexOf('2'));

      expect(upcoming(queue.state).take(2), ['5', '2']);
      expect(queue.moveNext(), isA<MovedToTrack>());
      expect(currentId(queue.state), '5');
      expect(queue.moveNext(), isA<MovedToTrack>());
      expect(currentId(queue.state), '2');
    });

    test('with shuffle the next track is the one chosen, even if played', () {
      final queue = shuffled(8, seed: 3);
      queue.moveNext();
      queue.moveNext();
      final replayed = played(queue.state).first;

      queue.moveToNext(ids(queue.state).indexOf(replayed));

      expect(upcoming(queue.state).first, replayed);
      expect(played(queue.state), isNot(contains(replayed)));
      expect([...queue.state.shuffleOrder!]..sort(), [
        for (var i = 0; i < 8; i++) i,
      ]);
    });

    test('it mixes with play next in either order', () {
      final queue = shuffled(6, seed: 11);
      queue.playNext(tracks(['x']));
      queue.moveToNext(ids(queue.state).indexOf('4'));
      queue.playNext(tracks(['y']));

      expect(upcoming(queue.state).take(3), ['x', '4', 'y']);
    });

    test('during a temporary play it goes after the snapshot song', () {
      final queue = QueueModel()..replace(tracks(['a', 'b', 'c']));
      queue.playTemporary(track('t'), position: Duration.zero, playing: true);

      queue.moveToNext(2);

      expect(ids(queue.state), ['a', 'c', 'b']);
      expect(queue.state.mode, QueueMode.temporary);
      expect(queue.state.currentIndex, 0);
    });

    test('the current song does nothing; an empty queue has no position', () {
      final queue = QueueModel();
      expect(() => queue.moveToNext(0), throwsRangeError);

      queue.replace(tracks(['a', 'b']));
      final before = queue.state;
      queue.moveToNext(0);
      expect(ids(queue.state), ids(before));
      expect(queue.state.currentIndex, 0);
    });

    test('changing song starts a new run', () {
      final queue = QueueModel()..replace(tracks(['a', 'b', 'c', 'd', 'e']));
      queue.moveToNext(4);
      queue.moveNext();
      expect(ids(queue.state), ['a', 'e', 'b', 'c', 'd']);
      expect(currentId(queue.state), 'e');

      queue.moveToNext(4);
      queue.moveToNext(4);

      expect(ids(queue.state), ['a', 'e', 'd', 'c', 'b']);
    });
  });

  group('remove and clear', () {
    test('removing before the current track keeps the current track', () {
      final queue = QueueModel()
        ..replace(tracks(['a', 'b', 'c']), startIndex: 2);
      queue.remove(0);
      expect(ids(queue.state), ['b', 'c']);
      expect(currentId(queue.state), 'c');
    });

    test('removing the current track moves to the next one', () {
      final queue = QueueModel()
        ..replace(tracks(['a', 'b', 'c']), startIndex: 1);
      queue.remove(1);
      expect(ids(queue.state), ['a', 'c']);
      expect(currentId(queue.state), 'c');
    });

    test('removing the current last track moves back when loop is off, to the '
        'first when loop is all', () {
      final off = QueueModel()..replace(tracks(['a', 'b', 'c']), startIndex: 2);
      off.remove(2);
      expect(currentId(off.state), 'b');

      final all = QueueModel()
        ..replace(tracks(['a', 'b', 'c']), startIndex: 2)
        ..cycleLoopMode();
      all.remove(2);
      expect(currentId(all.state), 'a');
    });

    test('removing with shuffle moves along the order; the rest keep their '
        'order', () {
      final queue = shuffled(6, seed: 4)..moveNext();
      final rest = upcoming(queue.state);
      final playedBefore = played(queue.state);

      queue.remove(queue.state.currentIndex!);
      expect(currentId(queue.state), rest.first);
      expect(upcoming(queue.state), rest.sublist(1));
      expect(played(queue.state), playedBefore);

      final other = rest[2];
      queue.remove(ids(queue.state).indexOf(other));
      expect(upcoming(queue.state), [...rest.sublist(1)]..remove(other));
    });

    test('removing the only track empties the queue', () {
      final queue = QueueModel()..replace(tracks(['a']));
      queue.remove(0);
      expect(queue.state.currentIndex, isNull);
      expect(queue.state.entries, isEmpty);
    });

    test('clear empties the queue and keeps loop and shuffle', () {
      final queue = shuffled(3)
        ..cycleLoopMode()
        ..playTemporary(track('t'), position: Duration.zero, playing: true);
      queue.clear();

      expect(queue.state.entries, isEmpty);
      expect(queue.state.current, isNull);
      expect(queue.state.mode, QueueMode.queue);
      expect(queue.state.loopMode, LoopMode.all);
      expect(queue.state.shuffleEnabled, isTrue);
    });
  });

  group('limit', () {
    test('replace takes exactly 10,000 and rejects 10,001 as a whole', () {
      final queue = QueueModel()..replace(tracks(['a']));
      final before = queue.state;

      expect(queue.replace(numbered(QueueModel.maxLength + 1)), isFalse);
      expect(queue.state, same(before));
      expect(queue.replace(numbered(QueueModel.maxLength)), isTrue);
      expect(queue.state.entries, hasLength(10000));
    });

    test('append and play next reject the whole batch past 10,000', () {
      for (final add in <bool Function(QueueModel, List<TrackInfo>)>[
        (queue, tracks) => queue.append(tracks),
        (queue, tracks) => queue.playNext(tracks),
      ]) {
        final queue = QueueModel()..replace(numbered(QueueModel.maxLength - 1));
        final before = queue.state;

        expect(add(queue, tracks(['x', 'y'])), isFalse);
        expect(queue.state, same(before));
        expect(add(queue, tracks(['x'])), isTrue);
        expect(queue.state.entries, hasLength(10000));
        expect(add(queue, tracks(['y'])), isFalse);
        expect(queue.state.entries, hasLength(10000));
      }
    });

    test('temporary play does not count against the limit', () {
      final queue = QueueModel()..replace(numbered(QueueModel.maxLength));
      queue.playTemporary(track('t'), position: Duration.zero, playing: true);
      expect(currentId(queue.state), 't');
      expect(queue.state.entries, hasLength(10000));
    });
  });

  group('temporary play', () {
    test('plays a track outside the queue and returns to the snapshot', () {
      final queue = QueueModel()..replace(tracks(['a', 'b']), startIndex: 1);
      final entries = queue.state.entries;

      queue.playTemporary(
        track('t'),
        position: const Duration(seconds: 42),
        playing: true,
      );
      expect(queue.state.mode, QueueMode.temporary);
      expect(currentId(queue.state), 't');
      expect(queue.state.entries, entries);
      expect(queue.state.currentIndex, 1);
      expect(queue.state.hasNext, isTrue);
      expect(queue.next, (index: 1, track: track('b')));

      final step = queue.moveNext();
      expect(step, isA<ReturnedToQueue>());
      final snapshot = (step as ReturnedToQueue).snapshot;
      expect(snapshot.position, const Duration(seconds: 42));
      expect(snapshot.playing, isTrue);
      expect(queue.state.mode, QueueMode.queue);
      expect(currentId(queue.state), 'b');
    });

    test('previous also returns to the queue', () {
      final queue = QueueModel()
        ..replace(tracks(['a', 'b']), startIndex: 1)
        ..playTemporary(track('t'), position: Duration.zero, playing: false);

      expect(
        queue.movePrevious(position: const Duration(seconds: 30)),
        isA<ReturnedToQueue>(),
      );
      expect(currentId(queue.state), 'b');
    });

    test('a second temporary track keeps the earliest snapshot', () {
      final queue = QueueModel()
        ..replace(tracks(['a', 'b']))
        ..playTemporary(
          track('t1'),
          position: const Duration(seconds: 10),
          playing: true,
        )
        ..playTemporary(
          track('t2'),
          position: const Duration(seconds: 99),
          playing: false,
        );

      expect(currentId(queue.state), 't2');
      final snapshot = (queue.moveNext() as ReturnedToQueue).snapshot;
      expect(snapshot.position, const Duration(seconds: 10));
      expect(snapshot.playing, isTrue);
      expect(currentId(queue.state), 'a');
    });

    test(
      'looping one track stays temporary and still returns to the snapshot',
      () {
        final queue = QueueModel()
          ..replace(tracks(['a', 'b']), startIndex: 1)
          ..playTemporary(
            track('t'),
            position: const Duration(seconds: 5),
            playing: true,
          )
          ..cycleLoopMode()
          ..cycleLoopMode();

        expect(queue.state.loopMode, LoopMode.one);
        expect(queue.state.mode, QueueMode.temporary);
        expect(currentId(queue.state), 't');

        final step = queue.moveNext() as ReturnedToQueue;
        expect(step.snapshot.position, const Duration(seconds: 5));
        expect(currentId(queue.state), 'b');
      },
    );

    test(
      'picking a queue track ends temporary play and drops the snapshot',
      () {
        final queue = QueueModel()
          ..replace(tracks(['a', 'b', 'c']))
          ..playTemporary(track('t'), position: Duration.zero, playing: true);

        queue.jumpTo(2);
        expect(queue.state.mode, QueueMode.queue);
        expect(queue.state.temporary, isNull);
        expect(currentId(queue.state), 'c');
        expect(queue.moveNext(), isA<QueueUnchanged>());
      },
    );

    test('play next during temporary play goes after the snapshot track', () {
      final queue = QueueModel()
        ..replace(tracks(['a', 'b', 'c']), startIndex: 1)
        ..playTemporary(track('t'), position: Duration.zero, playing: true)
        ..playNext(tracks(['x']))
        ..playNext(tracks(['y']));

      expect(ids(queue.state), ['a', 'b', 'x', 'y', 'c']);
      expect(currentId(queue.state), 't');
      queue.moveNext();
      expect(currentId(queue.state), 'b');
      expect(queue.next?.track, track('x'));
    });

    test('from an empty queue returns to nothing', () {
      final queue = QueueModel()
        ..playTemporary(
          track('t'),
          position: const Duration(seconds: 8),
          playing: true,
        );

      final step = queue.moveNext() as ReturnedToQueue;
      expect(step.snapshot.playing, isFalse);
      expect(queue.state.current, isNull);
    });

    test(
      'removing the snapshot track returns to the next one from its start',
      () {
        final queue = QueueModel()
          ..replace(tracks(['a', 'b', 'c']))
          ..playTemporary(
            track('t'),
            position: const Duration(seconds: 50),
            playing: true,
          );

        queue.remove(0);
        expect(currentId(queue.state), 't');
        final snapshot = (queue.moveNext() as ReturnedToQueue).snapshot;
        expect(snapshot.position, Duration.zero);
        expect(snapshot.playing, isTrue);
        expect(currentId(queue.state), 'b');
      },
    );

    test('replacing the queue ends temporary play', () {
      final queue = QueueModel()
        ..playTemporary(track('t'), position: Duration.zero, playing: true)
        ..replace(tracks(['a']));
      expect(queue.state.mode, QueueMode.queue);
      expect(currentId(queue.state), 'a');
    });

    test('resume position rewinds when remembered, else starts over', () {
      const snapshot = QueueSnapshot(
        position: Duration(seconds: 30),
        playing: true,
      );
      expect(
        snapshot.resumeAt(
          rememberPosition: true,
          rewind: const Duration(seconds: 10),
        ),
        const Duration(seconds: 20),
      );
      expect(
        snapshot.resumeAt(
          rememberPosition: true,
          rewind: const Duration(seconds: 45),
        ),
        Duration.zero,
      );
      expect(
        snapshot.resumeAt(
          rememberPosition: false,
          rewind: const Duration(seconds: 10),
        ),
        Duration.zero,
      );
    });
  });

  group('restore', () {
    test('brings back the queue, the current song and the loop mode', () {
      final queue = QueueModel()
        ..restore(
          tracks: tracks(['a', 'b', 'c']),
          currentIndex: 1,
          loopMode: LoopMode.all,
          shuffle: false,
        );

      expect(ids(queue.state), ['a', 'b', 'c']);
      expect(currentId(queue.state), 'b');
      expect(queue.state.loopMode, LoopMode.all);
      expect(queue.state.shuffleEnabled, isFalse);
      expect(queue.state.mode, QueueMode.queue);
      expect(upcoming(queue.state), ['c']);
    });

    test('keeps the shuffle order it was given', () {
      final queue = QueueModel()
        ..restore(
          tracks: tracks(['a', 'b', 'c', 'd']),
          currentIndex: 2,
          loopMode: LoopMode.off,
          shuffle: true,
          shuffleOrder: [3, 2, 0, 1],
        );

      expect(queue.state.shuffleOrder, [3, 2, 0, 1]);
      expect(played(queue.state), ['d']);
      expect(upcoming(queue.state), ['a', 'b']);
      expect(playToEnd(queue), ['a', 'b']);
    });

    test('makes a new order, current song first, when shuffle is on but the '
        'order was not stored', () {
      final queue = QueueModel(random: Random(3))
        ..restore(
          tracks: numbered(6),
          currentIndex: 4,
          loopMode: LoopMode.off,
          shuffle: true,
        );

      final order = queue.state.shuffleOrder!;
      expect(order.first, 4);
      expect([...order]..sort(), [0, 1, 2, 3, 4, 5]);
    });

    test('an empty queue has no current song, and shuffle stays on', () {
      final queue = QueueModel()
        ..restore(
          tracks: const [],
          currentIndex: null,
          loopMode: LoopMode.one,
          shuffle: true,
        );

      expect(queue.state.entries, isEmpty);
      expect(queue.state.currentIndex, isNull);
      expect(queue.state.shuffleEnabled, isTrue);
      expect(queue.state.loopMode, LoopMode.one);
    });

    test('a position outside the queue is clamped', () {
      final queue = QueueModel()
        ..restore(
          tracks: numbered(3),
          currentIndex: 9,
          loopMode: LoopMode.off,
          shuffle: false,
        );

      expect(currentId(queue.state), '2');
    });

    test('a restored queue edits like any other', () {
      final queue = QueueModel(random: Random(5))
        ..restore(
          tracks: numbered(4),
          currentIndex: 0,
          loopMode: LoopMode.off,
          shuffle: true,
          shuffleOrder: [0, 3, 2, 1],
        );

      queue.playNext(tracks(['x']));
      expect(upcoming(queue.state).first, 'x');
      expect(queue.moveNext(), isA<MovedToTrack>());
      expect(currentId(queue.state), 'x');
    });
  });
}
