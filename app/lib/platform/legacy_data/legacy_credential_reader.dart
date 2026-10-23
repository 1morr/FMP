import 'package:flutter/foundation.dart';

/// 舊版 secure storage 裡一個鍵的讀取結果。值是秘密：[toString] 不印內容。
@immutable
sealed class LegacyCredentialRead {
  const LegacyCredentialRead();

  /// log 用的結果類別名稱（不用 `runtimeType`：release 混淆後會變）。
  String get label => switch (this) {
    LegacyCredentialFound() => 'found',
    LegacyCredentialMissing() => 'missing',
    LegacyCredentialUnreadable() => 'unreadable',
  };
}

/// 有值（字串，舊版存的是 JSON）。
final class LegacyCredentialFound extends LegacyCredentialRead {
  const LegacyCredentialFound(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is LegacyCredentialFound && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'LegacyCredentialFound';
}

/// 舊版沒存過這個鍵（或根本沒有舊資料）。
final class LegacyCredentialMissing extends LegacyCredentialRead {
  const LegacyCredentialMissing();

  @override
  String toString() => 'LegacyCredentialMissing';
}

/// 有舊資料但讀不出來（解密失敗、檔案壞掉、金鑰遺失）。匯入端把該平台標為需要重新登入。
final class LegacyCredentialUnreadable extends LegacyCredentialRead {
  const LegacyCredentialUnreadable();

  @override
  String toString() => 'LegacyCredentialUnreadable';
}

/// 唯讀讀出舊版（`flutter_secure_storage` 10.x）存的憑證（M5 design §0.1、§4.3）。
///
/// 不經套件的預設路徑：Windows 的套件在解不開時會刪整個檔案，Android 的預設選項
/// （`resetOnError: true`）會刪鍵，所以各平台的實作都只讀、不寫、不刪。舊鍵名的字面值只寫在
/// `lib/legacy_import/`，由呼叫端傳入。
abstract interface class LegacyCredentialReader {
  /// 回傳的 map 對 [keys] 的每個鍵都有一項。讀不出就是 [LegacyCredentialUnreadable]，
  /// 不拋例外。log 只寫鍵名與結果類別，不寫值。
  Future<Map<String, LegacyCredentialRead>> read(List<String> keys);
}

/// 沒有舊資料可讀的平台（Linux、macOS、iOS，以及 dev 的 Android）。
final class NoLegacyCredentialReader implements LegacyCredentialReader {
  const NoLegacyCredentialReader();

  @override
  Future<Map<String, LegacyCredentialRead>> read(List<String> keys) async => {
    for (final key in keys) key: const LegacyCredentialMissing(),
  };
}
