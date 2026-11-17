import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fmp/app/i18n/plural_rules.dart';

import 'support/no_network.dart';

/// `test/` 底下每個測試都零聯網（architecture〈測試策略〉）。先初始化 binding，再裝防線，
/// 並設好和 `main` 一樣的複數規則。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();
  configurePluralRules();
  await testMain();
}
