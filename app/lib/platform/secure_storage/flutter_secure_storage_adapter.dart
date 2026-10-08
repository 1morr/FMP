import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';

/// 鍵允許的字元（[SecureStorage]）。
final _validKey = RegExp(r'^[a-z0-9][a-z0-9.-]*$');

/// Android 與 Windows 共用的實作：`flutter_secure_storage` 11.x。
///
/// - Android：RSA-OAEP 包 AES-GCM 的金鑰（套件預設）。`resetOnError` 關掉：
///   套件預設讀取失敗就清空，違反 ADR 0012「讀取失敗時不刪除」。
/// - Windows：值以 AES-GCM 加密存在 application support 目錄的 `.secure`
///   檔，金鑰在 Credential Manager。
///
/// dev 與 prod 分開（ADR 0015 §決定 8）：兩個平台本來就分開（applicationId、
/// ProductName），這裡再以鍵前綴（`fmp-dev.`／`fmp.`）與 Android 的
/// `storageNamespace` 保險一次。套件的呼叫從建構子注入，測試不碰平台通道。
final class FlutterSecureStorageAdapter implements SecureStorage {
  FlutterSecureStorageAdapter({
    required this._prefix,
    required this._read,
    required this._write,
    required this._delete,
    required this._readAll,
  });

  /// 以套件接上系統。
  factory FlutterSecureStorageAdapter.system(AppFlavor flavor) {
    final storage = FlutterSecureStorage(aOptions: androidOptions(flavor));
    return FlutterSecureStorageAdapter(
      prefix: _prefixOf(flavor),
      read: (key) => storage.read(key: key),
      write: (key, value) => storage.write(key: key, value: value),
      delete: (key) => storage.delete(key: key),
      readAll: storage.readAll,
    );
  }

  /// Android 的選項。測試核對 `resetOnError` 與 namespace。
  static AndroidOptions androidOptions(AppFlavor flavor) => AndroidOptions(
    resetOnError: false,
    storageNamespace: _namespaceOf(flavor),
  );

  static String _namespaceOf(AppFlavor flavor) => switch (flavor) {
    AppFlavor.dev => 'fmp-dev',
    AppFlavor.prod => 'fmp',
  };

  static String _prefixOf(AppFlavor flavor) => '${_namespaceOf(flavor)}.';

  final String _prefix;
  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final Future<void> Function(String key) _delete;
  final Future<Map<String, String>> Function() _readAll;

  String _full(String key) {
    if (!_validKey.hasMatch(key)) {
      throw ArgumentError.value(
        key,
        'key',
        'must be lowercase alphanumerics, "." and "-"',
      );
    }
    return '$_prefix$key';
  }

  @override
  Future<String?> read(String key) async => _read(_full(key));

  @override
  Future<void> write(String key, String value) async =>
      _write(_full(key), value);

  @override
  Future<void> delete(String key) async => _delete(_full(key));

  @override
  Future<void> deleteAll() async {
    for (final key in (await _readAll()).keys) {
      if (key.startsWith(_prefix)) await _delete(key);
    }
  }
}
