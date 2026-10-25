import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/ui/tracks/track_markers.dart';

// 「正在播放」的比對（ADR 0035，B-01、B-34）：以 `TrackKey` 完整比對；影片列與分 P 群組標題用
// 分組鍵（`TrackKey.formatGroup`），同一支影片任何分 P 在播都算。

TrackInfo _track(String id, {int? cid, String source = 'fmp-test'}) =>
    TrackInfo(
      sourceTypeId: source,
      sourceId: id,
      cid: cid,
      title: id,
      partIndex: cid == null ? null : cid - 100,
    );

void main() {
  group('PlayingKey.matches', () {
    final playing = PlayingKey.of(_track('v', cid: 102));

    test('the exact key only matches that part', () {
      expect(playing.matches(_track('v', cid: 102)), isTrue);
      expect(playing.matches(_track('v', cid: 101)), isFalse);
      expect(playing.matches(_track('v')), isFalse);
      expect(playing.matches(_track('w', cid: 102)), isFalse);
      expect(playing.matches(_track('v', cid: 102, source: 'other')), isFalse);
    });

    test('the group key matches every part of the video and the video', () {
      expect(playing.matches(_track('v', cid: 101), group: true), isTrue);
      expect(playing.matches(_track('v'), group: true), isTrue);
      expect(playing.matches(_track('w'), group: true), isFalse);
      expect(
        playing.matches(_track('v', source: 'other'), group: true),
        isFalse,
      );
    });

    test('a track without parts matches only itself', () {
      final song = PlayingKey.of(_track('a'));
      expect(song.matches(_track('a')), isTrue);
      expect(song.matches(_track('b')), isFalse);
      expect(song.matches(_track('b'), group: true), isFalse);
    });
  });
}
