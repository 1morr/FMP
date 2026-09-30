import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/playback/queue_model.dart';

TrackKeyParts track(String id) =>
    TrackKeyParts(sourceTypeId: 'fmp-test', sourceId: id);

void main() {
  test('an empty queue has no current track and cannot move', () {
    final queue = QueueModel();
    expect(queue.state.current, isNull);
    expect(queue.next, isNull);
    expect(queue.moveNext(), isFalse);
    expect(queue.movePrevious(), isFalse);
  });

  test('plays in order from the start index', () {
    final queue = QueueModel()
      ..replace([track('a'), track('b'), track('c')], startIndex: 1);

    expect(queue.state.current, track('b'));
    expect(queue.next, (index: 2, track: track('c')));
    expect(queue.state.hasPrevious, isTrue);
    expect(queue.moveNext(), isTrue);
    expect(queue.state.currentIndex, 2);
  });

  test('next stops at the last track', () {
    final queue = QueueModel()..replace([track('a'), track('b')]);
    expect(queue.moveNext(), isTrue);

    expect(queue.state.hasNext, isFalse);
    expect(queue.next, isNull);
    expect(queue.moveNext(), isFalse);
    expect(queue.state.current, track('b'));
  });

  test('previous stops at the first track', () {
    final queue = QueueModel()..replace([track('a'), track('b')]);

    expect(queue.state.hasPrevious, isFalse);
    expect(queue.movePrevious(), isFalse);
    expect(queue.state.current, track('a'));
    queue.moveNext();
    expect(queue.movePrevious(), isTrue);
    expect(queue.state.current, track('a'));
  });

  test('the same track can appear twice, told apart by position', () {
    final queue = QueueModel()..replace([track('a'), track('a')]);
    expect(queue.next, (index: 1, track: track('a')));
  });

  test('replacing with an empty list empties the queue', () {
    final queue = QueueModel()
      ..replace([track('a')])
      ..replace([]);
    expect(queue.state.currentIndex, isNull);
  });

  test('a start index outside the list is rejected', () {
    expect(
      () => QueueModel().replace([track('a')], startIndex: 1),
      throwsRangeError,
    );
  });

  test('the snapshot does not change when the caller edits its list', () {
    final tracks = [track('a')];
    final queue = QueueModel()..replace(tracks);
    tracks.add(track('b'));
    expect(queue.state.tracks, [track('a')]);
  });
}
