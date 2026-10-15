import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/ui/library/library_state.dart';

// 歌單詳情的分 P 分組與拖曳後的順序（M4 PR 3，design §10.4）：純函數。

var _nextId = 0;

/// 一首一般的曲目。
PlaylistEntry _song(String id) => PlaylistEntry(
  id: _nextId++,
  position: _nextId,
  track: TrackInfo(sourceTypeId: 'fmp-test', sourceId: id, title: id),
);

/// 影片 [video] 的第 [index] 個分 P。
PlaylistEntry _part(String video, int index, {String source = 'fmp-test'}) =>
    PlaylistEntry(
      id: _nextId++,
      position: _nextId,
      track: TrackInfo(
        sourceTypeId: source,
        sourceId: video,
        cid: 100 + index,
        title: 'P$index',
        partIndex: index,
        parentTitle: 'Video $video',
      ),
    );

/// 列的簡寫：群組標題是 `[影片 id]`，群組裡的分 P 前面加兩個空白。
List<String> _shape(List<PlaylistRow> rows) => [
  for (final row in rows)
    switch (row) {
      PlaylistGroupRow(:final parts) => '[${parts.first.track.sourceId}]',
      PlaylistEntryRow(:final entry, inGroup: true) =>
        '  ${entry.track.sourceId}${entry.track.cid}',
      PlaylistEntryRow(:final entry) =>
        '${entry.track.sourceId}${entry.track.cid ?? ''}',
    },
];

void main() {
  group('groupParts', () {
    test('consecutive parts of one video go under its title', () {
      final rows = groupParts([
        _song('a'),
        _part('v', 1),
        _part('v', 2),
        _part('v', 3),
        _song('b'),
      ]);

      expect(_shape(rows), ['a', '[v]', '  v101', '  v102', '  v103', 'b']);
    });

    test('a single part is a plain row, not a group of one', () {
      expect(_shape(groupParts([_song('a'), _part('v', 2), _song('b')])), [
        'a',
        'v102',
        'b',
      ]);
    });

    test('parts of one video that are not next to each other are not '
        'merged', () {
      final rows = groupParts([
        _part('v', 1),
        _part('v', 2),
        _song('a'),
        _part('v', 3),
        _part('v', 4),
      ]);

      expect(_shape(rows), [
        '[v]',
        '  v101',
        '  v102',
        'a',
        '[v]',
        '  v103',
        '  v104',
      ]);
    });

    test('two videos next to each other are two groups', () {
      expect(
        _shape(
          groupParts([
            _part('v', 1),
            _part('v', 2),
            _part('w', 1),
            _part('w', 2),
          ]),
        ),
        ['[v]', '  v101', '  v102', '[w]', '  w101', '  w102'],
      );
    });

    test('the same video id from another source is another video', () {
      expect(
        _shape(groupParts([_part('v', 1), _part('v', 2, source: 'other')])),
        ['v101', 'v102'],
      );
    });

    test('the same part twice in a row is still one group', () {
      final part = _part('v', 1);
      final again = PlaylistEntry(
        id: _nextId++,
        position: _nextId,
        track: part.track,
      );

      expect(_shape(groupParts([part, again])), ['[v]', '  v101', '  v101']);
    });

    test('the video itself (no part index) does not join its parts', () {
      final video = PlaylistEntry(
        id: _nextId++,
        position: _nextId,
        track: const TrackInfo(
          sourceTypeId: 'fmp-test',
          sourceId: 'v',
          title: 'Video v',
        ),
      );

      expect(_shape(groupParts([video, _part('v', 1), _part('v', 2)])), [
        'v',
        '[v]',
        '  v101',
        '  v102',
      ]);
    });
  });

  group('reorderedEntryIds', () {
    test('moves an entry among plain rows', () {
      final entries = [_song('a'), _song('b'), _song('c')];
      final rows = groupParts(entries);

      // a 拖到最後（`to` 已扣掉被拿起的那一格）。
      expect(reorderedEntryIds(rows, 0, 2), [
        entries[1].id,
        entries[2].id,
        entries[0].id,
      ]);
    });

    test('rows of group titles do not count as positions', () {
      final a = _song('a');
      final p1 = _part('v', 1);
      final p2 = _part('v', 2);
      final b = _song('b');
      // [a, [v], p1, p2, b]
      final rows = groupParts([a, p1, p2, b]);

      // b 放在群組標題之前（第 1 列）：在 a 之後、p1 之前。
      expect(reorderedEntryIds(rows, 4, 1), [a.id, b.id, p1.id, p2.id]);
      // b 放在標題與 p1 之間（第 2 列）：一樣是 p1 之前。
      expect(reorderedEntryIds(rows, 4, 2), [a.id, b.id, p1.id, p2.id]);
      // a 拖到最後。
      expect(reorderedEntryIds(rows, 0, 4), [p1.id, p2.id, b.id, a.id]);
      // p1 拖到 p2 之後。
      expect(reorderedEntryIds(rows, 2, 3), [a.id, p2.id, p1.id, b.id]);
    });

    test('a group title cannot be dragged', () {
      final rows = groupParts([_part('v', 1), _part('v', 2)]);

      expect(() => reorderedEntryIds(rows, 0, 2), throwsArgumentError);
    });
  });
}
