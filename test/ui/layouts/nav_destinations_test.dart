import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/layouts/responsive_scaffold.dart';
import 'package:fmp/ui/router.dart';

void main() {
  group('destinations', () {
    test('settings is a destination, and the last one', () {
      // 設定曾被移出導覽列（14c6608c）又放回來：手機上會捲走、導覽軌上沒有
      // 文字的入口，比五個較寬的分頁更礙事。
      expect(destinations.last.path, RoutePaths.settings);
    });

    test('every destination has a label and a distinct route', () {
      for (final d in destinations) {
        expect(d.label, isNotEmpty);
        expect(d.path, startsWith('/'));
      }
      expect(
        destinations.map((d) => d.path).toSet(),
        hasLength(destinations.length),
      );
    });
  });

  group('navIndexForLocation', () {
    test('maps each destination to its own index', () {
      for (var i = 0; i < destinations.length; i++) {
        expect(
          navIndexForLocation(destinations[i].path),
          i,
          reason: destinations[i].path,
        );
      }
    });

    test('a sub-route highlights its destination', () {
      expect(
        navIndexForLocation('/library/downloaded'),
        destinations.indexWhere((d) => d.path == RoutePaths.library),
      );
      expect(
        navIndexForLocation(RoutePaths.audioSettings),
        destinations.indexWhere((d) => d.path == RoutePaths.settings),
      );
    });

    test('explore and history highlight home', () {
      // 刻意的：它們都是從首頁推進去的子頁（見 lib/ui/AGENTS.md 的
      // Page Conventions）。
      expect(navIndexForLocation(RoutePaths.explore), 0);
      expect(navIndexForLocation(RoutePaths.history), 0);
      expect(navIndexForLocation(RoutePaths.home), 0);
    });

    test(
      'a route that merely shares a prefix does not steal the highlight',
      () {
        // `/radio-player` 以 `/radio` 開頭。舊的 startsWith 比對會把它算成
        // 電台分頁。
        expect(navIndexForLocation(RoutePaths.radioPlayer), 0);
        expect(navIndexForLocation(RoutePaths.player), 0);
      },
    );
  });

  test('the labels come from i18n, not hardcoded strings', () {
    expect(destinations.first.label, t.nav.home);
    expect(destinations.last.label, t.nav.settings);
  });
}
