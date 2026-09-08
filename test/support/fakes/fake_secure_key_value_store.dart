import 'package:fmp/core/secure_key_value_store.dart';

/// 記憶體版的憑證儲存。
class MemorySecureKeyValueStore implements SecureKeyValueStore {
  MemorySecureKeyValueStore([Map<String, String>? initialValues])
    : values = Map<String, String>.from(initialValues ?? const {});

  final Map<String, String> values;

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

/// 每次操作都以 [SecureStorageUnavailable] 失敗的憑證儲存。
///
/// 模擬 Android Keystore 解不開既有密文、或 Windows DPAPI 換了使用者設定檔的
/// 情形 —— 那些在平台層是 `PlatformException`，不是回 `null`。
class UnavailableSecureKeyValueStore implements SecureKeyValueStore {
  UnavailableSecureKeyValueStore({this.code = 'decrypt_failed'});

  final String code;

  /// 被呼叫過幾次，讓測試能斷言「失敗之後沒有被當成已載入而不再重試」。
  int readCount = 0;

  @override
  Future<String?> read({required String key}) async {
    readCount++;
    throw SecureStorageUnavailable('read', code);
  }

  @override
  Future<void> write({required String key, required String value}) async {
    throw SecureStorageUnavailable('write', code);
  }

  @override
  Future<void> delete({required String key}) async {
    throw SecureStorageUnavailable('delete', code);
  }
}
