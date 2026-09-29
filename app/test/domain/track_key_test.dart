import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/track_key.dart';

/// 識別鍵的字面輸出是持久化格式的一部分：新資料庫的曲目唯一鍵，也是 M5 匯入
/// 舊資料時對上舊版 Isar 索引與備份 JSON 的鍵。所以這裡用寫死的字串釘住輸出，
/// 字面值與舊版 `test/data/models/track_key_test.dart` 相同。
void main() {
  group('TrackKey literal output', () {
    test('is pinned for both the cid and the cid-less branch', () {
      expect(TrackKey.format('bilibili', 'BV123456'), 'bilibili:BV123456');
      expect(
        TrackKey.format('bilibili', 'BV123456', cid: 42),
        'bilibili:BV123456:42',
      );
      expect(TrackKey.formatGroup('bilibili', 'BV123456'), 'bilibili:BV123456');
      expect(TrackKey.format('youtube', 's466YCiHfKw'), 'youtube:s466YCiHfKw');
      expect(TrackKey.format('netease', '139774'), 'netease:139774');
    });

    test('the group key leaves out the cid', () {
      // 同一支影片的分 P 要落在同一組。
      expect(
        TrackKey.formatGroup('bilibili', 'BV123456'),
        TrackKey.format('bilibili', 'BV123456'),
      );
      expect(
        TrackKey.formatGroup('bilibili', 'BV123456'),
        isNot(TrackKey.format('bilibili', 'BV123456', cid: 42)),
      );
    });

    test('toString of parsed parts is the key itself', () {
      expect(
        const TrackKeyParts(
          sourceTypeId: 'bilibili',
          sourceId: 'BV123456',
          cid: 42,
        ).toString(),
        'bilibili:BV123456:42',
      );
    });
  });

  group('tryParse', () {
    test('round-trips everything format produces', () {
      for (final parts in [
        const TrackKeyParts(sourceTypeId: 'bilibili', sourceId: 'BV1'),
        const TrackKeyParts(sourceTypeId: 'bilibili', sourceId: 'BV1', cid: 42),
        const TrackKeyParts(sourceTypeId: 'youtube', sourceId: 's466YCiHfKw'),
        const TrackKeyParts(sourceTypeId: 'netease', sourceId: '139774'),
      ]) {
        final raw = TrackKey.format(
          parts.sourceTypeId,
          parts.sourceId,
          cid: parts.cid,
        );
        expect(TrackKey.tryParse(raw), parts, reason: raw);
      }
    });

    test('rejects what it cannot round-trip', () {
      expect(TrackKey.tryParse('bilibili'), isNull);
      expect(TrackKey.tryParse('bilibili:'), isNull);
      expect(TrackKey.tryParse(':BV1'), isNull);
      expect(TrackKey.tryParse('bilibili:BV1:notacid'), isNull);
      expect(TrackKey.tryParse('a:b:1:2'), isNull);
    });
  });
}
