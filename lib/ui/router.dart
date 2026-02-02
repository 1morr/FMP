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
import 'pages/settings/audio_settings_page.dart';
import 'pages/settings/database_viewer_page.dart';
import 'pages/settings/log_viewer_page.dart';
import 'pages/radio/radio_page.dart';
import 'pages/radio/radio_player_page.dart';
import 'pages/library/downloaded_page.dart';
import 'pages/library/downloaded_category_page.dart';
import '../providers/download_provider.dart';
import 'app_shell.dart';

/// 路由路径常量
class RoutePaths {
  RoutePaths._();

  static const String home = '/';
  static const String search = '/search';
  static const String explore = '/explore';
  static const String player = '/player';
  static const String queue = '/queue';
  static const String radio = '/radio';
  static const String radioPlayer = '/radio-player';
  static const String library = '/library';
  static const String settings = '/settings';
  static const String playlistDetail = '/library/:id';
  static const String downloaded = '/library/downloaded';
  static const String downloadManager = '/settings/download-manager';
  static const String audioSettings = '/settings/audio';
  static const String developerOptions = '/settings/developer';
  static const String databaseViewer = '/settings/developer/database';
  static const String logViewer = '/settings/developer/logs';
}

/// 路由名称常量
class RouteNames {
  RouteNames._();

  static const String home = 'home';
  static const String search = 'search';
  static const String explore = 'explore';
  static const String player = 'player';
  static const String queue = 'queue';
  static const String radio = 'radio';
  static const String radioPlayer = 'radioPlayer';
  static const String library = 'library';
  static const String settings = 'settings';
  static const String playlistDetail = 'playlistDetail';
  static const String downloaded = 'downloaded';
  static const String downloadedCategory = 'downloadedCategory';
  static const String downloadManager = 'downloadManager';
  static const String audioSettings = 'audioSettings';
  static const String developerOptions = 'developerOptions';
  static const String databaseViewer = 'databaseViewer';
  static const String logViewer = 'logViewer';
}

/// 用于 StatefulShellRoute 的 navigator key
final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// 应用路由配置
final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: RoutePaths.home,
  routes: [
    // StatefulShellRoute - 使用 IndexedStack 保持页面状态
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => AppShell(
        navigationShell: navigationShell,
      ),
      branches: [
        // 首页分支
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: RoutePaths.home,
              name: RouteNames.home,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: HomePage(),
              ),
            ),
          ],
        ),
        // 搜索分支
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: RoutePaths.search,
              name: RouteNames.search,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: SearchPage(),
              ),
            ),
          ],
        ),
        // 队列分支
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: RoutePaths.queue,
              name: RouteNames.queue,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: QueuePage(),
              ),
            ),
          ],
        ),
        // 音乐库分支
        StatefulShellBranch(
          routes: [
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
          ],
        ),
        // 电台分支
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: RoutePaths.radio,
              name: RouteNames.radio,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: RadioPage(),
              ),
            ),
          ],
        ),
        // 设置分支
        StatefulShellBranch(
          routes: [
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
                // 音频质量设置页面
                GoRoute(
                  path: 'audio',
                  name: RouteNames.audioSettings,
                  builder: (context, state) => const AudioSettingsPage(),
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
                    // 日志查看器
                    GoRoute(
                      path: 'logs',
                      name: RouteNames.logViewer,
                      builder: (context, state) => const LogViewerPage(),
                    ),
                  ],
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
      parentNavigatorKey: _rootNavigatorKey,
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
    // 電台播放器頁面（不在 Shell 內）
    GoRoute(
      path: RoutePaths.radioPlayer,
      name: RouteNames.radioPlayer,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => CustomTransitionPage(
        child: const RadioPlayerPage(),
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
