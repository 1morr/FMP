import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:isar/isar.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../core/utils/innertube_utils.dart';
import '../../data/models/account.dart';
import '../../data/models/track.dart';
import 'account_service.dart';
import 'youtube_credentials.dart';

/// YouTube 帳號服務實現
///
/// 使用 Cookie + SAPISIDHASH 認證。
/// Cookie 有效期 ~2 年，無需刷新流程。
class YouTubeAccountService extends AccountService with Logging {
  final Dio _dio;
  final FlutterSecureStorage _secureStorage;
  final Isar _isar;
  YouTubeCredentials? _cachedCredentials;

  static const String _storageKey = 'account_youtube_credentials';
  static const String _innerTubeApiBase = 'https://www.youtube.com/youtubei/v1';
  static const String _innerTubeApiKey =
      'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const String _innerTubeClientName = 'WEB';
  static const String _innerTubeClientVersion = '2.20260128.05.00';
  static const Set<String> requiredCookieNames = {
    'SAPISID',
    '__Secure-1PSID',
    '__Secure-3PSID',
  };

  YouTubeAccountService({required Isar isar})
      : _isar = isar,
        _secureStorage = const FlutterSecureStorage(),
        _dio = Dio(BaseOptions(
          headers: {
            'Content-Type': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Origin': 'https://www.youtube.com',
            'Referer': 'https://www.youtube.com/',
          },
          connectTimeout: AppConstants.networkConnectTimeout,
          receiveTimeout: AppConstants.networkReceiveTimeout,
        ));

  @override
  SourceType get platform => SourceType.youtube;

  // ===== 登錄 =====

  /// WebView 登錄完成後，從 WebView 提取的 cookies 初始化
  Future<void> loginWithCookies(Map<String, String> cookies) async {
    final missingCookies =
        YouTubeAccountService.getMissingRequiredCookies(cookies);
    if (missingCookies.isNotEmpty) {
      logWarning(
          'YouTube login: missing required cookies: ${missingCookies.join(', ')}');
      throw Exception(
          'Missing required YouTube cookies: ${missingCookies.join(', ')}');
    }

    final credentials = YouTubeCredentials(
      sid: cookies['SID'] ?? '',
      hsid: cookies['HSID'] ?? '',
      ssid: cookies['SSID'] ?? '',
      apisid: cookies['APISID'] ?? '',
      sapisid: cookies['SAPISID'] ?? '',
      secure1Psid: cookies['__Secure-1PSID'] ?? '',
      secure3Psid: cookies['__Secure-3PSID'] ?? '',
      secure1Papisid: cookies['__Secure-1PAPISID'] ?? '',
      secure3Papisid: cookies['__Secure-3PAPISID'] ?? '',
      loginInfo: cookies['LOGIN_INFO'] ?? '',
      datasyncId: cookies['DATASYNC_ID'],
      savedAt: DateTime.now(),
    );

    await _secureStorage.write(
      key: _storageKey,
      value: jsonEncode(credentials.toJson()),
    );
    _cachedCredentials = credentials;

    await _updateAccount(isLoggedIn: true, loginAt: DateTime.now());
    logInfo('YouTube login successful');
  }

  // ===== 認證管理 =====

  static List<String> getMissingRequiredCookies(Map<String, String> cookies) {
    return requiredCookieNames
        .where((name) => (cookies[name] ?? '').isEmpty)
        .toList();
  }

  /// 獲取認證 headers（Cookie + Authorization）
  Future<Map<String, String>?> getAuthHeaders() async {
    final credentials = await _loadCredentials();
    if (credentials == null || !credentials.isValid) return null;
    return {
      'Cookie': credentials.toCookieString(),
      'Authorization': credentials.generateSapiSidHash(),
    };
  }

  /// 獲取 Cookie 字符串
  Future<String?> getAuthCookieString() async {
    final credentials = await _loadCredentials();
    return credentials?.toCookieString();
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
        .platformEqualTo(SourceType.youtube)
        .findFirst();
  }

