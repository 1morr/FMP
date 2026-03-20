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
import 'bilibili_crypto.dart';

/// QR 碼數據
class QrCodeData {
  final String url;
  final String qrcodeKey;

  QrCodeData({required this.url, required this.qrcodeKey});
}

/// 勳章牆直播間項目
class MedalWallItem {
  final String roomId;
  final String name;
  final String? avatarUrl;
  final int uid;
  final int liveStatus; // 0: 未直播, 1: 直播中, 2: 輪播
  final String link;

  const MedalWallItem({
    required this.roomId,
    required this.name,
    this.avatarUrl,
    required this.uid,
    required this.liveStatus,
    required this.link,
  });

  bool get isLive => liveStatus == 1;
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
  BilibiliCredentials? _cachedCredentials;

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
    if (sessdata.isEmpty || biliJct.isEmpty || dedeUserId.isEmpty) {
      throw ArgumentError('Invalid Bilibili credentials: required cookies are empty');
    }

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
    _cachedCredentials = credentials;

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
  ///
  /// 最多輪詢 3 分鐘（90 次 × 2 秒），超時後自動停止。
  /// 連續網絡錯誤超過 5 次也會停止。
  /// 取消訂閱後輪詢會在當前請求完成後立即停止。
  Stream<QrCodePollResult> pollQrCodeStatus(String qrcodeKey) {
    var stopped = false;
    late final StreamController<QrCodePollResult> controller;
    controller = StreamController<QrCodePollResult>(
      onCancel: () {
        stopped = true;
        if (!controller.isClosed) controller.close();
      },
    );

    Future<void> poll() async {
      const maxPolls = 90; // 3 分鐘
      const maxConsecutiveErrors = 5;
      int pollCount = 0;
      int consecutiveErrors = 0;

      while (pollCount < maxPolls && !stopped) {
        await Future.delayed(const Duration(seconds: 2));
        if (stopped) break;
        pollCount++;

        try {
          final response = await _dio.get(
            '$_passportBase/x/passport-login/web/qrcode/poll',
            queryParameters: {'qrcode_key': qrcodeKey},
          );
          if (stopped) break;

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

              if (!stopped) controller.add(QrCodePollResult(status: QrCodeStatus.success));
              return;

            case 86038: // 已過期
              if (!stopped) controller.add(QrCodePollResult(status: QrCodeStatus.expired));
              return;

            case 86090: // 已掃碼待確認
              consecutiveErrors = 0;
              if (!stopped) controller.add(QrCodePollResult(status: QrCodeStatus.scanned));

            default: // 86101 等待掃碼
              consecutiveErrors = 0;
              if (!stopped) controller.add(QrCodePollResult(status: QrCodeStatus.waiting));
          }
        } catch (e) {
          if (stopped) break;
          logError('QR code poll error', e);
          consecutiveErrors++;
          if (consecutiveErrors >= maxConsecutiveErrors) {
            controller.add(QrCodePollResult(
              status: QrCodeStatus.expired,
              message: 'Network error',
            ));
            return;
          }
          controller.add(QrCodePollResult(
            status: QrCodeStatus.waiting,
            message: e.toString(),
          ));
        }
      }

      // 超時
      if (!stopped) {
        controller.add(QrCodePollResult(status: QrCodeStatus.expired));
      }
    }

    poll().whenComplete(() {
      if (!controller.isClosed) controller.close();
    });

    return controller.stream;
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
    _cachedCredentials = null;

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
    final credentials = await _loadCredentials();
    if (credentials == null) return false;

