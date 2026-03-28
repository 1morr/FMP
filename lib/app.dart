import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'main.dart' show preloadedThemeMode, preloadedPrimaryColor, preloadedFontFamily;
import 'providers/database_provider.dart';
import 'providers/account_provider.dart';
import 'providers/playback_settings_provider.dart';
import 'providers/desktop_settings_provider.dart';
import 'providers/hotkey_config_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/windows_desktop_provider.dart';
import 'services/refresh/auto_refresh_service.dart';
import 'i18n/strings.g.dart';
import 'providers/locale_provider.dart';
import 'ui/router.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/network_status_banner.dart';

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
        theme: AppTheme.lightTheme(primaryColor: preloadedPrimaryColor, fontFamily: preloadedFontFamily),
        darkTheme: AppTheme.darkTheme(primaryColor: preloadedPrimaryColor, fontFamily: preloadedFontFamily),
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
        theme: AppTheme.lightTheme(primaryColor: preloadedPrimaryColor, fontFamily: preloadedFontFamily),
        darkTheme: AppTheme.darkTheme(primaryColor: preloadedPrimaryColor, fontFamily: preloadedFontFamily),
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

        // 初始化自动刷新服务（后台运行，不阻塞 UI）
        ref.watch(autoRefreshServiceProvider);

        // 啟動時檢查並刷新 Bilibili Cookie（後台執行）
        ref.watch(accountCookieRefreshProvider);

        return MaterialApp.router(
          title: '${AppConstants.appName} - ${AppConstants.appFullName}',
          debugShowCheckedModeBanner: false,

          // i18n 配置
          locale: TranslationProvider.of(context).flutterLocale,
          supportedLocales: AppLocaleUtils.supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,

          // 主题配置
          theme: AppTheme.lightTheme(primaryColor: primaryColor, fontFamily: fontFamily),
          darkTheme: AppTheme.darkTheme(primaryColor: primaryColor, fontFamily: fontFamily),
          themeMode: themeMode,

          // 路由配置
          routerConfig: appRouter,

          // 全局 Banner 包装器 - 确保在所有页面（包括全屏播放器）显示网络状态
          // Windows: 禁用 semantics 避免 Flutter 引擎 accessibility_bridge 报错
          // (已知 Flutter Windows bug: AXTree 更新失败)
          builder: (context, child) {
            Widget content = _AppContentWrapper(child: child);
            if (Platform.isWindows) {
              content = ExcludeSemantics(child: content);
            }
            return content;
          },
        );
      },
    );
  }
}

/// App 内容包装器 - 处理网络状态 Banner 和 SafeArea
class _AppContentWrapper extends ConsumerWidget {
  final Widget? child;

  const _AppContentWrapper({this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBannerVisible = ref.watch(networkBannerVisibleProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // Windows 平台的 Banner 由 ResponsiveScaffold 在标题栏下方显示，
    // 此处不重复渲染（全屏页面如播放器页面自行处理）
    if (Platform.isWindows) {
      return child ?? const SizedBox.shrink();
    }

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
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
