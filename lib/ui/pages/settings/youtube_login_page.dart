import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/toast_service.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account_provider.dart';
import '../../../services/account/youtube_account_service.dart';

/// YouTube 登錄頁面（WebView 登錄）
///
/// Google 封殺 WebView 登錄（返回 403 disallowed_useragent），
/// 解決方案：UA 偽裝，去除 `;wv` 標記，偽裝為普通 Chrome 瀏覽器。
class YouTubeLoginPage extends ConsumerStatefulWidget {
  const YouTubeLoginPage({super.key});

  @override
  ConsumerState<YouTubeLoginPage> createState() => _YouTubeLoginPageState();
}

class _YouTubeLoginPageState extends ConsumerState<YouTubeLoginPage> {
  bool _isLoading = true;
  bool _loginHandled = false;

  /// 獲取偽裝 UA（去除 ;wv 標記）
  String get _userAgent {
    if (Platform.isAndroid) {
      // Android: 去除 ;wv 標記，偽裝為普通 Chrome
      return 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36';
    }
    // Windows/Desktop: 標準 Chrome UA
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  }

  void _onPageLoaded(InAppWebViewController controller, WebUri? url) async {
    setState(() => _isLoading = false);

    if (url == null || _loginHandled) return;

    final host = url.host;
    // 檢測跳轉到 youtube.com（登錄成功）
    if (host.contains('youtube.com') && !host.contains('accounts.google')) {
      _loginHandled = true;
      await _extractCookiesAndLogin(controller);
    }
  }

  Future<void> _extractCookiesAndLogin(InAppWebViewController controller) async {
    try {
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(
        url: WebUri('https://www.youtube.com'),
      );

      final cookieMap = <String, String>{};
      for (final cookie in cookies) {
        cookieMap[cookie.name] = cookie.value.toString();
      }

      // 驗證 SAPISID 存在（關鍵認證 Cookie）
      if (cookieMap['SAPISID'] == null || cookieMap['SAPISID']!.isEmpty) {
        _loginHandled = false;
        return;
      }

      // 可選：提取 DATASYNC_ID
      try {
        final datasyncId = await controller.evaluateJavascript(
          source: "ytcfg.get('DATASYNC_ID')",
        );
        if (datasyncId is String && datasyncId.isNotEmpty && datasyncId != 'null') {
          cookieMap['DATASYNC_ID'] = datasyncId;
        }
      } catch (_) {
        // DATASYNC_ID 是可選的，忽略錯誤
      }

      final accountService = ref.read(youtubeAccountServiceProvider);
      await accountService.loginWithCookies(cookieMap);

      // 從 WebView 頁面提取用戶信息（比 InnerTube API 更可靠）
      await _extractUserInfoFromPage(controller, accountService);

      if (mounted) {
        ToastService.show(context, t.account.loginSuccess);
        Navigator.pop(context, true);
      }
    } catch (e) {
      _loginHandled = false;
      if (mounted) {
        ToastService.error(context, e.toString());
      }
    }
  }