    try {
      final cookieString = credentials.toCookieString();

      // Step 1: 檢查是否需要刷新
      final checkResponse = await _dio.get(
        '$_passportBase/x/passport-login/web/cookie/info',
        options: Options(headers: {'Cookie': cookieString}),
      );
      if (checkResponse.data['data']?['refresh'] != true) {
        logInfo('Cookie refresh not needed');
        return true; // 不需要刷新，當前 cookie 仍有效
      }
      final timestamp = checkResponse.data['data']['timestamp'] as int;

      // Step 2: 生成 correspondPath
      final correspondPath =
          BilibiliCrypto.generateCorrespondPath(timestamp);

      // Step 3: 獲取 refresh_csrf
      final csrfResponse = await _dio.get(
        'https://www.bilibili.com/correspond/1/$correspondPath',
        options: Options(headers: {'Cookie': cookieString}),
      );
      final refreshCsrf = _extractRefreshCsrf(csrfResponse.data as String);
      if (refreshCsrf == null) {
        logWarning('Failed to extract refresh_csrf from HTML');
        return false;
      }

      // Step 4: 刷新 Cookie
      final refreshResponse = await _dio.post(
        '$_passportBase/x/passport-login/web/cookie/refresh',
        data: {
          'csrf': credentials.biliJct,
          'refresh_csrf': refreshCsrf,
          'source': 'main_web',
          'refresh_token': credentials.refreshToken,
        },
        options: Options(
          headers: {'Cookie': cookieString},
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final refreshData = refreshResponse.data;
      if (refreshData['code'] != 0) {
        logWarning(
            'Cookie refresh failed, code: ${refreshData['code']}, message: ${refreshData['message']}');
        return false;
      }

      // 從 Set-Cookie 提取新 cookies
      final newCookies = _extractCookiesFromResponse(refreshResponse);
      final newRefreshToken =
          refreshData['data']?['refresh_token'] as String? ?? '';
      if (newCookies == null || newRefreshToken.isEmpty) {
        logWarning('Failed to extract new cookies from refresh response');
        return false;
      }

      // 保存新憑據
      final newCredentials = BilibiliCredentials(
        sessdata: newCookies['SESSDATA'] ?? credentials.sessdata,
        biliJct: newCookies['bili_jct'] ?? credentials.biliJct,
        dedeUserId: newCookies['DedeUserID'] ?? credentials.dedeUserId,
        dedeUserIdCkMd5:
            newCookies['DedeUserID__ckMd5'] ?? credentials.dedeUserIdCkMd5,
        refreshToken: newRefreshToken,
        savedAt: DateTime.now(),
      );
      await _secureStorage.write(
        key: _storageKey,
        value: jsonEncode(newCredentials.toJson()),
      );
      _cachedCredentials = newCredentials;

      // Step 5: 確認更新（使用新 cookie + 舊 refresh_token）
      final newCookieString = newCredentials.toCookieString();
      await _dio.post(
        '$_passportBase/x/passport-login/web/confirm/refresh',
        data: {
          'csrf': newCredentials.biliJct,
          'refresh_token': credentials.refreshToken, // 舊 refresh_token
        },
        options: Options(
          headers: {'Cookie': newCookieString},
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      // 更新 Account 記錄（lastRefreshed 自動設置為 now）
      await _updateAccount();

      logInfo('Cookie refresh successful');
      return true;
    } catch (e) {
      logError('Cookie refresh failed', e);
      return false;
    }
  }

  /// 從 HTML 中提取 refresh_csrf
  ///
  /// HTML 中包含 `<div id="1-name">...</div>` 標籤，其中的文本即為 refresh_csrf。
  String? _extractRefreshCsrf(String html) {
    final regex = RegExp(r'<div\s+id="1-name"\s*>(.*?)</div>');
    final match = regex.firstMatch(html);
    return match?.group(1)?.trim();
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

  // ===== 勳章牆（直播間列表） =====

  /// 從勳章牆 API 獲取關注的直播間列表
  Future<List<MedalWallItem>> fetchMedalWall() async {
    final cookieString = await getAuthCookieString();
    if (cookieString == null) throw Exception('Not logged in');

    final mid = await getUserMid();
    if (mid == null) throw Exception('User mid not available');

    final response = await _dio.get(
      'https://api.live.bilibili.com/xlive/web-ucenter/user/MedalWall',
      queryParameters: {'target_id': mid},
      options: Options(headers: {'Cookie': cookieString}),
    );

    final code = response.data['code'] as int?;
    if (code != 0) {
      throw Exception('MedalWall API error: ${response.data['message']}');
    }

    final list = response.data['data']?['list'] as List? ?? [];

    // 並行獲取所有主播的直播間信息
    final futures = list.map((item) async {
      final medalInfo = item['medal_info'] as Map<String, dynamic>?;
      if (medalInfo == null) return null;

      final uid = medalInfo['target_id'] as int? ?? 0;
      if (uid == 0) return null;

      try {
        // 通過 UID 獲取直播間號
        final roomResponse = await _dio.get(
          'https://api.live.bilibili.com/room/v1/Room/getRoomInfoOld',
          queryParameters: {'mid': uid},
        );

        if (roomResponse.data['code'] != 0) return null;

        final roomId = roomResponse.data['data']?['roomid']?.toString();
        if (roomId == null || roomId == '0') return null;

        return MedalWallItem(
          roomId: roomId,
          name: item['target_name'] as String? ?? '',
          avatarUrl: item['target_icon'] as String?,
          uid: uid,
          liveStatus: item['live_status'] as int? ?? 0,
          link: 'https://live.bilibili.com/$roomId',
        );
      } catch (e) {
        // 單個失敗不影響其他項
        return null;
      }
    }).toList();

    final items = await Future.wait(futures);
    return items.whereType<MedalWallItem>().toList();
  }

  // ===== 內部方法 =====

  /// 從 secure storage 加載憑據（帶內存緩存）
  Future<BilibiliCredentials?> _loadCredentials() async {
    if (_cachedCredentials != null) return _cachedCredentials;
    final json = await _secureStorage.read(key: _storageKey);
    if (json == null) return null;
    try {
      _cachedCredentials = BilibiliCredentials.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      return _cachedCredentials;
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
      try {
        final parts = cookie.split(';').first.split('=');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final value = parts.sublist(1).join('=').trim();
          if (key.isNotEmpty) {
            cookies[key] = value;
          }
        }
      } catch (e) {
        logWarning('Failed to parse cookie: $cookie, error: $e');
      }
    }
    return cookies.isEmpty ? null : cookies;
  }

  /// 暴露 Dio 實例（供 Interceptor 重試使用）
  Dio get dio => _dio;
}
