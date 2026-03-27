import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:isar/isar.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../core/utils/netease_crypto.dart';
import '../../data/models/account.dart';
import '../../data/models/track.dart';
import 'account_service.dart';
import 'netease_credentials.dart';

/// 網易雲帳號歌單項
class NeteasePlaylistItem {
  final String id;
  final String name;
  final int trackCount;
  final String? coverUrl;
  final String? creatorName;

  const NeteasePlaylistItem({
    required this.id,
    required this.name,
    required this.trackCount,
    this.coverUrl,
    this.creatorName,
  });
}

/// 網易雲音樂帳號服務實現
///
/// 使用 MUSIC_U Cookie 認證。
/// MUSIC_U 有效期長（~1 年），無需刷新流程。
class NeteaseAccountService extends AccountService with Logging {
  final Dio _dio;
  final FlutterSecureStorage _secureStorage;
  final Isar _isar;
  NeteaseCredentials? _cachedCredentials;

  static const String _storageKey = 'account_netease_credentials';
  static const String _apiBase = 'https://music.163.com';

  NeteaseAccountService({required Isar isar})
      : _isar = isar,
        _secureStorage = const FlutterSecureStorage(),
        _dio = Dio(BaseOptions(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            'Referer': 'https://music.163.com',
            'Origin': 'https://music.163.com',
            'Accept': '*/*',
          },
          contentType: Headers.formUrlEncodedContentType,
          connectTimeout: AppConstants.networkConnectTimeout,
          receiveTimeout: AppConstants.networkReceiveTimeout,
        ));

  @override
  SourceType get platform => SourceType.netease;

  // ===== 登錄 =====

  /// 使用 Cookie 登錄（WebView 提取或手動輸入）
  Future<void> loginWithCookies({
    required String musicU,
    required String csrf,
    String? userId,
  }) async {
    if (musicU.isEmpty) {
      throw ArgumentError('Invalid Netease credentials: MUSIC_U is empty');
    }

    final credentials = NeteaseCredentials(
      musicU: musicU,
      csrf: csrf,
      userId: userId,
      savedAt: DateTime.now(),
    );

    await _secureStorage.write(
      key: _storageKey,
      value: jsonEncode(credentials.toJson()),
    );
    _cachedCredentials = credentials;

    await _updateAccount(
      isLoggedIn: true,
      userId: userId,
      loginAt: DateTime.now(),
    );

    logInfo('Netease login successful${userId != null ? ', userId: $userId' : ''}');
  }

  /// QR 碼登錄 - 生成 QR 碼
  Future<({String url, String unikey})> generateQrCode() async {
    final encrypted = NeteaseCrypto.weapi({'type': 1});
    final response = await _dio.post(
      '$_apiBase/weapi/login/qrcode/unikey',
      data: encrypted,
    );

    final data = response.data;
    final code = data['code'] as int?;
    if (code != 200) {
      throw Exception('Failed to generate QR code: ${data['message']}');
    }

    final unikey = data['unikey'] as String;
    return (
      url: 'https://music.163.com/login?codekey=$unikey',
      unikey: unikey,
    );
  }

  /// QR 碼登錄 - 輪詢掃碼狀態
  ///
  /// 最多輪詢 3 分鐘（60 次 × 3 秒），超時後自動停止。
  /// 狀態碼：800=expired, 801=waiting, 802=scanned, 803=success
  Stream<({int code, String? message})> pollQrCodeStatus(String unikey) {
    var stopped = false;
    late final StreamController<({int code, String? message})> controller;
    controller = StreamController(
      onCancel: () {
        stopped = true;
        if (!controller.isClosed) controller.close();
      },
    );

    Future<void> poll() async {
      const maxPolls = 60;
      const maxConsecutiveErrors = 5;
      int pollCount = 0;
      int consecutiveErrors = 0;

      while (pollCount < maxPolls && !stopped) {
        await Future.delayed(const Duration(seconds: 3));
        if (stopped) break;
        pollCount++;

        try {
          final encrypted = NeteaseCrypto.weapi({'type': 1, 'key': unikey});
          final response = await _dio.post(
            '$_apiBase/weapi/login/qrcode/client/login',
            data: encrypted,
          );
          if (stopped) break;

          final data = response.data;
          final code = data['code'] as int? ?? 0;

          switch (code) {
            case 803: // 登錄成功
              // 從 Set-Cookie 提取 MUSIC_U 和 __csrf
              final cookies = _extractCookiesFromResponse(response);
              if (cookies != null) {
                final musicU = cookies['MUSIC_U'] ?? '';
                final csrf = cookies['__csrf'] ?? '';
                final userId = cookies['__csrf_token']; // 可能沒有

                if (musicU.isNotEmpty) {
                  await loginWithCookies(
                    musicU: musicU,
                    csrf: csrf,
                    userId: userId,
                  );
                }
              }
              if (!stopped) {
                controller.add((code: 803, message: null));
              }
              return;

            case 800: // 已過期
              if (!stopped) controller.add((code: 800, message: null));
              return;

            case 802: // 已掃碼待確認
              consecutiveErrors = 0;
              if (!stopped) controller.add((code: 802, message: null));

            default: // 801 等待掃碼
              consecutiveErrors = 0;
              if (!stopped) controller.add((code: 801, message: null));
          }
        } catch (e) {
          if (stopped) break;
          logError('Netease QR code poll error', e);
          consecutiveErrors++;
          if (consecutiveErrors >= maxConsecutiveErrors) {
            controller.add((code: 800, message: 'Network error'));
            return;
          }
          controller.add((code: 801, message: e.toString()));
        }
      }

      if (!stopped) {
        controller.add((code: 800, message: 'Timeout'));
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

  /// 獲取認證 headers
  Future<Map<String, String>?> getAuthHeaders() async {
    final cookieString = await getAuthCookieString();
    if (cookieString == null) return null;
    return {'Cookie': cookieString};
  }

  /// 獲取 CSRF token
  Future<String?> getCsrfToken() async {
    final credentials = await _loadCredentials();
    return credentials?.csrf;
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
        .platformEqualTo(SourceType.netease)
        .findFirst();
  }

  @override
  Future<void> logout() async {
    await _secureStorage.delete(key: _storageKey);
    _cachedCredentials = null;
    await _updateAccount(isLoggedIn: false);
    logInfo('Netease logged out');
  }

  /// MUSIC_U 有效期長，無需刷新
  @override
  Future<bool> refreshCredentials() async => true;

  /// MUSIC_U 有效期長，無需刷新
  @override
  Future<bool> needsRefresh() async => false;

  // ===== 用戶信息 =====

  /// 檢查登錄狀態並獲取用戶信息
  Future<void> fetchAndUpdateUserInfo() async {
    final cookieString = await getAuthCookieString();
    if (cookieString == null) return;

    try {
      final encrypted = NeteaseCrypto.weapi({});
      final response = await _dio.post(
        '$_apiBase/weapi/w/nuser/account/get',
        data: encrypted,
        options: Options(headers: {'Cookie': cookieString}),
      );

      final data = response.data;
      final code = data['code'] as int?;
      if (code != 200) {
        logWarning('Netease: failed to fetch user info, code: $code');
        return;
      }

      final profile = data['profile'] as Map<String, dynamic>?;
      if (profile == null) {
        logWarning('Netease: user profile is null');
        return;
      }

      final userId = (profile['userId'] as num?)?.toString();
      final userName = profile['nickname'] as String?;
      final avatarUrl = profile['avatarUrl'] as String?;

      await _updateAccount(
        userName: userName,
        avatarUrl: avatarUrl,
        userId: userId,
      );

      // 如果 credentials 中沒有 userId，補充保存
      final credentials = await _loadCredentials();
      if (credentials != null && credentials.userId == null && userId != null) {
        final updated = NeteaseCredentials(
          musicU: credentials.musicU,
          csrf: credentials.csrf,
          userId: userId,
          savedAt: credentials.savedAt,
        );
        await _secureStorage.write(
          key: _storageKey,
          value: jsonEncode(updated.toJson()),
        );
        _cachedCredentials = updated;
      }

      logInfo('Netease user info updated: $userName');
    } catch (e) {
      logError('Failed to fetch Netease user info', e);
    }
  }

  // ===== 歌單管理 =====

  /// 獲取用戶歌單列表
  Future<List<NeteasePlaylistItem>> getUserPlaylists() async {
    final credentials = await _loadCredentials();
    if (credentials == null) throw Exception('Not logged in');

    final userId = credentials.userId;
    if (userId == null) throw Exception('User ID not available');

    final cookieString = credentials.toCookieString();
    final encrypted = NeteaseCrypto.weapi({
      'uid': userId,
      'limit': 50,
      'offset': 0,
    });

    final response = await _dio.post(
      '$_apiBase/weapi/user/playlist',
      data: encrypted,
      options: Options(headers: {'Cookie': cookieString}),
    );

    final data = response.data;
    final code = data['code'] as int?;
    if (code != 200) {
      throw Exception('Failed to fetch playlists: ${data['message']}');
    }

    final playlists = data['playlist'] as List? ?? [];
    return playlists.map((p) {
      final creator = p['creator'] as Map<String, dynamic>?;
      return NeteasePlaylistItem(
        id: (p['id'] as num).toString(),
        name: p['name'] as String? ?? '',
        trackCount: p['trackCount'] as int? ?? 0,
        coverUrl: p['coverImgUrl'] as String?,
        creatorName: creator?['nickname'] as String?,
      );
    }).toList();
  }

  // ===== 內部方法 =====

  /// 從 secure storage 加載憑據（帶內存緩存）
  Future<NeteaseCredentials?> _loadCredentials() async {
    if (_cachedCredentials != null) return _cachedCredentials;
    final json = await _secureStorage.read(key: _storageKey);
    if (json == null) return null;
    try {
      _cachedCredentials = NeteaseCredentials.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      return _cachedCredentials;
    } catch (e) {
      logError('Failed to parse Netease credentials', e);
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
          .platformEqualTo(SourceType.netease)
          .findFirst();

      account ??= Account()..platform = SourceType.netease;

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

  /// 暴露 Dio 實例（供 Interceptor 使用）
  Dio get dio => _dio;
}
