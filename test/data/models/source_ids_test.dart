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

    test('shortNameFor prefers the short key, then the display name', () {
      LocaleSettings.setLocale(AppLocale.en);
      expect(SourceIds.shortNameFor(SourceIds.netease), 'NetEase');
      expect(SourceIds.shortNameFor(SourceIds.youtube), 'YouTube');
      expect(SourceIds.shortNameFor('soundcloud'), 'soundcloud');
    });

    // 音訊設定頁依音源 id 組出這些鍵去查，程式碼裡搜不到它們的名字；少了一個
    // 不會編譯錯誤，那一段只會退回顯示音源名稱。
    test('every built-in source has its audio settings texts', () {
      for (final locale in AppLocale.values) {
        LocaleSettings.setLocale(locale);
        for (final id in SourceIds.values) {
          for (final key in [
            'audioSettings.streamPriority.${id}Title',
            'audioSettings.authForPlay.${id}Description',
          ]) {
            expect(t[key], isA<String>(), reason: '$locale $key');
          }
        }
      }
      LocaleSettings.setLocale(AppLocale.en);
    });
  });
}
