import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/layouts/responsive_scaffold.dart';
import 'package:fmp/ui/router.dart';

void main() {
  group('destinations', () {
    test('has five, which is the M3 ceiling for a navigation bar', () {
      // 「Navigation bars can have three to five destinations.」設定是第六個，
      // 也是最少用的一個，所以它移到導覽軌底部與首頁右上角。
      expect(destinations, hasLength(5));
    });

    test('settings is not one of them', () {
      expect(
        destinations.map((d) => d.path),
        isNot(contains(RoutePaths.settings)),
      );
      expect(settingsDestination.path, RoutePaths.settings);
    });

    test('every destination has a label and a route', () {
      for (final d in destinations) {
        expect(d.label, isNotEmpty);
        expect(d.path, startsWith('/'));
      }
      expect(destinations.map((d) => d.path).toSet(), hasLength(5));
    });
  });

  group('navIndexForLocation', () {
    test('maps each destination to its own index', () {
      for (var i = 0; i < destinations.length; i++) {
        expect(navIndexForLocation(destinations[i].path), i,
            reason: destinations[i].path);
      }
    });

    test('a sub-route highlights its destination', () {
      expect(navIndexForLocation('/library/downloaded'),
          destinations.indexWhere((d) => d.path == RoutePaths.library));
      expect(navIndexForLocation('/settings/audio'), 0);
    });

    test('settings highlights home, like explore and history do', () {
      // 刻意的：它們都是從首頁推進去的子頁（見 lib/ui/AGENTS.md 的
      // Page Conventions）。
      expect(navIndexForLocation(RoutePaths.settings), 0);
      expect(navIndexForLocation(RoutePaths.explore), 0);
      expect(navIndexForLocation(RoutePaths.history), 0);
      expect(navIndexForLocation(RoutePaths.home), 0);
    });

    test('a route that merely shares a prefix does not steal the highlight',
        () {
      // `/radio-player` 以 `/radio` 開頭。舊的 startsWith 比對會把它算成
      // 電台分頁。
      expect(navIndexForLocation(RoutePaths.radioPlayer), 0);
      expect(navIndexForLocation(RoutePaths.player), 0);
    });
  });

  test('the labels come from i18n, not hardcoded strings', () {
    expect(destinations.first.label, t.nav.home);
    expect(settingsDestination.label, t.nav.settings);
  });
}
