import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 憑證存放（ADR 0012 §決定 3、ADR 0029 §決定 5）：平台的 secure storage。
///
/// 鍵只准小寫英數、`.`、`-`，其他拋 [ArgumentError]：Windows 的實作直接把鍵當
/// `<鍵>.secure` 的檔名，不做跳脫。讀寫失敗丟平台套件的原始例外，呼叫端
/// （`CredentialStore`）自己決定怎麼處理，這一層不吞也不刪資料。
abstract interface class SecureStorage {
  /// [key] 的值；沒有時回 `null`。
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  /// 沒有這個鍵時什麼都不做。
  Future<void> delete(String key);

  /// 只刪這個 [SecureStorage] 自己前綴的鍵，不動別人的（不呼叫套件的全刪）。
  Future<void> deleteAll();
}

/// 平台的 secure storage。`main()` 以 `AppPlatform.secureStorage` override；
/// 沒 override 就讀會拋錯。
final secureStorageProvider = Provider<SecureStorage>(
  (ref) => throw UnimplementedError(
    'secureStorageProvider is overridden by main() with the platform '
    'implementation',
  ),
);
