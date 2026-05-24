import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/services/account/bilibili_account_service.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/services/account/youtube_account_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Isar isar;
  late Map<String, String> secureStorageData;

  setUpAll(() async {
    await Isar.initializeIsarCore(
      libraries: {Abi.current(): await _resolveIsarLibraryPath()},
    );
  });

  setUp(() async {
    AppLogger.clearLogs();
    tempDir = await Directory.systemTemp.createTemp(
      'account_credentials_redaction_test_',
    );
    isar = await Isar.open(
      [AccountSchema],
      directory: tempDir.path,
      name: 'account_credentials_redaction_test',
    );
    secureStorageData = <String, String>{};
    FlutterSecureStorage.setMockInitialValues(secureStorageData);
  });

  tearDown(() async {
    AppLogger.clearLogs();
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('malformed stored Bilibili credentials do not leak token text to logs',
      () async {
    const sentinel = 'bilibili-secret-sessdata';
    secureStorageData[_bilibiliStorageKey] = '{"SESSDATA":"$sentinel",';
    FlutterSecureStorage.setMockInitialValues(secureStorageData);

    final service = BilibiliAccountService(isar: isar);

    expect(await service.getAuthCookieString(), isNull);
    expect(_allLogText(), isNot(contains(sentinel)));
    expect(secureStorageData.containsKey(_bilibiliStorageKey), isFalse);
  });

  test('malformed stored YouTube credentials do not leak token text to logs',
      () async {
    const sentinel = 'youtube-secret-sapisid';
    secureStorageData[_youtubeStorageKey] = '{"SAPISID":"$sentinel",';
    FlutterSecureStorage.setMockInitialValues(secureStorageData);

    final service = YouTubeAccountService(isar: isar);

    expect(await service.getAuthHeaders(), isNull);
    expect(_allLogText(), isNot(contains(sentinel)));
    expect(secureStorageData.containsKey(_youtubeStorageKey), isFalse);
  });

  test('malformed stored Netease credentials do not leak token text to logs',
      () async {
    const sentinel = 'netease-secret-music-u';
    secureStorageData[_neteaseStorageKey] = '{"musicU":"$sentinel",';
    FlutterSecureStorage.setMockInitialValues(secureStorageData);

    final service = NeteaseAccountService(isar: isar);

    expect(await service.getAuthCookieString(), isNull);
    expect(_allLogText(), isNot(contains(sentinel)));
    expect(secureStorageData.containsKey(_neteaseStorageKey), isFalse);
  });

  test('AppLogger redacts complete auth header values', () {
    const sentinel = 'token.tail.must.not.leak';

    final redacted = AppLogger.redactSensitive(
      'Authorization: Bearer $sentinel\n'
      'Authorization=SAPISIDHASH 123_$sentinel\n'
      'Cookie: MUSIC_U=$sentinel; SID=$sentinel',
    );

    expect(redacted, isNot(contains(sentinel)));
    expect(redacted, contains('Authorization: [REDACTED]'));
    expect(redacted, contains('Authorization=[REDACTED]'));
    expect(redacted, contains('Cookie: [REDACTED]'));
  });
}

String _allLogText() {
  return AppLogger.logs
      .map((entry) => '${entry.message}\n${entry.error ?? ''}')
      .join('\n');
}

const _bilibiliStorageKey = 'account_bilibili_credentials';
const _youtubeStorageKey = 'account_youtube_credentials';
const _neteaseStorageKey = 'account_netease_credentials';

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  final packageConfig = jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_flutter_libs') {
      continue;
    }
    final packageDir = Directory(
      packageConfigDir.uri.resolve(package['rootUri'] as String).toFilePath(),
    );
    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}
