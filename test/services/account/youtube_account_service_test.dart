import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/services/account/youtube_account_service.dart';
import 'package:fmp/services/account/youtube_credentials.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YouTubeAccountService auth headers', () {
    late Directory tempDir;
    late Isar isar;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'youtube_account_service_test_',
      );
      isar = await Isar.open(
        [AccountSchema],
        directory: tempDir.path,
        name: 'youtube_account_service_test',
      );
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('getAuthHeaders returns cookie and authorization without LOGIN_INFO',
        () async {
      final loginService = YouTubeAccountService(isar: isar);

      await loginService.loginWithCookies({
        'SAPISID': 'sapisid',
        '__Secure-1PSID': '1psid',
        '__Secure-3PSID': '3psid',
      });

      final service = YouTubeAccountService(isar: isar);
      final headers = await service.getAuthHeaders();

      expect(headers, isNotNull);
      expect(headers!['Cookie'], contains('SAPISID=sapisid'));
      expect(headers['Cookie'], contains('__Secure-1PSID=1psid'));
      expect(headers['Cookie'], contains('__Secure-3PSID=3psid'));
      expect(headers['Cookie'], isNot(contains('LOGIN_INFO=')));
      expect(headers['Authorization'], startsWith('SAPISIDHASH '));
    });
  });

  group('YouTubeAccountService.getMissingRequiredCookies', () {
    test('returns all missing required cookies', () {
      final missing = YouTubeAccountService.getMissingRequiredCookies({
        'SAPISID': 'sapisid',
      });

      expect(missing, equals(['__Secure-1PSID', '__Secure-3PSID']));
    });

    test('returns empty list when all required cookies exist', () {
      final missing = YouTubeAccountService.getMissingRequiredCookies({
        'SAPISID': 'sapisid',
        '__Secure-1PSID': '1psid',
        '__Secure-3PSID': '3psid',
        'LOGIN_INFO': 'login-info',
      });

      expect(missing, isEmpty);
    });

    test('does not require LOGIN_INFO for playback auth cookies', () {
      final missing = YouTubeAccountService.getMissingRequiredCookies({
        'SAPISID': 'sapisid',
        '__Secure-1PSID': '1psid',
        '__Secure-3PSID': '3psid',
      });

      expect(missing, isEmpty);
    });
  });

  group('YouTubeCredentials.isValid', () {
    test('returns true when LOGIN_INFO is missing', () {
      final credentials = YouTubeCredentials(
        sid: '',
        hsid: '',
        ssid: '',
        apisid: '',
        sapisid: 'sapisid',
        secure1Psid: '1psid',
        secure3Psid: '3psid',
        secure1Papisid: '',
        secure3Papisid: '',
        loginInfo: '',
        savedAt: DateTime(2026),
      );

      expect(credentials.isValid, isTrue);
    });

    test('returns false when __Secure-1PSID is missing', () {
      final credentials = YouTubeCredentials(
        sid: '',
        hsid: '',
        ssid: '',
        apisid: '',
        sapisid: 'sapisid',
        secure1Psid: '',
        secure3Psid: '3psid',
        secure1Papisid: '',
        secure3Papisid: '',
        loginInfo: '',
        savedAt: DateTime(2026),
      );

      expect(credentials.isValid, isFalse);
    });

    test('returns true when all required cookies exist', () {
      final credentials = YouTubeCredentials(
        sid: '',
        hsid: '',
        ssid: '',
        apisid: '',
        sapisid: 'sapisid',
        secure1Psid: '1psid',
        secure3Psid: '3psid',
        secure1Papisid: '',
        secure3Papisid: '',
        loginInfo: 'login-info',
        savedAt: DateTime(2026),
      );

      expect(credentials.isValid, isTrue);
    });
  });

  group('YouTubeCredentials.toCookieString', () {
    test('omits empty optional cookies', () {
      final credentials = YouTubeCredentials(
        sid: '',
        hsid: '',
        ssid: '',
        apisid: '',
        sapisid: 'sapisid',
        secure1Psid: '1psid',
        secure3Psid: '3psid',
        secure1Papisid: '',
        secure3Papisid: '',
        loginInfo: '',
        savedAt: DateTime(2026),
      );

      expect(credentials.toCookieString(), contains('SAPISID=sapisid'));
      expect(credentials.toCookieString(), contains('__Secure-1PSID=1psid'));
      expect(credentials.toCookieString(), contains('__Secure-3PSID=3psid'));
      expect(credentials.toCookieString(), isNot(contains('LOGIN_INFO=')));
    });
  });
}

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
