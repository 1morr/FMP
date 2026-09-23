/// `lib/core/` 裡兩條只有讀源碼才驗得到的規則。
///
/// 授權登記那條原本藏在 `third_party_licenses_test.dart` 裡，從檔名看不出它在
/// grep 源碼。#107 那條原本混在播放頁的結構規則裡，跟著那些結構斷言一起被砍時
/// 留了下來 —— 它守的是一個修過的 bug，不是版面。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/dart_source.dart';

/// 錨定掛上 `ProviderScope` 的那一次 `runApp`。`main.dart` 還有第二個真的呼叫
/// —— 啟動失敗時頂替上去的最小錯誤畫面（issue #37）；那一個排在授權登記之前
/// 是應該的：它存在的前提就是初始化沒跑完。
final _scopedRunApp = RegExp(r'\brunApp\(\s*ProviderScope\(');

/// `registerThirdPartyLicenses()` 在（去掉註解後的）第一個 scoped `runApp` 之前。
bool registersLicencesBeforeRunApp(String source) {
  final code = stripDartComments(source);
  final call = _scopedRunApp.firstMatch(code);
  if (call == null) return false;
  return code.substring(0, call.start).contains('registerThirdPartyLicenses()');
}

void main() {
  group('core source static rules', () {
    test('main registers the licence collector before runApp', () {
      // 收集器是惰性的，忘記登記不會有任何錯誤 —— 授權頁只會少幾筆。
      expect(
        registersLicencesBeforeRunApp(File('lib/main.dart').readAsStringSync()),
        isTrue,
      );
    });

    test('registering after runApp, or only in a comment, is red', () {
      const after = '''
void main() {
  runApp(ProviderScope(child: FMPApp()));
  registerThirdPartyLicenses();
}
''';
      const commentedOut = '''
void main() {
  // registerThirdPartyLicenses();
  runApp(ProviderScope(child: FMPApp()));
}
''';
      const noScopedRunApp = '''
void main() {
  registerThirdPartyLicenses();
  runApp(const StartupFailureApp());
}
''';

      expect(registersLicencesBeforeRunApp(after), isFalse);
      expect(registersLicencesBeforeRunApp(commentedOut), isFalse);
      expect(registersLicencesBeforeRunApp(noScopedRunApp), isFalse);
    });

    test('comments, blank lines and a failure-screen runApp do not matter', () {
      const reformatted = '''
void main() {
  // 啟動失敗時先頂一個最小畫面：runApp(ProviderScope(...)) 在後面。
  if (failed) {
    runApp(const StartupFailureApp());
    return;
  }

  registerThirdPartyLicenses();

  /* 初始化完成 */
  runApp(
    ProviderScope(
      child: FMPApp(),
    ),
  );
}
''';

      expect(registersLicencesBeforeRunApp(reformatted), isTrue);
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
