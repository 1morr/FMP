import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// App 的路由：所有頁面都在外殼的 `ShellRoute` 裡，打開在首頁
/// （`docs/design/DESIGN.md`〈手機〉）。換頁不做過場，像系統的分頁。
GoRouter buildRouter() => GoRouter(
  initialLocation: Destination.home.path,
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(location: state.uri.path, child: child),
      routes: [
        for (final destination in Destination.values)
          GoRoute(
            path: destination.path,
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: _pageOf(destination),
            ),
          ),
      ],
    ),
  ],
);

Widget _pageOf(Destination destination) => switch (destination) {
  Destination.home => const HomePage(),
  Destination.library => const LibraryPage(),
  Destination.queue => const QueuePage(),
  Destination.settings => const SettingsPage(),
  Destination.search => const SearchPage(),
};
