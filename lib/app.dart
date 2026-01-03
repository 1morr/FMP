import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/router.dart';
import 'ui/theme/app_theme.dart';

/// FMP 应用主组件
class FMPApp extends ConsumerWidget {
  const FMPApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: 从设置中获取主题模式和自定义颜色
    const themeMode = ThemeMode.system;
    const primaryColor = null; // 使用默认颜色

    return MaterialApp.router(
      title: 'FMP - Flutter Music Player',
      debugShowCheckedModeBanner: false,

      // 主题配置
      theme: AppTheme.lightTheme(primaryColor: primaryColor),
      darkTheme: AppTheme.darkTheme(primaryColor: primaryColor),
      themeMode: themeMode,

      // 路由配置
      routerConfig: appRouter,
    );
  }
}