  /// 從 WebView 頁面的 ytInitialData / ytcfg / account_menu 提取用戶信息
  Future<void> _extractUserInfoFromPage(
    InAppWebViewController controller,
    YouTubeAccountService accountService,
  ) async {
    String? avatarUrl;
    String? channelId;
    String? userName;

    // Step 1: 從頁面全局變量提取 avatar + channelId
    try {
      final result = await controller.evaluateJavascript(source: '''
        (function() {
          try {
            var data = {};
            if (typeof ytInitialData !== 'undefined' && ytInitialData) {
              var topbar = ytInitialData.topbar;
              if (topbar && topbar.desktopTopbarRenderer) {
                var topbarBtn = topbar.desktopTopbarRenderer.topbarButtons;
                if (topbarBtn) {
                  for (var i = 0; i < topbarBtn.length; i++) {
                    var btn = topbarBtn[i];
                    if (btn.topbarMenuButtonRenderer && btn.topbarMenuButtonRenderer.avatar) {
                      var thumbs = btn.topbarMenuButtonRenderer.avatar.thumbnails;
                      if (thumbs && thumbs.length > 0) {
                        data.avatarUrl = thumbs[thumbs.length - 1].url;
                      }
                    }
                  }
                }
              }
            }
            if (!data.avatarUrl) {
              var img = document.querySelector('#avatar-btn img');
              if (img) data.avatarUrl = img.src;
            }
            if (typeof ytcfg !== 'undefined' && ytcfg.get) {
              var ch = ytcfg.get('CHANNEL_ID');
              if (ch) data.channelId = ch;
            }
            return JSON.stringify(data);
          } catch(e) { return JSON.stringify({error: e.message}); }
        })()
      ''');
      if (result is String && result.isNotEmpty && result != 'null') {
        final info = Map<String, dynamic>.from(_parseJson(result));
        avatarUrl = info['avatarUrl'] as String?;
        channelId = info['channelId'] as String?;
      }
    } catch (_) {}

    // Step 2: 從瀏覽器上下文獲取用戶名
    // 策略 A: ytcfg ID_TOKEN JWT / DELEGATED_SESSION_ID
    // 策略 B: InnerTube accounts_list 端點
    // 策略 C: yt.config_ 全局變量
    try {
      final asyncResult = await controller.callAsyncJavaScript(functionBody: '''
        var result = {};
        // --- 策略 A: ytcfg 提取 ---
        if (typeof ytcfg !== 'undefined' && ytcfg.get) {
          // 直接嘗試 USER_ACCOUNT_NAME
          var uan = ytcfg.get('USER_ACCOUNT_NAME');
          if (uan) result.userName = uan;
          var idToken = ytcfg.get('ID_TOKEN');
          if (idToken && idToken.indexOf('.') > 0) {
            try {
              var parts = idToken.split('.');
              var payload = JSON.parse(atob(parts[1]));
              if (payload.name) result.userName = payload.name;
            } catch(e) {}
          }
          var dsid = ytcfg.get('DELEGATED_SESSION_ID');
          if (dsid && dsid.indexOf('UC') === 0) {
            result.channelId = dsid.split('||')[0];
          }
        }
        // --- 策略 B: accounts_list 端點 ---
        if (!result.userName) {
          try {
            var ctx = ytcfg.get('INNERTUBE_CONTEXT');
            var key = ytcfg.get('INNERTUBE_API_KEY');
            if (ctx && key) {
              var resp = await fetch('/youtubei/v1/account/accounts_list?key=' + key, {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({context: ctx})
              });
              var data = await resp.json();
              function findField(obj, name, d) {
                if (d > 10 || !obj || typeof obj !== 'object') return null;
                if (obj[name]) {
                  var v = obj[name];
                  if (typeof v === 'string' && v.length > 0) return v;
                  if (v && v.simpleText) return v.simpleText;
                  if (v && v.runs) return v.runs.map(function(r){return r.text||''}).join('');
                }
                var keys = Object.keys(obj);
                for (var i = 0; i < keys.length; i++) {
                  var r = findField(obj[keys[i]], name, d + 1);
                  if (r) return r;
                }
                return null;
              }
              var n = findField(data, 'accountName', 0);
              if (n) result.userName = n;
              if (!result.userName) {
                n = findField(data, 'channelTitle', 0);
                if (n) result.userName = n;
              }
              var c = findField(data, 'channelId', 0);
              if (c) result.channelId = c;
            }
          } catch(e) { result.accountsListError = e.message; }
        }
        // --- 策略 C: yt.config_ ---
        if (!result.userName && typeof yt !== 'undefined' && yt.config_) {
          var cfg = yt.config_;
          var nameKeys = ['USER_ACCOUNT_NAME', 'LOGGED_IN_USER', 'USER_DISPLAY_NAME', 'CHANNEL_NAME'];
          for (var i = 0; i < nameKeys.length; i++) {
            if (cfg[nameKeys[i]]) { result.userName = cfg[nameKeys[i]]; break; }
          }
        }
        return JSON.stringify(result);
      ''');
      final menuResult = asyncResult?.value;
      if (menuResult is String && menuResult.isNotEmpty && menuResult != 'null') {
        final info = Map<String, dynamic>.from(_parseJson(menuResult));
        userName = info['userName'] as String?;
        channelId ??= info['channelId'] as String?;
      }
    } catch (_) {}

    // 更新帳號信息
    if (avatarUrl != null || channelId != null || userName != null) {
      await accountService.updateUserInfo(
        avatarUrl: avatarUrl,
        userId: channelId,
        userName: userName,
      );
    }

    // 如果仍然沒有用戶名，用 InnerTube API 兜底
    if (userName == null) {
      await accountService.fetchAndUpdateUserInfo();
    }
  }

  dynamic _parseJson(String json) {
    try {
      return const JsonDecoder().convert(json);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t.importPlatform.youtube),
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(
                'https://accounts.google.com/ServiceLogin'
                '?service=youtube'
                '&continue=https://www.youtube.com/',
              ),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              userAgent: _userAgent,
            ),
            onLoadStop: _onPageLoaded,
            onLoadStart: (_, __) {
              if (mounted) setState(() => _isLoading = true);
            },
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
