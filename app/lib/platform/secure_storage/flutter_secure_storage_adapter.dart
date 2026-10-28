import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';

/// 鍵允許的字元（[SecureStorage]）。
final _validKey = RegExp(r'^[a-z0-9][a-z0-9.-]*$');

/// Android、Windows 與 macOS 共用的實作：`flutter_secure_storage` 11.x。
///
/// - Android：RSA-OAEP 包 AES-GCM 的金鑰（套件預設）。`resetOnError` 關掉：
///   套件預設讀取失敗就清空，違反 ADR 0012「讀取失敗時不刪除」。
/// - Windows：整份鍵值是一個 JSON，以 DPAPI（`CryptProtectData`，無 entropy）加密成
///   application support 目錄的單一檔案 `flutter_secure_storage.dat`（ADR 0029
///   決定 5 的更正）。寫入是整檔載入、改一鍵、整檔寫回；prod 與舊版 App 共用同一個檔，
///   舊鍵（無前綴）保留。套件的 `load` 解不開或 JSON 壞掉時會刪整個檔，沒有開關。
/// - macOS：傳統的登入 keychain（`usesDataProtectionKeychain: false`）。data protection
///   keychain 要 keychain-access-groups entitlement 與開發者帳號簽章；App 不開沙盒、
///   也不用開發者帳號簽（ADR 0036），所以不能用。
///
/// dev 與 prod 分開（ADR 0015 §決定 8）：各平台本來就分開（applicationId、
/// ProductName），這裡再以鍵前綴（`fmp-dev.`／`fmp.`）與 Android 的
/// `storageNamespace` 保險一次。套件的呼叫從建構子注入，測試不碰平台通道。
final class FlutterSecureStorageAdapter implements SecureStorage {
  FlutterSecureStorageAdapter({
    required this._prefix,
    required this._read,
    required this._write,
    required this._delete,
    required this._readAll,
    this._deleteWholeStore,
  });

  /// 以套件接上系統（Android、Windows）。
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

  /// 以套件接上 macOS 的登入 keychain。
  ///
  /// [deleteAll] 用套件的 `deleteAll`，不先列出鍵：登入 keychain（file-based）不接受
  /// 「全部項目＋回傳資料」的查詢（`kSecMatchLimitAll` 加 `kSecReturnData`），套件的 `readAll`
  /// 回 `-50`（errSecParam，2026-10-28 實機）。套件的 `deleteAll` 以 service（`accountName`，
  /// [macOsOptionsFor]）刪，這個 service 只有 FMP 這個 flavor 用，範圍和鍵前綴相同。
  factory FlutterSecureStorageAdapter.macos(AppFlavor flavor) {
    final storage = FlutterSecureStorage(mOptions: macOsOptionsFor(flavor));
    return FlutterSecureStorageAdapter(
      prefix: _prefixOf(flavor),
      read: (key) => storage.read(key: key),
      write: (key, value) => storage.write(key: key, value: value),
      delete: (key) => storage.delete(key: key),
      readAll: storage.readAll,
      deleteWholeStore: storage.deleteAll,
    );
  }

  /// Android 的選項。測試核對 `resetOnError` 與 namespace。
  static AndroidOptions androidOptions(AppFlavor flavor) => AndroidOptions(
    resetOnError: false,
    storageNamespace: _namespaceOf(flavor),
  );

  /// macOS 的選項。測試核對 `usesDataProtectionKeychain` 與帳號名。
  static MacOsOptions macOsOptionsFor(AppFlavor flavor) => MacOsOptions(
    usesDataProtectionKeychain: false,
    accountName: _namespaceOf(flavor),
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

  /// 有值時 [deleteAll] 直接清掉整個儲存區（它只屬於這個 flavor），不列出鍵。
  final Future<void> Function()? _deleteWholeStore;

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
    if (_deleteWholeStore case final deleteWholeStore?) {
      await deleteWholeStore();
      return;
    }
    for (final key in (await _readAll()).keys) {
      if (key.startsWith(_prefix)) await _delete(key);
    }
  }
}
