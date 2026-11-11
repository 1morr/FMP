import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/no_network.dart';

/// `test/` 底下每個測試都零聯網（plan §3）。先初始化 binding，再裝防線。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();
  await testMain();
}