  @override
  Future<void> logout() async {
    _cachedCredentials = null;
    await _secureStorage.delete(key: _storageKey);
    await _updateAccount(isLoggedIn: false);

    // 清除 WebView cookies，避免重新登入時自動使用舊帳號
    try {
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteCookies(
        url: WebUri('https://accounts.google.com'),
      );
      await cookieManager.deleteCookies(
        url: WebUri('https://www.youtube.com'),
      );
    } catch (e) {
      logWarning('Failed to clear WebView cookies: $e');
    }

    logInfo('YouTube logged out');
  }

  /// YouTube Cookie 不需要刷新（有效期 ~2 年）
  @override
  Future<bool> refreshCredentials() async => true;

  /// YouTube Cookie 不需要刷新
  @override
  Future<bool> needsRefresh() async => false;

  // ===== 用戶信息 =====

  /// 從外部（如 WebView）直接更新用戶信息
  Future<void> updateUserInfo({
    String? userName,
    String? avatarUrl,
    String? userId,
  }) async {
    await _updateAccount(
      userName: userName,
      avatarUrl: avatarUrl,
      userId: userId,
    );
    if (userName != null || avatarUrl != null) {
      logInfo('YouTube user info updated from WebView: $userName');
    }
  }

  /// 獲取用戶信息並更新 Account
  ///
  /// 策略：
  /// 1. browse SPaccount_overview（帳號設置頁）提取用戶名
  /// 2. 如果已有 channelId，browse 頻道頁獲取頻道名
  /// 3. 兜底：guide 端點，只匹配有 thumbnail（頭像）的項
  Future<void> fetchAndUpdateUserInfo() async {
    final headers = await getAuthHeaders();
    if (headers == null) return;

    // 策略 1: browse SPaccount_overview — 帳號設置頁包含用戶名
    try {
      final response = await _dio.post(
        '$_innerTubeApiBase/browse?key=$_innerTubeApiKey',
        data: jsonEncode({
          'browseId': 'SPaccount_overview',
          'context': buildInnerTubeContext(),
        }),
        options: Options(headers: headers),
      );
      final data = response.data;
      final name = _extractNameFromAccountOverview(data);
      if (name != null) {
        await _updateAccount(userName: name);
        logInfo('YouTube user info updated via account_overview: $name');
        return;
      } else if (data is Map<String, dynamic>) {
        logWarning('YouTube: account_overview returned no user name');
      }
    } catch (e) {
      logWarning('YouTube: account_overview browse failed: $e');
    }

    // 策略 2: 用已有的 channelId browse 頻道頁
    final account = await getCurrentAccount();
    final channelId = account?.userId;
    if (channelId != null && channelId.isNotEmpty) {
      final browseId = channelId.startsWith('UC') ? channelId : 'UC$channelId';
      try {
        final response = await _dio.post(
          '$_innerTubeApiBase/browse?key=$_innerTubeApiKey',
          data: jsonEncode({
            'browseId': browseId,
            'context': buildInnerTubeContext(),
          }),
          options: Options(headers: headers),
        );
        final channelName = _extractChannelName(response.data);
        if (channelName != null) {
          await _updateAccount(userName: channelName);
          logInfo('YouTube user info updated via channel browse: $channelName');
          return;
        }
      } catch (e) {
        logWarning('YouTube: channel browse failed: $e');
      }
    }

    // 策略 3: guide 端點 — 只匹配有 thumbnail（用戶頭像）且無 icon 的項
    try {
      final response = await _dio.post(
        '$_innerTubeApiBase/guide?key=$_innerTubeApiKey',
        data: jsonEncode({
          'context': buildInnerTubeContext(),
        }),
        options: Options(headers: headers),
      );
      final channelName = _extractChannelNameFromGuide(response.data);
      if (channelName != null) {
        await _updateAccount(userName: channelName);
        logInfo('YouTube user info updated via guide: $channelName');
        return;
      }
    } catch (e) {
      logWarning('YouTube: guide endpoint failed: $e');
    }

    logWarning('YouTube: could not extract user info from any endpoint');
  }

