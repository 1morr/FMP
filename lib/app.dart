import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/database_provider.dart';
import 'ui/router.dart';
import 'ui/theme/app_theme.dart';

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
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在初始化...'),
              ],
            ),
          ),
        ),
      ),
      error: (error, stack) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text('初始化失败'),
                const SizedBox(height: 8),
                Text(error.toString()),
              ],
            ),
          ),
        ),
      ),
      data: (_) {
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
      },
    );
  }
}
