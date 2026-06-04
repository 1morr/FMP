import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fullscreen player route transitions', () {
    late String routerSource;

    setUp(() {
      routerSource = File('lib/ui/router.dart').readAsStringSync();
    });

    test('dismisses fullscreen players with a fast reverse curve', () {
      expect(
        routerSource,
        contains('CustomTransitionPage<void> _fullscreenPlayerPage'),
      );
      expect(
        routerSource,
        contains('reverseCurve: Curves.easeInCubic'),
      );
      expect(routerSource, contains('ClipRect('));
    });

    test('player and radio player routes share the fullscreen transition', () {
      expect(routerSource, contains('child: const PlayerPage(),'));
      expect(routerSource, contains('child: const RadioPlayerPage(),'));
      expect(
        RegExp(r'_fullscreenPlayerPage\(').allMatches(routerSource),
        hasLength(3),
      );
    });
  });
}
