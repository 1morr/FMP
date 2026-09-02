import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_history.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/models/track_key.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/services/backup/backup_data.dart';

/// 識別鍵的字面輸出是持久化格式的一部分：它同時是 Isar 複合索引的鍵
/// （`Track.sourcePageKey`，Isar 只在 put 時重算索引項）與備份 JSON 的外鍵。
/// 所以這裡用寫死的字串釘住輸出，並斷言每一份實作彼此一致。
void main() {
  final createdAt = DateTime.utc(2026, 1, 1);

  Track buildTrack({int? cid}) => Track()
    ..sourceId = 'BV123456'
    ..sourceType = SourceType.bilibili
    ..title = 'T'
    ..cid = cid
    ..createdAt = createdAt;

  group('TrackKey literal output', () {
    test('is pinned for both the cid and the cid-less branch', () {
      expect(TrackKey.format('bilibili', 'BV123456'), 'bilibili:BV123456');
      expect(TrackKey.format('bilibili', 'BV123456', cid: 42),
          'bilibili:BV123456:42');
      expect(TrackKey.formatGroup('bilibili', 'BV123456'), 'bilibili:BV123456');
      expect(TrackKey.format('youtube', 's466YCiHfKw'), 'youtube:s466YCiHfKw');
      expect(TrackKey.format('netease', '139774'), 'netease:139774');
    });
  });

  group('every producer agrees', () {
    test('cid-less tracks produce the same key everywhere', () {
      const expected = 'bilibili:BV123456';
      final track = buildTrack();

      expect(track.uniqueKey, expected);
      expect(track.sourcePageKey, expected);
      expect(track.groupKey, expected);

      final history = PlayHistory.fromTrack(track);
      expect(history.trackKey, expected);

      expect(TrackSourceIdentity.fromTrack(track).sourcePageKey, expected);

      final trackBackup = TrackBackup(
        sourceId: 'BV123456',
        sourceType: 'bilibili',
        title: 'T',
        createdAt: createdAt,
      );
      expect(trackBackup.uniqueKey, expected);

      final historyBackup = PlayHistoryBackup(
        sourceId: 'BV123456',
        sourceType: 'bilibili',
        title: 'T',
        playedAt: createdAt,
      );
      expect(historyBackup.trackKey, expected);

      final station = RadioStation()
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili;
      expect(station.uniqueKey, expected);
    });

    test('tracks with a cid produce the same key everywhere', () {
      const expected = 'bilibili:BV123456:42';
      final track = buildTrack(cid: 42);

      expect(track.uniqueKey, expected);
      expect(track.sourcePageKey, expected);
      expect(PlayHistory.fromTrack(track).trackKey, expected);
      expect(TrackSourceIdentity.fromTrack(track).sourcePageKey, expected);
      expect(
        TrackBackup(
          sourceId: 'BV123456',
          sourceType: 'bilibili',
          title: 'T',
          cid: 42,
          createdAt: createdAt,
        ).uniqueKey,
        expected,
      );
      expect(
        PlayHistoryBackup(
          sourceId: 'BV123456',
          sourceType: 'bilibili',
          title: 'T',
          cid: 42,
          playedAt: createdAt,
        ).trackKey,
        expected,
      );

      // groupKey 刻意不含 cid —— 同一支影片的分 P 要落在同一組。
      expect(track.groupKey, 'bilibili:BV123456');
    });
  });

  group('tryParse', () {
    test('round-trips everything format produces', () {
      for (final parts in [
        const TrackKeyParts(sourceTypeId: 'bilibili', sourceId: 'BV1'),
        const TrackKeyParts(
            sourceTypeId: 'bilibili', sourceId: 'BV1', cid: 42),
        const TrackKeyParts(sourceTypeId: 'youtube', sourceId: 's466YCiHfKw'),
        const TrackKeyParts(sourceTypeId: 'netease', sourceId: '139774'),
      ]) {
        final raw = TrackKey.format(parts.sourceTypeId, parts.sourceId,
            cid: parts.cid);
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
