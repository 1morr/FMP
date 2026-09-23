import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/main.dart'
    show preloadedThemeMode, preloadedPrimaryColor, preloadedFontFamily;
import 'package:fmp/data/database/database_provider.dart';
import 'package:fmp/providers/account/account_provider.dart';
import 'package:fmp/providers/audio/playback_settings_provider.dart';
import 'package:fmp/providers/download/startup_download_sync_provider.dart';
import 'package:fmp/providers/settings/desktop_settings_provider.dart';
import 'package:fmp/providers/settings/hotkey_config_provider.dart';
import 'package:fmp/providers/settings/theme_provider.dart';
import 'package:fmp/providers/system/windows_desktop_provider.dart';
import 'package:fmp/services/library/auto_refresh_service.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/settings/locale_provider.dart';
import 'package:fmp/providers/settings/refresh_settings_provider.dart';
import 'package:fmp/ui/router.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:fmp/ui/widgets/app_bars/custom_title_bar.dart';
import 'package:fmp/ui/widgets/feedback/network_status_banner.dart';

/// FMP 应用主组件
class FMPApp extends ConsumerWidget {
  const FMPApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 等待数据库初始化
    final dbAsync = ref.watch(databaseProvider);

    return dbAsync.when(
      loading: () => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(
          primaryColor: preloadedPrimaryColor,
          fontFamily: preloadedFontFamily,
        ),
        darkTheme: AppTheme.darkTheme(
          primaryColor: preloadedPrimaryColor,
          fontFamily: preloadedFontFamily,
        ),
        themeMode: preloadedThemeMode,
        locale: TranslationProvider.of(context).flutterLocale,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(t.general.initializing),
              ],
            ),
          ),
        ),
      ),
      error: (error, stack) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(
          primaryColor: preloadedPrimaryColor,
          fontFamily: preloadedFontFamily,
        ),
        darkTheme: AppTheme.darkTheme(
          primaryColor: preloadedPrimaryColor,
          fontFamily: preloadedFontFamily,
        ),
        themeMode: preloadedThemeMode,
        locale: TranslationProvider.of(context).flutterLocale,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(t.general.initFailed),
                const SizedBox(height: 8),
                Text(error.toString()),
              ],
            ),
          ),
        ),
      ),
      data: (_) {
        // Windows: 初始化桌面特性（托盘、快捷键等）
        if (Platform.isWindows) {
          ref.watch(windowsDesktopServiceProvider);
          // 初始化桌面设置（托盘/快捷键开关），会根据保存的设置自动应用
          ref.watch(minimizeToTrayProvider);
          ref.watch(globalHotkeysEnabledProvider);
          // 初始化开机自启动设置
          ref.watch(launchAtStartupProvider);
          // 加载自定义快捷键配置
          ref.watch(hotkeyConfigProvider);
        }

        // 从设置中获取主题模式和自定义颜色
        final themeState = ref.watch(themeProvider);
        final themeMode = themeState.themeMode;
        final primaryColor = themeState.primaryColor;
        final fontFamily = themeState.fontFamily;

        // 初始化 locale provider（加载用户语言设置）
        ref.watch(localeProvider);

        // 提前初始化播放设置（避免进入设置页时 Switch 出现开启动画）
        ref.watch(playbackSettingsProvider);

        // 載入時把存的排行榜刷新間隔套到服務上；以前要打開設定頁才生效
        ref.watch(refreshSettingsProvider);

        // 初始化自动刷新服务（后台运行，不阻塞 UI）
        ref.watch(autoRefreshServiceProvider);

        // 啟動時檢查帳號狀態（含 Cookie 刷新，後台執行）
        ref.watch(accountStatusCheckProvider);

        // 請求期偵測到的登入失效，由它補一次提示
        ref.watch(accountSessionExpiryWatcherProvider);

        // 啟動後靜默同步已下載頁面的本地文件狀態
        ref.watch(startupDownloadSyncProvider);

        return MaterialApp.router(
          title: '${AppConstants.appName} - ${AppConstants.appFullName}',
          debugShowCheckedModeBanner: false,

          // i18n 配置
          locale: TranslationProvider.of(context).flutterLocale,
          supportedLocales: AppLocaleUtils.supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,

          // 主题配置
          theme: AppTheme.lightTheme(
            primaryColor: primaryColor,
            fontFamily: fontFamily,
          ),
          darkTheme: AppTheme.darkTheme(
            primaryColor: primaryColor,
            fontFamily: fontFamily,
          ),
          themeMode: themeMode,

          // 路由配置
          routerConfig: appRouter,

          // 全局内容包装器 - 确保标题栏 / 网络状态在所有页面（包括播放器）一致显示
          builder: (context, child) => AppContentWrapper(child: child),
        );
      },
    );
  }
}

/// App 內容包裝器：Windows 標題列、網路狀態 Banner 與 SafeArea。
///
/// 這些控制項掛在 Navigator 之上。每個路由的 ModalBarrier 都帶
/// `BlockSemantics`，會把同一個語意容器裡、比它先畫的節點整段丟掉 —— 標題列
/// 的三個按鈕和 Banner 因此不在語意樹上，讀屏聽不到。路由那一格包成獨立的
/// 語意容器（[_routeSemantics]），擋的範圍就只剩路由自己。
///
/// 公開是為了讓 widget test 在真的 Navigator 底下量語意樹。
class AppContentWrapper extends ConsumerWidget {
  final Widget? child;

  const AppContentWrapper({super.key, this.child});

  Widget _routeSemantics() =>
      Semantics(container: true, child: child ?? const SizedBox.shrink());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Platform.isWindows) {
      return Column(
        children: [
          const CustomTitleBar(),
          const NetworkStatusBanner(),
          Expanded(child: _routeSemantics()),
        ],
      );
    }

    final isBannerVisible = ref.watch(networkBannerVisibleProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // 当 banner 可见时，状态栏区域使用 banner 颜色；否则使用 scaffold 背景色
    final statusBarColor = isBannerVisible
        ? colorScheme.surfaceContainerHigh
        : Theme.of(context).scaffoldBackgroundColor;

    return ColoredBox(
      color: statusBarColor,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const NetworkStatusBanner(),
            Expanded(
              // 移除顶部 padding，避免 AppBar 再次添加状态栏空间
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: _routeSemantics(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
