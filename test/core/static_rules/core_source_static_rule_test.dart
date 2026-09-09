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
      // 用縮排錨定真正的呼叫；`runApp()` 這個字串在註解裡也出現過。
      final call = RegExp(r'^\s+runApp\(', multiLine: true).firstMatch(source);
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
