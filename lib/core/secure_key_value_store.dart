import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 平台憑證儲存本身無法存取。
///
/// 這與「沒有存過東西」是兩件事：`read` 回 `null` 代表沒有憑證，這個例外代表
/// 憑證可能存在但讀不出來。Android 的 Keystore 在裝置備份還原、系統更新或
/// Keystore 損毀之後可能解不開既有密文；Windows 的 DPAPI 密文綁在使用者設定檔
/// 上，設定檔重建或資料被搬到另一個帳號之後就解不開。
///
/// 兩者必須分開：把存取失敗當成「未登入」，使用者會看到 app 壞掉的樣子而不是
/// 一個可解釋的狀態。
class SecureStorageUnavailable implements Exception {
  const SecureStorageUnavailable(this.operation, this.code);

  /// `read` / `write` / `delete`。
  final String operation;

  /// 平台回報的錯誤碼。**只帶碼不帶 message** —— 平台訊息可能夾帶金鑰別名或
  /// 檔案路徑，而 `AppLogger` 的規則是憑證相關失敗只寫固定的消毒訊息。
  final String? code;

  @override
  String toString() =>
      'SecureStorageUnavailable($operation'
      '${code == null ? '' : ', code=$code'})';
}

/// 憑證儲存的窄介面。
///
/// 存在的理由有兩個：測試不必碰平台通道，以及所有平台例外都在一個地方轉成
/// [SecureStorageUnavailable]，不會有哪個呼叫端漏接。
abstract class SecureKeyValueStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) =>
      _guard('read', () => _storage.read(key: key));

  @override
  Future<void> write({required String key, required String value}) {
    return _guard('write', () => _storage.write(key: key, value: value));
  }

  @override
  Future<void> delete({required String key}) =>
      _guard('delete', () => _storage.delete(key: key));

  Future<T> _guard<T>(String operation, Future<T> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (error) {
      throw SecureStorageUnavailable(operation, error.code);
    } on MissingPluginException {
      throw SecureStorageUnavailable(operation, 'missing_plugin');
    }
  }
}
