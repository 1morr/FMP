import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';

void main() {
  group('home ranking source id whitelist (D4)', () {
    test('homeRankingSourceIds derives from SourceType.values, not a literal', () {
      // 單一真相：白名單必須隨 SourceType enum 同步。
      // 新增 enum 值未補到此 list 時，此測試應失敗（D4 防靜默丟棄）。
      final expected =
          SourceType.values.map((type) => type.name).toList(growable: false);
      expect(homeRankingSourceIds, expected);
      expect(homeRankingSourceIds, hasLength(SourceType.values.length));
    });

    test('defaultHomeRankingSourcePriority stays in sync with the whitelist', () {
      // 預設排序字串與白名單順序一致；若將來改成衍生，此測試仍應成立。
      expect(
        defaultHomeRankingSourcePriority,
        homeRankingSourceIds.join(','),
      );
    });

    test('normalize keeps every registered source id', () {
      // 所有 enum 來源的 id 經 normalize 後都不被靜默丟棄。
      final shuffled = homeRankingSourceIds.reversed.join(',');
      final normalized = normalizeHomeRankingSourcePriority(shuffled);
      expect({...normalized}, {...homeRankingSourceIds});
    });
  });
}
