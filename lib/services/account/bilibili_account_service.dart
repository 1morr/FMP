import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:isar/isar.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/account.dart';
import '../../data/models/track.dart';
import 'account_service.dart';
import 'bilibili_credentials.dart';

/// QR 碼數據
class QrCodeData {
  final String url;
  final String qrcodeKey;

  QrCodeData({required this.url, required this.qrcodeKey});
}

/// QR 碼掃碼狀態
enum QrCodeStatus {
  waiting, // 等待掃碼
  scanned, // 已掃碼待確認
  expired, // 已過期
  success, // 登錄成功
}

/// QR 碼輪詢結果
class QrCodePollResult {
  final QrCodeStatus status;
  final String? message;

  QrCodePollResult({required this.status, this.message});
}

/// Bilibili 帳號服務實現
class BilibiliAccountService extends AccountService with Logging {
  final Dio _dio;
  final FlutterSecureStorage _secureStorage;
  final Isar _isar;

  static const String _storageKey = 'account_bilibili_credentials';
  static const String _apiBase = 'https://api.bilibili.com';
  static const String _passportBase = 'https://passport.bilibili.com';

  BilibiliAccountService({required Isar isar})
      : _isar = isar,
        _secureStorage = const FlutterSecureStorage(),
        _dio = Dio(BaseOptions(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            'Referer': 'https://www.bilibili.com/',
            'Origin': 'https://www.bilibili.com',
            'Accept': 'application/json, text/plain, */*',
          },
          connectTimeout: AppConstants.networkConnectTimeout,
          receiveTimeout: AppConstants.networkReceiveTimeout,
        ));

  @override
  SourceType get platform => SourceType.bilibili;

  // ===== 登錄 =====

  /// WebView 登錄完成後，從 WebView 提取的 cookies 初始化
  Future<void> loginWithCookies({
    required String sessdata,
    required String biliJct,
    required String dedeUserId,
    required String dedeUserIdCkMd5,
    required String refreshToken,
  }) async {
    final credentials = BilibiliCredentials(
      sessdata: sessdata,
      biliJct: biliJct,
      dedeUserId: dedeUserId,
      dedeUserIdCkMd5: dedeUserIdCkMd5,
      refreshToken: refreshToken,
      savedAt: DateTime.now(),
    );

    // 保存到 secure storage
    await _secureStorage.write(
      key: _storageKey,
      value: jsonEncode(credentials.toJson()),
    );

    // 更新 Account 記錄
    await _updateAccount(
      isLoggedIn: true,
      userId: dedeUserId,
      loginAt: DateTime.now(),
    );

    logInfo('Bilibili login successful, userId: $dedeUserId');
  }

  /// QR 碼登錄 - 生成 QR 碼
  Future<QrCodeData> generateQrCode() async {
    final response = await _dio.get(
      '$_passportBase/x/passport-login/web/qrcode/generate',
    );

    final data = response.data['data'];
    return QrCodeData(
      url: data['url'] as String,
      qrcodeKey: data['qrcode_key'] as String,
    );
  }

  /// QR 碼登錄 - 輪詢掃碼狀態
  Stream<QrCodePollResult> pollQrCodeStatus(String qrcodeKey) async* {
    while (true) {
      await Future.delayed(const Duration(seconds: 2));

      try {
        final response = await _dio.get(
          '$_passportBase/x/passport-login/web/qrcode/poll',
          queryParameters: {'qrcode_key': qrcodeKey},
        );

        final data = response.data['data'];
        final code = data['code'] as int;

        switch (code) {
          case 0: // 登錄成功
            // 從 Set-Cookie 提取 cookies
            final cookies = _extractCookiesFromResponse(response);
            final refreshToken = data['refresh_token'] as String? ?? '';

            if (cookies != null) {
              await loginWithCookies(
                sessdata: cookies['SESSDATA'] ?? '',
                biliJct: cookies['bili_jct'] ?? '',
                dedeUserId: cookies['DedeUserID'] ?? '',
                dedeUserIdCkMd5: cookies['DedeUserID__ckMd5'] ?? '',
                refreshToken: refreshToken,
              );
            }

            yield QrCodePollResult(status: QrCodeStatus.success);
            return;

          case 86038: // 已過期
            yield QrCodePollResult(status: QrCodeStatus.expired);
            return;

          case 86090: // 已掃碼待確認
            yield QrCodePollResult(status: QrCodeStatus.scanned);

          default: // 86101 等待掃碼
            yield QrCodePollResult(status: QrCodeStatus.waiting);
        }
      } catch (e) {
        logError('QR code poll error', e);
        yield QrCodePollResult(
          status: QrCodeStatus.waiting,
          message: e.toString(),
        );
      }
    }
  }

  // ===== 認證管理 =====

  /// 獲取當前認證 Cookie 字符串
  Future<String?> getAuthCookieString() async {
    final credentials = await _loadCredentials();
    return credentials?.toCookieString();
  }

  /// 獲取 CSRF token
  Future<String?> getCsrfToken() async {
    final credentials = await _loadCredentials();
    return credentials?.biliJct;
  }

  /// 獲取用戶 mid
  Future<String?> getUserMid() async {
    final credentials = await _loadCredentials();
    return credentials?.dedeUserId;
  }

  // ===== AccountService 實現 =====

  @override
  Future<bool> isLoggedIn() async {
    final account = await getCurrentAccount();
    return account?.isLoggedIn ?? false;
  }

  @override
  Future<Account?> getCurrentAccount() async {
    return _isar.accounts
        .filter()
        .platformEqualTo(SourceType.bilibili)
        .findFirst();
  }

  @override
  Future<void> logout() async {
    // 清除 secure storage
    await _secureStorage.delete(key: _storageKey);

    // 更新 Account 記錄
    await _updateAccount(isLoggedIn: false);

    logInfo('Bilibili logged out');
  }

  @override
  Future<bool> needsRefresh() async {
    final credentials = await _loadCredentials();
    if (credentials == null) return false;

    try {
      final cookieString = credentials.toCookieString();
      final response = await _dio.get(
        '$_passportBase/x/passport-login/web/cookie/info',
        options: Options(headers: {'Cookie': cookieString}),
      );

      final data = response.data['data'];
      return data['refresh'] == true;
    } catch (e) {
      logWarning('Failed to check cookie refresh status: $e');
      return false;
    }
  }

  @override
  Future<bool> refreshCredentials() async {
    // Phase 5 實現完整 RSA 流程
    // 暫時返回 false 表示需要重新登錄
    logWarning('Cookie refresh not yet implemented (Phase 5)');
    return false;
  }

  // ===== 用戶信息 =====

  /// 獲取用戶信息並更新 Account
  Future<void> fetchAndUpdateUserInfo() async {
    final cookieString = await getAuthCookieString();
    if (cookieString == null) return;

    try {
      final response = await _dio.get(
        '$_apiBase/x/web-interface/nav',
        options: Options(headers: {'Cookie': cookieString}),
      );

      final code = response.data['code'] as int?;
      if (code != 0) {
        logWarning('Failed to fetch user info, code: $code');
        return;
      }

      final data = response.data['data'];
      await _updateAccount(
        userName: data['uname'] as String?,
        avatarUrl: data['face'] as String?,
        userId: (data['mid'] as num?)?.toString(),
      );

      logInfo('User info updated: ${data['uname']}');
    } catch (e) {
      logError('Failed to fetch user info', e);
    }
  }

  // ===== 內部方法 =====

  /// 從 secure storage 加載憑據
  Future<BilibiliCredentials?> _loadCredentials() async {
    final json = await _secureStorage.read(key: _storageKey);
    if (json == null) return null;
    try {
      return BilibiliCredentials.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (e) {
      logError('Failed to parse credentials', e);
      return null;
    }
  }

  /// 更新或創建 Account 記錄
  Future<void> _updateAccount({
    bool? isLoggedIn,
    String? userId,
    String? userName,
    String? avatarUrl,
    DateTime? loginAt,
  }) async {
    await _isar.writeTxn(() async {
      var account = await _isar.accounts
          .filter()
          .platformEqualTo(SourceType.bilibili)
          .findFirst();

      account ??= Account()..platform = SourceType.bilibili;

      if (isLoggedIn != null) account.isLoggedIn = isLoggedIn;
      if (userId != null) account.userId = userId;
      if (userName != null) account.userName = userName;
      if (avatarUrl != null) account.avatarUrl = avatarUrl;
      if (loginAt != null) account.loginAt = loginAt;
      account.lastRefreshed = DateTime.now();

      await _isar.accounts.put(account);
    });
  }

  /// 從 HTTP 響應中提取 Set-Cookie
  Map<String, String>? _extractCookiesFromResponse(Response response) {
    final setCookies = response.headers['set-cookie'];
    if (setCookies == null || setCookies.isEmpty) return null;

    final cookies = <String, String>{};
    for (final cookie in setCookies) {
      final parts = cookie.split(';').first.split('=');
      if (parts.length >= 2) {
        cookies[parts[0].trim()] = parts.sublist(1).join('=').trim();
      }
    }
    return cookies.isEmpty ? null : cookies;
  }

  /// 暴露 Dio 實例（供 Interceptor 重試使用）
  Dio get dio => _dio;
}
