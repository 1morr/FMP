import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/services/toast_service.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account_provider.dart';
import '../../../services/account/bilibili_account_service.dart';

/// Bilibili 登錄頁面（WebView + QR 碼）
class BilibiliLoginPage extends ConsumerStatefulWidget {
  const BilibiliLoginPage({super.key});

  @override
  ConsumerState<BilibiliLoginPage> createState() => _BilibiliLoginPageState();
}

class _BilibiliLoginPageState extends ConsumerState<BilibiliLoginPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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
    return Scaffold(
      appBar: AppBar(
        title: Text(t.importPlatform.bilibili),
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
          _WebViewLoginTab(onLoginSuccess: _onLoginSuccess),
          _QrCodeLoginTab(onLoginSuccess: _onLoginSuccess),
        ],
      ),
    );
  }
}

// ===== WebView 登錄 Tab =====

class _WebViewLoginTab extends ConsumerStatefulWidget {
  final VoidCallback onLoginSuccess;

  const _WebViewLoginTab({required this.onLoginSuccess});

  @override
  ConsumerState<_WebViewLoginTab> createState() => _WebViewLoginTabState();
}

class _WebViewLoginTabState extends ConsumerState<_WebViewLoginTab> {
  bool _isLoading = true;
  bool _loginHandled = false;

  void _onPageLoaded(InAppWebViewController controller, WebUri? url) async {
    setState(() => _isLoading = false);

    if (url == null || _loginHandled) return;

    final host = url.host;
    if (host.contains('bilibili.com') && !host.contains('passport')) {
      _loginHandled = true;

      // 提取 cookies
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(
        url: WebUri('https://www.bilibili.com'),
      );

      String? findCookie(String name) {
        try {
          return cookies
              .firstWhere((c) => c.name == name)
              .value;
        } catch (_) {
          return null;
        }
      }

      final sessdata = findCookie('SESSDATA');
      final biliJct = findCookie('bili_jct');
      final dedeUserId = findCookie('DedeUserID');
      final dedeUserIdCkMd5 = findCookie('DedeUserID__ckMd5');

      if (sessdata == null || biliJct == null || dedeUserId == null) {
        _loginHandled = false;
        return;
      }

      // 提取 refresh_token
      final refreshToken = await controller.evaluateJavascript(
        source: "localStorage.getItem('ac_time_value')",
      ) as String?;

      final accountService = ref.read(bilibiliAccountServiceProvider);
      await accountService.loginWithCookies(
        sessdata: sessdata,
        biliJct: biliJct,
        dedeUserId: dedeUserId,
        dedeUserIdCkMd5: dedeUserIdCkMd5 ?? '',
        refreshToken: refreshToken ?? '',
      );
      await accountService.fetchAndUpdateUserInfo();

      widget.onLoginSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri('https://passport.bilibili.com/login'),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            userAgent:
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          ),
          onLoadStop: _onPageLoaded,
          onLoadStart: (_, __) {
            if (mounted) setState(() => _isLoading = true);
          },
        ),
        if (_isLoading)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

// ===== QR 碼登錄 Tab =====

class _QrCodeLoginTab extends ConsumerStatefulWidget {
  final VoidCallback onLoginSuccess;

  const _QrCodeLoginTab({required this.onLoginSuccess});

  @override
  ConsumerState<_QrCodeLoginTab> createState() => _QrCodeLoginTabState();
}

class _QrCodeLoginTabState extends ConsumerState<_QrCodeLoginTab> {
  QrCodeData? _qrData;
  QrCodeStatus _status = QrCodeStatus.waiting;
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
      _status = QrCodeStatus.waiting;
    });

    try {
      final accountService = ref.read(bilibiliAccountServiceProvider);
      final qrData = await accountService.generateQrCode();

      if (!mounted) return;
      setState(() {
        _qrData = qrData;
        _isGenerating = false;
      });

      _startPolling(qrData.qrcodeKey);
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ToastService.show(context, e.toString());
      }
    }
  }

  void _startPolling(String qrcodeKey) {
    _pollSubscription?.cancel();
    final accountService = ref.read(bilibiliAccountServiceProvider);

    _pollSubscription =
        accountService.pollQrCodeStatus(qrcodeKey).listen((result) async {
      if (!mounted) return;

      setState(() => _status = result.status);

      if (result.status == QrCodeStatus.success) {
        await accountService.fetchAndUpdateUserInfo();
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
            else if (_qrData != null)
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
                      data: _qrData!.url,
                      version: QrVersions.auto,
                      size: 200,
                    ),
                    if (_status == QrCodeStatus.expired)
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
                                  style: TextStyle(
                                      color: colorScheme.onSurface)),
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
            if (_status == QrCodeStatus.expired)
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
      case QrCodeStatus.waiting:
        return t.account.qrWaiting;
      case QrCodeStatus.scanned:
        return t.account.qrScanned;
      case QrCodeStatus.expired:
        return t.account.qrExpired;
      case QrCodeStatus.success:
        return t.account.loginSuccess;
    }
  }
}
