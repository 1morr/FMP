import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/services/account/bilibili_account_service.dart';
import 'package:fmp/services/account/bilibili_auth_interceptor.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/services/account/netease_auth_interceptor.dart';
import 'package:fmp/services/account/youtube_account_service.dart';
import 'package:isar_community/isar.dart';

import '../../support/fakes/fake_secure_key_value_store.dart';
import '../../support/isar_test_harness.dart';

/// 憑證失效走的是「標記」而不是「登出」。
///
/// 兩者都會清掉 secure storage 裡的憑證 —— 失效的 cookie 再附到請求上只會換來
/// 同一個錯誤 —— 差別在帳號列：登出刪列，失效保留列並把 `sessionExpired` 設為
/// true，帳號頁才有辦法把「從沒登入過」和「登入過期了」分開呈現（#92 / #93）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Isar isar;
  late MemorySecureKeyValueStore secureStorage;
  late AccountRepository accounts;

  setUpAll(() async {
    await initializeIsarForTests();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'account_session_expiry_test_',
    );
    isar = await Isar.open(
      [AccountSchema],
      directory: tempDir.path,
      name: 'account_session_expiry_test',
    );
    secureStorage = MemorySecureKeyValueStore();
    accounts = AccountRepository(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> giveAccountAProfile(String platform) {
    return accounts.upsert(
      platform,
      userName: 'Signed-in User',
      avatarUrl: 'https://example.com/avatar.png',
    );
  }

  group('Bilibili', () {
    Future<BilibiliAccountService> loggedInService() async {
      final service = BilibiliAccountService(
        isar: isar,
        secureStorage: secureStorage,
      );
      await service.loginWithCookies(
        sessdata: 'sessdata',
        biliJct: 'bili-jct',
        dedeUserId: '42',
        dedeUserIdCkMd5: 'ckmd5',
        refreshToken: 'refresh-token',
      );
      await giveAccountAProfile(SourceIds.bilibili);
      return service;
    }

    test(
      'markSessionExpired keeps the row and clears the credential',
      () async {
        final service = await loggedInService();

        await service.markSessionExpired();

        final account = await service.getCurrentAccount();
        expect(account, isNotNull);
        expect(account!.sessionExpired, isTrue);
        expect(account.isLoggedIn, isFalse);
        expect(account.userName, 'Signed-in User');
        expect(account.avatarUrl, 'https://example.com/avatar.png');
        expect(secureStorage.values, isEmpty);
        expect(await service.getAuthCookieString(), isNull);
      },
    );

    test('logout deletes the row', () async {
      final service = await loggedInService();

      await service.logout();

      expect(await service.getCurrentAccount(), isNull);
      expect(secureStorage.values, isEmpty);
    });

    test('a later login clears the expired flag', () async {
      final service = await loggedInService();
      await service.markSessionExpired();

      await service.loginWithCookies(
        sessdata: 'new-sessdata',
        biliJct: 'new-bili-jct',
        dedeUserId: '42',
        dedeUserIdCkMd5: 'ckmd5',
        refreshToken: 'refresh-token',
      );

      final account = await service.getCurrentAccount();
      expect(account!.sessionExpired, isFalse);
      expect(account.isLoggedIn, isTrue);
    });

    test('a -101 the refresh cannot fix marks the session expired', () async {
      final service = _NonRefreshingBilibiliAccountService(
        isar: isar,
        secureStorage: secureStorage,
      );
      await service.loginWithCookies(
        sessdata: 'sessdata',
        biliJct: 'bili-jct',
        dedeUserId: '42',
        dedeUserIdCkMd5: 'ckmd5',
        refreshToken: 'refresh-token',
      );
      await giveAccountAProfile(SourceIds.bilibili);

      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter({'code': -101})
        ..interceptors.add(BilibiliAuthInterceptor(service));
      await dio.get('https://api.bilibili.com/x/web-interface/nav');

      final account = await service.getCurrentAccount();
      expect(account, isNotNull);
      expect(account!.sessionExpired, isTrue);
      expect(account.isLoggedIn, isFalse);
      expect(account.userName, 'Signed-in User');
      expect(secureStorage.values, isEmpty);
    });
  });

  group('YouTube', () {
    Future<YouTubeAccountService> loggedInService() async {
      final service = YouTubeAccountService(
        isar: isar,
        secureStorage: secureStorage,
      );
      await service.loginWithCookies({
        'SAPISID': 'sapisid',
        '__Secure-1PSID': '1psid',
        '__Secure-3PSID': '3psid',
      });
      await giveAccountAProfile(SourceIds.youtube);
      return service;
    }

    test(
      'markSessionExpired keeps the row and clears the credential',
      () async {
        final service = await loggedInService();

        await service.markSessionExpired();

        final account = await service.getCurrentAccount();
        expect(account, isNotNull);
        expect(account!.sessionExpired, isTrue);
        expect(account.isLoggedIn, isFalse);
        expect(account.userName, 'Signed-in User');
        expect(secureStorage.values, isEmpty);
        expect(await service.getAuthHeaders(), isNull);
      },
    );

    test('logout deletes the row', () async {
      final service = await loggedInService();

      await service.logout();

      expect(await service.getCurrentAccount(), isNull);
      expect(secureStorage.values, isEmpty);
    });

    test('a later login clears the expired flag', () async {
      final service = await loggedInService();
      await service.markSessionExpired();

      await service.loginWithCookies({
        'SAPISID': 'sapisid',
        '__Secure-1PSID': '1psid',
        '__Secure-3PSID': '3psid',
      });

      final account = await service.getCurrentAccount();
      expect(account!.sessionExpired, isFalse);
      expect(account.isLoggedIn, isTrue);
    });
  });

  group('Netease', () {
    Future<NeteaseAccountService> loggedInService() async {
      final service = NeteaseAccountService(
        isar: isar,
        secureStorage: secureStorage,
      );
      await service.loginWithCookies(musicU: 'music-u', csrf: 'csrf');
      await giveAccountAProfile(SourceIds.netease);
      return service;
    }

    test(
      'markSessionExpired keeps the row and clears the credential',
      () async {
        final service = await loggedInService();

        await service.markSessionExpired();

        final account = await service.getCurrentAccount();
        expect(account, isNotNull);
        expect(account!.sessionExpired, isTrue);
        expect(account.isLoggedIn, isFalse);
        expect(account.userName, 'Signed-in User');
        expect(secureStorage.values, isEmpty);
        expect(await service.getAuthCookieString(), isNull);
      },
    );

    test('logout deletes the row', () async {
      final service = await loggedInService();

      await service.logout();

      expect(await service.getCurrentAccount(), isNull);
      expect(secureStorage.values, isEmpty);
    });

    test('a later login clears the expired flag', () async {
      final service = await loggedInService();
      await service.markSessionExpired();

      await service.loginWithCookies(musicU: 'music-u', csrf: 'csrf');

      final account = await service.getCurrentAccount();
      expect(account!.sessionExpired, isFalse);
      expect(account.isLoggedIn, isTrue);
    });

    test(
      'a 301 on an authenticated request marks the session expired',
      () async {
        final service = await loggedInService();

        final dio = Dio()
          ..httpClientAdapter = _FakeHttpClientAdapter({'code': 301})
          ..interceptors.add(NeteaseAuthInterceptor(service));
        await dio.get('https://music.163.com/api/v1/playlist/detail');

        final account = await service.getCurrentAccount();
        expect(account, isNotNull);
        expect(account!.sessionExpired, isTrue);
        expect(account.isLoggedIn, isFalse);
        expect(account.userName, 'Signed-in User');
        expect(secureStorage.values, isEmpty);
      },
    );

    test('a 301 without a logged-in account marks nothing', () async {
      final service = NeteaseAccountService(
        isar: isar,
        secureStorage: secureStorage,
      );

      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter({'code': 301})
        ..interceptors.add(NeteaseAuthInterceptor(service));
      await dio.get('https://music.163.com/api/v1/playlist/detail');

      // 匿名請求本來就會拿到 301，那不是憑證失效。
      expect(await service.getCurrentAccount(), isNull);
    });
  });
}

/// 刷新永遠換不回有效憑證的 Bilibili 服務。
///
/// `refreshCredentials()` 真打 passport API，測試裡不能讓它出門；回 false 正是
/// 「-101 之後刷新也救不回來」那條要驗的路徑。
class _NonRefreshingBilibiliAccountService extends BilibiliAccountService {
  _NonRefreshingBilibiliAccountService({
    required super.isar,
    required super.secureStorage,
  });

  @override
  Future<bool> refreshCredentials() async => false;
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this.data);

  final Map<String, dynamic> data;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode(data)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
