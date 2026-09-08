import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/core/secure_key_value_store.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/services/account/bilibili_account_service.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/services/account/youtube_account_service.dart';
import 'package:isar_community/isar.dart';

import '../../support/fakes/fake_secure_key_value_store.dart';
import '../../support/isar_test_harness.dart';

/// 憑證儲存本身壞掉時（Android Keystore 解不開既有密文、Windows DPAPI 換了使用者
/// 設定檔），`read()` 丟的是 `PlatformException` 而不是回 `null`。
///
/// 這條路徑被 `SourceAuthContext`（串流解析 / 播放交接 / 下載 / 曲目詳情的授權閘）
/// 與兩個 Dio interceptor 使用，所以往上丟等於每一個 API 請求都變成錯誤。降級成
/// 「未登入」才是可以繼續走的答案。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Isar isar;

  setUpAll(() async {
    await initializeIsarForTests();
  });

  setUp(() async {
    AppLogger.clearLogs();
    tempDir = await Directory.systemTemp.createTemp(
      'account_secure_storage_failure_test_',
    );
    isar = await Isar.open(
      [AccountSchema],
      directory: tempDir.path,
      name: 'account_secure_storage_failure_test',
    );
  });

  tearDown(() async {
    AppLogger.clearLogs();
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('an unreadable Bilibili credential store reads as logged out', () async {
    final service = BilibiliAccountService(
      isar: isar,
      secureStorage: UnavailableSecureKeyValueStore(),
    );

    expect(await service.getAuthCookieString(), isNull);
    expect(_allLogText(), contains('Bilibili credential store unavailable'));
  });

  test('an unreadable YouTube credential store reads as logged out', () async {
    final service = YouTubeAccountService(
      isar: isar,
      secureStorage: UnavailableSecureKeyValueStore(),
    );

    expect(await service.getAuthHeaders(), isNull);
    expect(_allLogText(), contains('YouTube credential store unavailable'));
  });

  test('an unreadable Netease credential store reads as logged out', () async {
    final service = NeteaseAccountService(
      isar: isar,
      secureStorage: UnavailableSecureKeyValueStore(),
    );

    expect(await service.getAuthCookieString(), isNull);
    expect(_allLogText(), contains('Netease credential store unavailable'));
  });

  test(
    'the failure is retried rather than cached as "no credentials"',
    () async {
      final store = UnavailableSecureKeyValueStore();
      final service = NeteaseAccountService(isar: isar, secureStorage: store);

      await service.getAuthCookieString();
      await service.getAuthCookieString();

      // 一次暫時性的 Keystore 失敗不該把整個 app 生命週期釘在「未登入」。
      expect(store.readCount, 2);
    },
  );

  test('the log carries the operation and code, not the platform message', () {
    const failure = SecureStorageUnavailable('read', 'decrypt_failed');

    expect(
      failure.toString(),
      'SecureStorageUnavailable(read, code=decrypt_failed)',
    );
  });
}

String _allLogText() =>
    AppLogger.logs.map((entry) => entry.toString()).join('\n');
