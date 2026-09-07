import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/source_ids.dart';
import 'package:fmp/i18n/strings.g.dart';

/// `SourceIds` 的字串就是磁碟上的值，也是 `TrackKey` 的第一段。
/// 改動這些字面值會讓既有資料庫的索引項與新查詢對不上。
void main() {
  group('SourceIds', () {
    test('the ids are exactly the strings already on disk', () {
      expect(SourceIds.bilibili, 'bilibili');
      expect(SourceIds.youtube, 'youtube');
      expect(SourceIds.netease, 'netease');
      expect(SourceIds.values, ['bilibili', 'youtube', 'netease']);
    });

    test('no id can collide with the TrackKey delimiter', () {
      for (final id in SourceIds.values) {
        expect(id, isNotEmpty);
        expect(id, isNot(contains(':')));
        expect(id, equals(id.toLowerCase()));
      }
    });

    test('displayNameFor resolves the built-in ids through i18n', () {
      expect(
        SourceIds.displayNameFor(SourceIds.bilibili),
        t.importPlatform.bilibili,
      );
      expect(
        SourceIds.displayNameFor(SourceIds.netease),
        t.importPlatform.netease,
      );
    });

    test('displayNameFor falls back to the raw id', () {
      // 新增音源只要補一筆 i18n 就有名字；沒補之前顯示原始 id，
      // 而不是謊稱它是別的平台。
      expect(SourceIds.displayNameFor('soundcloud'), 'soundcloud');
      expect(SourceIds.displayNameFor(''), '');
    });
  });
}
