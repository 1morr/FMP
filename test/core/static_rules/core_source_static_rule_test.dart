/// `lib/core/` 裡兩條只有讀源碼才驗得到的規則。
///
/// 兩條原本各自藏在一支行為測試裡（`third_party_licenses_test.dart` 與
/// `thumbnail_url_utils_test.dart`），從檔名看不出它們在 grep 源碼。
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

    test('ThumbnailUrlUtils documents itself as a single-URL helper', () {
      // 它只換一個 URL，不做退回載入。呼叫端誤以為它會退回就會少一層保護。
      final content = File(
        'lib/core/utils/thumbnail_url_utils.dart',
      ).readAsStringSync();

      expect(content, contains('single URL consumer'));
      expect(content, contains('does not perform fallback loading'));
    });
  });
}
