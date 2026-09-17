/// `lib/core/` 裡兩條只有讀源碼才驗得到的規則。
///
/// 授權登記那條原本藏在 `third_party_licenses_test.dart` 裡，從檔名看不出它在
/// grep 源碼。#107 那條原本混在播放頁的結構規則裡，跟著那些結構斷言一起被砍時
/// 留了下來 —— 它守的是一個修過的 bug，不是版面。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('core source static rules', () {
    test('main registers the licence collector before runApp', () {
      // 收集器是惰性的，忘記登記不會有任何錯誤 —— 授權頁只會少幾筆。
      final source = File('lib/main.dart').readAsStringSync();
      // 錨定掛上 `ProviderScope` 的那一次呼叫。`runApp()` 這個字串在註解裡出現
      // 過，而且 `main.dart` 現在有第二個真的呼叫 —— 啟動失敗時頂替上去的最小
      // 錯誤畫面（issue #37）。那一個排在授權登記之前是應該的：它存在的前提就
      // 是初始化沒跑完。
      final call = RegExp(
        r'^\s+runApp\(\s*ProviderScope\(',
        multiLine: true,
      ).firstMatch(source);
      expect(call, isNotNull);
      expect(
        source.substring(0, call!.start),
        contains('registerThirdPartyLicenses()'),
      );
    });

    test('image candidates scale the disk cache by height only (#107)', () {
      // 磁碟縮放同時拿到寬高時會按寬把 16:9 封面縮到不夠高（issue #107），
      // 所以候選 provider 只給 maxHeight。
      final source = File(
        'lib/core/services/image_loading_service.dart',
      ).readAsStringSync();
      final start = source.indexOf(
        'static List<ImageProvider> imageProviderCandidates(',
      );
      expect(start, greaterThanOrEqualTo(0));
      final end = source.indexOf('\n  static ', start);
      expect(end, greaterThan(start));
      final candidates = source.substring(start, end);

      expect(candidates, contains('maxHeight: request.cacheExtent'));
      expect(candidates, isNot(contains('maxWidth: request.cacheExtent')));
    });
  });
}
