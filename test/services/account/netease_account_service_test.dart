import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/account/account_service.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NeteaseAccountService login validation', () {
    late Directory tempDir;
    late Isar isar;
    late Map<String, String> secureStorageData;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'netease_account_service_test_',
      );
      isar = await Isar.open(
        [AccountSchema],
        directory: tempDir.path,
        name: 'netease_account_service_test',
      );
      secureStorageData = <String, String>{};
      FlutterSecureStorage.setMockInitialValues(secureStorageData);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('pollQrCodeStatus fails when success response has no MUSIC_U cookie',
        () async {
      final service = _FakeNeteaseAccountService(
        isar: isar,
        nextStatus: const AccountCheckResult(status: AccountStatus.valid),
      )
        ..pollResponseData = {'code': 803}
        ..pollSetCookieHeaders = ['__csrf=csrf; Path=/'];

      final result = await service.pollQrCodeStatus('unikey').first;

      expect(result.code, 800);
      expect(result.message, 'Missing login cookies');
      expect(await service.isLoggedIn(), isFalse);
      expect(await service.getAuthCookieString(), isNull);
    });

    test('returns false and clears new login state when validation is invalid',
        () async {
      final service = _FakeNeteaseAccountService(
        isar: isar,
        nextStatus: const AccountCheckResult(status: AccountStatus.invalid),
      );

      final success = await service.loginWithCookiesAndValidate(
        musicU: 'music-u',
        csrf: 'csrf',
      );

      expect(success, isFalse);
      expect(await service.isLoggedIn(), isFalse);
      expect(await service.getAuthCookieString(), isNull);
      final account = await service.getCurrentAccount();
      expect(account, isNull);
      expect(secureStorageData, isEmpty);
    });

    test(
        'returns true and keeps logged-in account state when validation passes',
        () async {
      final service = _FakeNeteaseAccountService(
        isar: isar,
        nextStatus: const AccountCheckResult(status: AccountStatus.valid),
        validatedUserId: '12345',
        validatedUserName: 'Netease User',
        validatedAvatarUrl: 'https://example.com/avatar.png',
        validatedIsVip: true,
      );

      final success = await service.loginWithCookiesAndValidate(
        musicU: 'music-u',
        csrf: 'csrf',
      );

      expect(success, isTrue);
      expect(await service.isLoggedIn(), isTrue);
      final account = await service.getCurrentAccount();
      expect(account, isNotNull);
      expect(account!.isLoggedIn, isTrue);
      expect(account.userId, '12345');
      expect(account.userName, 'Netease User');
      expect(account.avatarUrl, 'https://example.com/avatar.png');
      expect(account.isVip, isTrue);
      expect(account.loginAt, isNotNull);

      final cookieString = await service.getAuthCookieString();
      expect(cookieString, contains('MUSIC_U=music-u'));
      expect(cookieString, contains('__csrf=csrf'));

      final storedJson = secureStorageData[_storageKey];
      expect(storedJson, isNotNull);
      final stored = jsonDecode(storedJson!) as Map<String, dynamic>;
      expect(stored['musicU'], 'music-u');
      expect(stored['csrf'], 'csrf');
      expect(stored['userId'], '12345');
    });

    test('restores previous logged-in account when new validation is invalid',
        () async {
      final service = _FakeNeteaseAccountService(
        isar: isar,
        nextStatus: const AccountCheckResult(status: AccountStatus.valid),
        validatedUserId: 'existing-id',
        validatedUserName: 'Existing User',
      );

      final firstLogin = await service.loginWithCookiesAndValidate(
        musicU: 'existing-music-u',
        csrf: 'existing-csrf',
      );
      expect(firstLogin, isTrue);

      service.nextStatus =
          const AccountCheckResult(status: AccountStatus.invalid);
      service.validatedUserId = null;
      service.validatedUserName = null;
      service.validatedAvatarUrl = null;
      service.validatedIsVip = false;

      final secondLogin = await service.loginWithCookiesAndValidate(
        musicU: 'new-music-u',
        csrf: 'new-csrf',
      );

      expect(secondLogin, isFalse);
      expect(await service.isLoggedIn(), isTrue);
      final account = await service.getCurrentAccount();
      expect(account, isNotNull);
      expect(account!.isLoggedIn, isTrue);
      expect(account.userId, 'existing-id');
      expect(account.userName, 'Existing User');

      final cookieString = await service.getAuthCookieString();
      expect(cookieString, contains('MUSIC_U=existing-music-u'));
      expect(cookieString, contains('__csrf=existing-csrf'));
      expect(cookieString, isNot(contains('new-music-u')));
    });
  });
}

class _FakeNeteaseAccountService extends NeteaseAccountService {
  _FakeNeteaseAccountService({
    required super.isar,
    required this.nextStatus,
    this.validatedUserId,
    this.validatedUserName,
    this.validatedAvatarUrl,
    this.validatedIsVip = false,
  }) : _isar = isar;

  final Isar _isar;
  AccountCheckResult nextStatus;
  String? validatedUserId;
  String? validatedUserName;
  String? validatedAvatarUrl;
  bool validatedIsVip;
  Map<String, dynamic>? pollResponseData;
  List<String>? pollSetCookieHeaders;

  @override
  Future<AccountCheckResult> checkAccountStatus() async {
    if (nextStatus.status == AccountStatus.valid) {
      await _isar.writeTxn(() async {
        final existing = await _isar.accounts
            .filter()
            .platformEqualTo(SourceType.netease)
            .findFirst();
        final account = existing ?? (Account()..platform = SourceType.netease);
        account.isLoggedIn = true;
        account.userId = validatedUserId;
        account.userName = validatedUserName;
        account.avatarUrl = validatedAvatarUrl;
        account.isVip = validatedIsVip;
        account.lastRefreshed = DateTime.now();
        await _isar.accounts.put(account);
      });
    }

    return nextStatus;
  }

  @override
  Dio get dio {
    if (pollResponseData == null) {
      return super.dio;
    }

    final dio = Dio();
    dio.httpClientAdapter = _FakeHttpClientAdapter(
      data: pollResponseData!,
      setCookieHeaders: pollSetCookieHeaders ?? const [],
    );
    return dio;
  }
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter({
    required this.data,
    required this.setCookieHeaders,
  });

  final Map<String, dynamic> data;
  final List<String> setCookieHeaders;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = utf8.encode(jsonEncode(data));
    return ResponseBody.fromBytes(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (setCookieHeaders.isNotEmpty) 'set-cookie': setCookieHeaders,
      },
    );
  }
}

const _storageKey = 'account_netease_credentials';

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
