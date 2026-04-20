import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/services/toast_service.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account_provider.dart';

/// 網易雲音樂登錄頁面
///
/// Android: TabBar (WebView + QR Code)
/// Desktop: 僅 QR Code（無 TabBar）
class NeteaseLoginPage extends ConsumerStatefulWidget {
  const NeteaseLoginPage({super.key});

  @override
  ConsumerState<NeteaseLoginPage> createState() => _NeteaseLoginPageState();
}

class _NeteaseLoginPageState extends ConsumerState<NeteaseLoginPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _tabController = TabController(length: 2, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _onLoginSuccess() {
    if (mounted) {
      ToastService.show(context, t.account.loginSuccess);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.importPlatform.netease),
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: t.account.webLogin),
              Tab(text: t.account.qrLogin),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _NeteaseWebViewLoginTab(onLoginSuccess: _onLoginSuccess),
            _NeteaseQrCodeLoginTab(onLoginSuccess: _onLoginSuccess),
          ],
        ),
      );
    }

    // Desktop: QR Code only
    return Scaffold(
      appBar: AppBar(
        title: Text(t.importPlatform.netease),
      ),
      body: _NeteaseQrCodeLoginTab(onLoginSuccess: _onLoginSuccess),
    );
  }
}

// ===== WebView 登錄 Tab (Android only) =====

class _NeteaseWebViewLoginTab extends ConsumerStatefulWidget {
  final VoidCallback onLoginSuccess;

  const _NeteaseWebViewLoginTab({required this.onLoginSuccess});

  @override
  ConsumerState<_NeteaseWebViewLoginTab> createState() =>
      _NeteaseWebViewLoginTabState();
}

class _NeteaseWebViewLoginTabState
    extends ConsumerState<_NeteaseWebViewLoginTab> {
  bool _isLoading = true;
  bool _loginHandled = false;

  @override
  void dispose() {
    _cleanupWebView();
    super.dispose();
  }

  /// 清除 WebView 殘留的 cookies、快取和本地存儲
  Future<void> _cleanupWebView() async {
    try {
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteCookies(
        url: WebUri('https://music.163.com'),
        domain: '.163.com',
      );
    } catch (_) {}
    try {
      await InAppWebViewController.clearAllCache();
    } catch (_) {}
    try {
      await WebStorageManager.instance().deleteAllData();
    } catch (_) {}
  }

  void _onPageLoaded(InAppWebViewController controller, WebUri? url) async {
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (url == null || _loginHandled) return;

    // 只在 163.com 域名下檢查 cookies
    final host = url.host;
    if (!host.endsWith('163.com')) return;

    // 監控所有頁面加載，檢查 MUSIC_U cookie 是否出現
    final cookieManager = CookieManager.instance();
    final cookies = await cookieManager.getCookies(
      url: WebUri('https://music.163.com'),
    );

    String? findCookie(String name) {
      try {
        return cookies.firstWhere((c) => c.name == name).value;
      } catch (_) {
        return null;
      }
    }

    final musicU = findCookie('MUSIC_U');
    if (musicU == null || musicU.isEmpty) return;

    _loginHandled = true;
    final csrf = findCookie('__csrf') ?? '';

    try {
      final accountService = ref.read(neteaseAccountServiceProvider);
      final success = await accountService.loginWithCookiesAndValidate(
        musicU: musicU,
        csrf: csrf,
      );
      if (!success) {
        _loginHandled = false;
        return;
      }
      await _cleanupWebView();

      widget.onLoginSuccess();
    } catch (_) {
      _loginHandled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri('https://music.163.com/#/login'),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            userAgent:
                'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
            preferredContentMode: UserPreferredContentMode.MOBILE,
          ),
          onLoadStop: _onPageLoaded,
          onLoadStart: (_, __) {
            if (mounted) setState(() => _isLoading = true);
          },
        ),
        if (_isLoading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

// ===== QR 碼登錄 Tab =====

class _NeteaseQrCodeLoginTab extends ConsumerStatefulWidget {
  final VoidCallback onLoginSuccess;

  const _NeteaseQrCodeLoginTab({required this.onLoginSuccess});

  @override
  ConsumerState<_NeteaseQrCodeLoginTab> createState() =>
      _NeteaseQrCodeLoginTabState();
}

class _NeteaseQrCodeLoginTabState
    extends ConsumerState<_NeteaseQrCodeLoginTab> {
  String? _qrUrl;
  int _status = 801; // 801=waiting, 802=scanned, 800=expired, 803=success
  bool _isGenerating = false;
  StreamSubscription? _pollSubscription;

  @override
  void initState() {
    super.initState();
    _generateQrCode();
  }

  @override
  void dispose() {
    _pollSubscription?.cancel();
    super.dispose();
  }

  Future<void> _generateQrCode() async {
    if (_isGenerating) return;
    setState(() {
      _isGenerating = true;
      _status = 801;
    });

    try {
      final accountService = ref.read(neteaseAccountServiceProvider);
      final result = await accountService.generateQrCode();

      if (!mounted) return;
      setState(() {
        _qrUrl = result.url;
        _isGenerating = false;
      });

      _startPolling(result.unikey);
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ToastService.show(context, e.toString());
      }
    }
  }

  void _startPolling(String unikey) {
    _pollSubscription?.cancel();
    final accountService = ref.read(neteaseAccountServiceProvider);

    _pollSubscription =
        accountService.pollQrCodeStatus(unikey).listen((result) async {
      if (!mounted) return;

      setState(() => _status = result.code);

      if (result.code == 803 && mounted) {
        widget.onLoginSuccess();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // QR 碼
            if (_isGenerating)
              const SizedBox(
                width: 200,
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_qrUrl != null)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    QrImageView(
                      data: _qrUrl!,
                      version: QrVersions.auto,
                      size: 200,
                    ),
                    if (_status == 800)
                      Container(
                        width: 200,
                        height: 200,
                        color: Colors.white.withValues(alpha: 0.85),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh,
                                  size: 40, color: colorScheme.primary),
                              const SizedBox(height: 8),
                              Text(t.account.qrExpired,
                                  style:
                                      TextStyle(color: colorScheme.onSurface)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            // 狀態文字
            Text(
              _statusText,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // 重新生成按鈕
            if (_status == 800)
              FilledButton.icon(
                onPressed: _generateQrCode,
                icon: const Icon(Icons.refresh),
                label: Text(t.account.qrRefresh),
              ),
          ],
        ),
      ),
    );
  }

  String get _statusText {
    switch (_status) {
      case 801:
        return t.account.neteaseQrWaiting;
      case 802:
        return t.account.qrScanned;
      case 800:
        return t.account.qrExpired;
      case 803:
        return t.account.loginSuccess;
      default:
        return t.account.neteaseQrWaiting;
    }
  }
}
