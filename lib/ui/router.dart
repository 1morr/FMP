import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'pages/home/home_page.dart';
import 'pages/search/search_page.dart';
import 'pages/player/player_page.dart';
import 'pages/queue/queue_page.dart';
import 'pages/library/library_page.dart';
import 'pages/library/playlist_detail_page.dart';
import 'pages/settings/settings_page.dart';
import 'pages/settings/download_manager_page.dart';
import 'pages/settings/developer_options_page.dart';
import 'pages/settings/database_viewer_page.dart';
import 'pages/library/downloaded_page.dart';
import 'pages/library/downloaded_category_page.dart';
import '../providers/download_provider.dart';
import 'app_shell.dart';

/// 路由路径常量
class RoutePaths {
  RoutePaths._();

  static const String home = '/';
  static const String search = '/search';
  static const String player = '/player';
  static const String queue = '/queue';
  static const String library = '/library';
  static const String settings = '/settings';
  static const String playlistDetail = '/library/:id';
  static const String downloaded = '/library/downloaded';
  static const String downloadManager = '/settings/download-manager';
  static const String developerOptions = '/settings/developer';
  static const String databaseViewer = '/settings/developer/database';
}

/// 路由名称常量
class RouteNames {
  RouteNames._();

  static const String home = 'home';
  static const String search = 'search';
  static const String player = 'player';
  static const String queue = 'queue';
  static const String library = 'library';
  static const String settings = 'settings';
  static const String playlistDetail = 'playlistDetail';
  static const String downloaded = 'downloaded';
  static const String downloadedCategory = 'downloadedCategory';
  static const String downloadManager = 'downloadManager';
  static const String developerOptions = 'developerOptions';
  static const String databaseViewer = 'databaseViewer';
}

/// 应用路由配置
final appRouter = GoRouter(
  initialLocation: RoutePaths.home,
  routes: [
    // Shell Route - 包含底部导航的页面
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: RoutePaths.home,
          name: RouteNames.home,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HomePage(),
          ),
        ),
        GoRoute(
          path: RoutePaths.search,
          name: RouteNames.search,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SearchPage(),
          ),
        ),
        GoRoute(
          path: RoutePaths.queue,
          name: RouteNames.queue,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: QueuePage(),
          ),
        ),
        GoRoute(
          path: RoutePaths.library,
          name: RouteNames.library,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: LibraryPage(),
          ),
          routes: [
            // 已下载页面
            GoRoute(
              path: 'downloaded',
              name: RouteNames.downloaded,
              builder: (context, state) => const DownloadedPage(),
              routes: [
                // 已下载分类详情页
                GoRoute(
                  path: ':folderName',
                  name: RouteNames.downloadedCategory,
                  builder: (context, state) {
                    final category = state.extra as DownloadedCategory;
                    return DownloadedCategoryPage(category: category);
                  },
                ),
              ],
            ),
            // 歌单详情页作为 library 的子路由
            GoRoute(
              path: ':id',
              name: RouteNames.playlistDetail,
              builder: (context, state) {
                final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                return PlaylistDetailPage(playlistId: id);
              },
            ),
          ],
        ),
        GoRoute(
          path: RoutePaths.settings,
          name: RouteNames.settings,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsPage(),
          ),
          routes: [
            // 下载管理页面作为 settings 的子路由
            GoRoute(
              path: 'download-manager',
              name: RouteNames.downloadManager,
              builder: (context, state) => const DownloadManagerPage(),
            ),
            // 开发者选项页面
            GoRoute(
              path: 'developer',
              name: RouteNames.developerOptions,
              builder: (context, state) => const DeveloperOptionsPage(),
              routes: [
                // 数据库查看器
                GoRoute(
                  path: 'database',
                  name: RouteNames.databaseViewer,
                  builder: (context, state) => const DatabaseViewerPage(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    // 全屏播放器页面（不在 Shell 内）
    GoRoute(
      path: RoutePaths.player,
      name: RouteNames.player,
      pageBuilder: (context, state) => CustomTransitionPage(
        child: const PlayerPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    ),
  ],
);
