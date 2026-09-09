import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// 讓 `flutter_secure_storage` 的平台通道照 [values] 回答，或整條失敗。
///
/// 用通道而不是 `FlutterSecureStorage.setMockInitialValues`：後者換掉的是
/// `FlutterSecureStoragePlatform.instance` 這個全域欄位而且不會還原，同一個檔案
/// 裡先跑過它的測試會讓後面每一條的通道 mock 都被繞過 —— 症狀是「注入的失敗沒
/// 有發生」，看起來像產品碼把例外吞了。
///
/// 走真的通道還有一個好處：`FlutterSecureKeyValueStore` 把 `PlatformException`
/// 翻成 `SecureStorageUnavailable` 的那一段也一起驗到。
void mockSecureStorageChannel({
  Map<String, String> values = const {},
  bool failing = false,
}) {
  final store = Map<String, String>.from(values);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        if (failing) {
          throw PlatformException(code: 'decrypt_failed');
        }
        final arguments = (call.arguments as Map?) ?? const {};
        final key = arguments['key'] as String?;
        switch (call.method) {
          case 'read':
            return store[key];
          case 'readAll':
            return store;
          case 'containsKey':
            return store.containsKey(key);
          case 'write':
            store[key!] = arguments['value'] as String;
            return null;
          case 'delete':
            store.remove(key);
            return null;
          case 'deleteAll':
            store.clear();
            return null;
          default:
            return null;
        }
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });
}
