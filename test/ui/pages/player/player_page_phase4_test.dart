import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 4 Task 1 player source contract', () {
    late String repoRoot;

    setUp(() {
      repoRoot = Directory.current.path;
    });

    String readSource(String relativePath) {
      return File('$repoRoot/$relativePath').readAsStringSync();
    }

    test('audio selector providers file defines shared player selectors', () {
      final selectorFile = File(
        '$repoRoot/lib/providers/audio_player_selectors.dart',
      );

      expect(selectorFile.existsSync(), isTrue);

      final source = selectorFile.readAsStringSync();
      expect(source, contains('playbackSpeedProvider'));
      expect(source, contains('desktopAudioDeviceStateProvider'));
      expect(source, contains('currentStreamMetadataProvider'));
    });

    test('PlayerPage selector does not capture the whole PlayerState object',
        () {
      final source = readSource('lib/ui/pages/player/player_page.dart');

      expect(source, isNot(contains('state: state')));
    });

    test('PlayerPage uses shared selectors instead of broad controller watch',
        () {
      final source = readSource('lib/ui/pages/player/player_page.dart');

      expect(source, isNot(contains('ref.watch(audioControllerProvider)')));
      expect(source, contains('ref.watch(playbackSpeedProvider)'));
      expect(source, contains('ref.watch(desktopAudioDeviceStateProvider)'));
      expect(source, contains('ref.watch(currentStreamMetadataProvider)'));
    });

    test('PlayerPage splits cover and lyrics on desktop width', () {
      final source = readSource('lib/ui/pages/player/player_page.dart');

      expect(source, contains('Breakpoints.isDesktop'));
      expect(source, contains('ImageFilter.blur'));
      expect(source, contains('_buildImmersiveDesktopLayout'));
      expect(source, contains('_buildDesktopPlayerContent'));
      expect(source, contains('_buildControlSection'));
      expect(
          source, contains('showLyricsActions = isWideLayout || _showLyrics'));
    });

    test('Windows title bar is owned by the app wrapper', () {
      final appSource = readSource('lib/app.dart');
      final playerSource = readSource('lib/ui/pages/player/player_page.dart');
      final responsiveSource =
          readSource('lib/ui/layouts/responsive_scaffold.dart');

      expect(appSource, contains('CustomTitleBar'));
      expect(playerSource, isNot(contains('CustomTitleBar')));
      expect(responsiveSource, isNot(contains('CustomTitleBar')));
    });

    test('CustomTitleBar skips Tooltip when no Overlay is available', () {
      final source = readSource('lib/ui/widgets/custom_title_bar.dart');

      expect(source, contains('Overlay.maybeOf(context)'));
      expect(source, contains('Tooltip('));
    });

    test('TrackDetailPanel uses shared stream selector without broad watch',
        () {
      final source = readSource('lib/ui/widgets/track_detail_panel.dart');

      expect(source, isNot(contains('ref.watch(audioControllerProvider)')));
      expect(source, contains('ref.watch(currentStreamMetadataProvider)'));
    });
  });
}
