/// 排行榜頁面的 watch 範圍。
///
/// 整包 watch `rankingCacheServiceProvider` 一樣會顯示正確的資料，只是三個音源
/// 任何一個回來都重建整頁。沒有錯誤訊息，只有掉幀 —— 所以只有源碼比對抓得到。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ranking watch scope static rules', () {
    test('home rankings select only the initial loading flag', () {
      final homePageSource = File(
        'lib/ui/pages/home/home_page.dart',
      ).readAsStringSync();

      expect(
        RegExp(
          r'ref\.watch\(\s*rankingCacheServiceProvider\.select\(\(state\)\s*=>\s*state\.isInitialLoading\)\s*,?\s*\)',
          dotAll: true,
        ).hasMatch(homePageSource),
        isTrue,
        reason:
            'Home rankings should not rebuild for unrelated ranking cache '
            'state changes.',
      );
    });

    test('explore tabs select only source-specific ranking cache fields', () {
      final source = File(
        'lib/ui/pages/explore/explore_page.dart',
      ).readAsStringSync();

      // 只比對 select 片段，不含 provider 名稱：`dart format` 會把長行折在
      // provider 與 .select 之間，把兩者綁在同一個字串會讓這條測試隨格式化紅燈。
      expect(
        source,
        isNot(contains('ref.watch(rankingCacheServiceProvider);')),
      );
      expect(
        source,
        contains(
          'rankingCacheServiceProvider.select((state) => state.isInitialLoading)',
        ),
      );
      for (final sourceId in const ['bilibili', 'youtube', 'netease']) {
        expect(
          source,
          matches(
            RegExp(
              r'\.select\(\s*\(state\) => state\.errorFor\(SourceIds\.'
              '$sourceId'
              r'\)',
            ),
          ),
          reason: '$sourceId tab should select only its own error field',
        );
      }
    });
  });
}
