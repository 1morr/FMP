import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:go_router/go_router.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:material_ui/material_ui.dart';

/// 全螢幕播放頁的路徑：疊在外殼上面（不在 `ShellRoute` 裡），蓋住導覽與
/// 播放膠囊。
const playerPath = '/player';

/// App 的路由：頁面都在外殼的 `ShellRoute` 裡，打開在首頁
/// （`docs/design/DESIGN.md`〈手機〉）。換頁不做過場，像系統的分頁。播放頁
/// 從底部升起（morph），系統開「減少動態效果」時改淡入淡出。
GoRouter buildRouter() => GoRouter(
  initialLocation: Destination.home.path,
  routes: [
    GoRoute(
      path: playerPath,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        transitionDuration: FmpMotion.morph,
        reverseTransitionDuration: FmpMotion.mid,
        child: const PlayerPage(),
        transitionsBuilder: (context, animation, _, child) {
          if (MediaQuery.disableAnimationsOf(context)) {
            return FadeTransition(opacity: animation, child: child);
          }
          return SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: FmpMotion.morphCurve,
                    reverseCurve: FmpMotion.outCurve.flipped,
                  ),
                ),
            child: child,
          );
        },
      ),
    ),
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
