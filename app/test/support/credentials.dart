import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/network/auth.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';

/// 每個音源都未登入的認證來源（不碰資料庫）。
final class NoCredentials implements CredentialSource {
  const NoCredentials();

  @override
  Future<CredentialMaterial?> credentialMaterial(String pluginId) async => null;

  @override
  Future<Set<String>> credentialCookieNames(String pluginId) async => const {};

  @override
  Future<bool> browseAsLoggedIn(String pluginId) async => true;
}

/// 記憶體裡的 [SecureStorage]。鍵與平台層一樣要通過檢查，但沒有前綴。
final class InMemorySecureStorage implements SecureStorage {
  final values = <String, String>{};

  /// 非空時 [read] 拋這個（模擬 keystore 暫時讀不到）。
  Object? readError;

  /// 非空時 [write] 與 [delete] 拋這個。
  Object? writeError;

  @override
  Future<String?> read(String key) async {
    if (readError case final error?) throw error;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (writeError case final error?) throw error;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (writeError case final error?) throw error;
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async => values.clear();
}

/// 接在 [database] 與 [storage] 上的 [CredentialStore]（沒給 [storage] 就是空的
/// 記憶體存放）。
CredentialStore credentialStoreFor(
  AppDatabase database, {
  required Redactor redactor,
  required Log log,
  SecureStorage? storage,
}) => CredentialStore(
  storage: storage ?? InMemorySecureStorage(),
  accounts: AccountRepository(database),
  plugins: PluginRepository(database),
  settings: SourceSettingsRepository(database),
  redactor: redactor,
  log: log,
);
