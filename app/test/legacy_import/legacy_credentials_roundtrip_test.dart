import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/legacy_import/legacy_converter.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';

import '../support/credentials.dart';
import '../support/memory_database.dart';
import 'legacy_credential_fixtures.dart';
import 'legacy_snapshot_builders.dart';

// 憑證的往返（M5 design §5.8、§9）：轉換器的結果經 `CredentialStore.writeImported` 與帳號列寫入，
// 真的 `CredentialStore` 載入後帳號與憑證成對、是登入狀態。全是假值。

void main() {
  test('imported credentials and accounts load as a logged-in pair', () async {
    final conversion = const LegacyConverter().convert(
      legacySnapshot(
        accounts: [legacyAccount(platform: 'bilibili', userId: '555')],
      ),
      source: LegacyImportSource.database,
      now: DateTime.utc(2026, 10, 23),
      credentials: legacyReads(
        bilibili: legacyBilibiliJson(),
        netease: legacyNeteaseJson(),
        // 讀不出的平台不寫帳號也不寫憑證。
        youtube: legacyYoutubeJson(sapisid: ''),
      ),
    );
    expect(conversion.bundle.accounts.map((a) => a.pluginId), [
      'bilibili',
      'netease',
    ]);

    final database = memoryDatabase();
    final accounts = AccountRepository(database);
    final storage = InMemorySecureStorage();
    for (final account in conversion.bundle.accounts) {
      await accounts.upsert(account);
    }
    for (final MapEntry(:key, :value) in conversion.credentials.entries) {
      await CredentialStore.writeImported(storage, key, value);
    }

    final store = CredentialStore(
      storage: storage,
      accounts: accounts,
      plugins: PluginRepository(database),
      settings: SourceSettingsRepository(database),
      redactor: Redactor(),
      log: Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
    );
    addTearDown(store.dispose);
    await store.ready;

    for (final id in ['bilibili', 'netease']) {
      expect(await store.state(id), CredentialState.active, reason: id);
      expect(
        await store.activeCredentials(id),
        conversion.credentials[id],
        reason: id,
      );
      // 載入時沒有把任何一半刪掉。
      expect(await accounts.byId(id), isNotNull, reason: id);
    }
    expect(await store.state('youtube'), CredentialState.none);
    expect(await accounts.byId('youtube'), isNull);
    expect(storage.values.keys, {
      'credentials.bilibili',
      'credentials.netease',
    });
  });

  test('writeImported stores the same JSON as save', () async {
    final conversion = const LegacyConverter().convert(
      legacySnapshot(),
      source: LegacyImportSource.database,
      now: DateTime.utc(2026, 10, 23),
      credentials: legacyReads(bilibili: legacyBilibiliJson()),
    );
    final credentials = conversion.credentials['bilibili']!;

    final imported = InMemorySecureStorage();
    await CredentialStore.writeImported(imported, 'bilibili', credentials);

    final database = memoryDatabase();
    final saved = InMemorySecureStorage();
    final store = CredentialStore(
      storage: saved,
      accounts: AccountRepository(database),
      plugins: PluginRepository(database),
      settings: SourceSettingsRepository(database),
      redactor: Redactor(),
      log: Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
    );
    addTearDown(store.dispose);
    await store.save(conversion.bundle.accounts.single, credentials);

    expect(imported.values, saved.values);
    expect(
      jsonDecode(imported.values['credentials.bilibili']!),
      credentials.toJson(),
    );
  });
}
