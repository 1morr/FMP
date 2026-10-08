import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/secure_storage/flutter_secure_storage_adapter.dart';
import 'package:integration_test/integration_test.dart';

// 平台的 secure storage 真的能寫、讀、刪，`deleteAll` 只刪自己前綴的鍵
// （design §6.1）。只用假值；只在 dev 跑，`deleteAll` 不能碰 prod 的憑證。
//
//   flutter test integration_test/secure_storage_test.dart -d windows
//   flutter test integration_test/secure_storage_test.dart -d <模擬器>
//
// Windows 另外確認 dev 的 `.secure` 檔在 dev 的 application support 目錄
// （%APPDATA%\<公司>\fmp-dev\），不在 prod 的目錄。

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('writes, reads and deletes; deleteAll keeps foreign keys', (
    tester,
  ) async {
    final flavor = AppFlavor.parse(appFlavor);
    expect(flavor, AppFlavor.dev, reason: 'deleteAll must not touch prod');
    final storage = FlutterSecureStorageAdapter.system(flavor);
    // 另一個前綴的鍵：直接用套件寫，`deleteAll` 不能動它。
    const foreignKey = 'fmp-integration-foreign.value';
    // 套件的 Android 選項與 App 一致，免得換了 namespace 看不到同一份資料。
    final rawStorage = FlutterSecureStorage(
      aOptions: FlutterSecureStorageAdapter.androidOptions(flavor),
    );
    addTearDown(() async {
      await storage.deleteAll();
      await rawStorage.delete(key: foreignKey);
    });

    expect(await storage.read('credentials.integration-test'), isNull);

    await storage.write('credentials.integration-test', 'FAKE_VALUE_1234');
    await storage.write('credentials.integration-other', 'FAKE_VALUE_5678');
    expect(
      await storage.read('credentials.integration-test'),
      'FAKE_VALUE_1234',
    );

    // 覆寫。
    await storage.write('credentials.integration-test', 'FAKE_VALUE_9999');
    expect(
      await storage.read('credentials.integration-test'),
      'FAKE_VALUE_9999',
    );

    await storage.delete('credentials.integration-test');
    expect(await storage.read('credentials.integration-test'), isNull);
    expect(
      await storage.read('credentials.integration-other'),
      'FAKE_VALUE_5678',
    );

    await rawStorage.write(key: foreignKey, value: 'FAKE_FOREIGN_1234');
    await storage.deleteAll();
    expect(await storage.read('credentials.integration-other'), isNull);
    expect(await rawStorage.read(key: foreignKey), 'FAKE_FOREIGN_1234');
  });
}