  /// 從 SPaccount_overview 響應中提取用戶名
  String? _extractNameFromAccountOverview(Map<String, dynamic> data) {
    // 遞歸搜索 accountName / title 等常見字段
    final accountItem = _findRendererRecursive(data, 'accountItemRenderer');
    if (accountItem != null) {
      return _extractText(accountItem['accountName']);
    }

    // 嘗試從 header 提取
    final pageHeader = _findRendererRecursive(data, 'pageHeaderRenderer');
    if (pageHeader != null) {
      final title = pageHeader['pageTitle'] as String?;
      if (title != null && title.isNotEmpty) return title;
    }

    // 嘗試從 settingsAccountRenderer 提取
    final settingsAccount =
        _findRendererRecursive(data, 'settingsAccountRenderer');
    if (settingsAccount != null) {
      return _extractText(settingsAccount['accountName']);
    }

    // 嘗試從 topbar 提取
    final topbarName = _extractNameFromTopbar(data['topbar']);
    if (topbarName != null) return topbarName;

    // 遞歸搜索任何 accountName 字段
    return _findStringFieldRecursive(data, 'accountName');
  }

  /// 從 topbar 中提取帳號名稱
  String? _extractNameFromTopbar(dynamic topbar) {
    if (topbar is! Map<String, dynamic>) return null;
    final buttons = topbar['desktopTopbarRenderer']?['topbarButtons'] as List?;
    if (buttons == null) return null;

    for (final button in buttons) {
      if (button is! Map<String, dynamic>) continue;
      final menuBtn = button['topbarMenuButtonRenderer'];
      if (menuBtn == null) continue;

      // 帳號按鈕有 avatar 字段
      if (menuBtn['avatar'] == null) continue;

      // 嘗試 tooltip（過濾通用標籤如 "Account menu"）
      final tooltip = menuBtn['tooltip'] as String?;
      if (tooltip != null &&
          tooltip.isNotEmpty &&
          !_isGenericMenuLabel(tooltip)) {
        return tooltip;
      }

      // 嘗試 accessibility（同樣過濾通用標籤）
      final accLabel =
          menuBtn['accessibility']?['accessibilityData']?['label'] as String?;
      if (accLabel != null &&
          accLabel.isNotEmpty &&
          !_isGenericMenuLabel(accLabel)) {
        return accLabel;
      }
    }
    return null;
  }

  /// 判斷是否為通用菜單標籤（非用戶名）
  bool _isGenericMenuLabel(String text) {
    final lower = text.toLowerCase();
    return lower.contains('account') ||
        lower.contains('menu') ||
        lower.contains('帳戶') ||
        lower.contains('账户') ||
        lower.contains('アカウント') ||
        lower.contains('選單') ||
        lower.contains('菜单') ||
        lower.contains('メニュー');
  }

  /// 遞歸搜索指定字段名的字符串值（委託到共用工具）
  String? _findStringFieldRecursive(dynamic data, String fieldName,
          [int depth = 0]) =>
      InnerTubeUtils.findStringField(data, fieldName, depth);

  /// 從 guide 響應中提取頻道名
  ///
  /// 只匹配有 thumbnail（用戶頭像）且無 icon 的 guideEntryRenderer，
  /// 避免匹配 "Music" 等系統頁面。
  String? _extractChannelNameFromGuide(Map<String, dynamic> data) {
    final items = data['items'] as List?;
    if (items == null) return null;

    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final sectionRenderer = item['guideSectionRenderer'];
      if (sectionRenderer == null) continue;

      final sectionItems = sectionRenderer['items'] as List?;
      if (sectionItems == null) continue;

      for (final sectionItem in sectionItems) {
        if (sectionItem is! Map<String, dynamic>) continue;
        final entryRenderer = sectionItem['guideEntryRenderer'];
        if (entryRenderer == null) continue;

        // 用戶頻道項特徵：有 thumbnail（頭像）且無 icon（系統圖標）
        // 系統頁面（Home, Music 等）有 icon，用戶頻道只有 thumbnail
        final hasThumbnail = entryRenderer['thumbnail'] != null;
        final hasIcon = entryRenderer['icon'] != null;
        final browseId = entryRenderer['navigationEndpoint']?['browseEndpoint']
            ?['browseId'] as String?;
        final title = _extractText(entryRenderer['formattedTitle']) ??
            _extractText(entryRenderer['title']);

        if (hasThumbnail &&
            !hasIcon &&
            browseId != null &&
            browseId.startsWith('UC')) {
          if (title != null && title.isNotEmpty) return title;
        }
      }
    }
    return null;
  }

  /// 從頻道頁 browse 響應中提取頻道名
  String? _extractChannelName(Map<String, dynamic> data) {
    // 路徑 1: metadata.channelMetadataRenderer.title
    final title =
        data['metadata']?['channelMetadataRenderer']?['title'] as String?;
    if (title != null) return title;

    // 路徑 2: header.c4TabbedHeaderRenderer.title
    final headerTitle =
        data['header']?['c4TabbedHeaderRenderer']?['title'] as String?;
    if (headerTitle != null) return headerTitle;

    // 路徑 3: header.pageHeaderRenderer — 新版
    final pageHeader =
        data['header']?['pageHeaderRenderer']?['pageTitle'] as String?;
    if (pageHeader != null) return pageHeader;

    // 路徑 4: 遞歸搜索 channelMetadataRenderer
    final renderer = _findRendererRecursive(data, 'channelMetadataRenderer');
    if (renderer != null) {
      return renderer['title'] as String?;
    }

    return null;
  }

  /// 遞歸搜索指定 renderer（委託到共用工具）
  Map<String, dynamic>? _findRendererRecursive(dynamic data, String key,
          [int depth = 0]) =>
      InnerTubeUtils.findRenderer(data, key, depth);

  /// 從 InnerTube Text 對象中提取文本（委託到共用工具）
  String? _extractText(dynamic textObj) => InnerTubeUtils.extractText(textObj);

  // ===== InnerTube 請求輔助 =====

  /// 構建帶認證的 InnerTube 請求 context
  Map<String, dynamic> buildInnerTubeContext() {
    return {
      'client': {
        'clientName': _innerTubeClientName,
        'clientVersion': _innerTubeClientVersion,
        'hl': 'en',
        'gl': 'US',
      },
    };
  }

  /// 暴露 Dio 實例（供 Interceptor 和 PlaylistService 使用）
  Dio get dio => _dio;

  /// 暴露 API 配置
  String get innerTubeApiBase => _innerTubeApiBase;
  String get innerTubeApiKey => _innerTubeApiKey;

  // ===== 內部方法 =====

  Future<YouTubeCredentials?> _loadCredentials() async {
    if (_cachedCredentials != null) return _cachedCredentials;
    final json = await _secureStorage.read(key: _storageKey);
    if (json == null) return null;
    try {
      _cachedCredentials = YouTubeCredentials.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      return _cachedCredentials;
    } catch (e) {
      logError('Failed to parse YouTube credentials', e);
      return null;
    }
  }

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
          .platformEqualTo(SourceType.youtube)
          .findFirst();

      account ??= Account()..platform = SourceType.youtube;

      if (isLoggedIn != null) account.isLoggedIn = isLoggedIn;
      if (userId != null) account.userId = userId;
      if (userName != null) account.userName = userName;
      if (avatarUrl != null) account.avatarUrl = avatarUrl;
      if (loginAt != null) account.loginAt = loginAt;
      account.lastRefreshed = DateTime.now();

      await _isar.accounts.put(account);
    });
  }
}
