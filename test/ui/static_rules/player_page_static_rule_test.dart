import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 播放頁與其共享 widget 的幾條跨檔規則。
///
/// 2026-09-17 之前這個檔案還釘著 `appBar: null`、四個 overlay alpha 常數、
/// `showLyricsActions = isWideLayout || _showLyrics` 這類版面結構。那些只有實機
/// 能驗（見根 `AGENTS.md` 的 on-device 規則），釘成源碼字串守不住任何 bug，
/// 只會讓正當的重構變紅，所以刪掉了。留下來的是三種還有消費者的規則：
/// watch 範圍（整頁不准 watch 整個控制器）、標題列的擁有權、以及兩個尚未有
/// widget 測試接手的行為（backdrop 清除、fade image 換 provider 時重載）。
void main() {
  group('player page watch scope and ownership', () {
    late String repoRoot;

    setUp(() {
      repoRoot = Directory.current.path;
    });

    String readSource(String relativePath) {
      return File('$repoRoot/$relativePath').readAsStringSync();
    }

    test(
      'PlayerPage uses shared selectors instead of broad controller watch',
      () {
        final source = readSource('lib/ui/pages/player/player_page.dart');

        expect(source, isNot(contains('ref.watch(audioControllerProvider)')));
        expect(source, contains('ref.watch(playbackSpeedProvider)'));
        expect(source, contains('ref.watch(desktopAudioDeviceStateProvider)'));
        expect(source, contains('ref.watch(currentStreamMetadataProvider)'));
      },
    );

    test(
      'TrackDetailPanel uses shared stream selector without broad watch',
      () {
        final source = readSource(
          'lib/ui/widgets/panels/track_detail_panel.dart',
        );

        expect(source, isNot(contains('ref.watch(audioControllerProvider)')));
        expect(source, contains('ref.watch(currentStreamMetadataProvider)'));
      },
    );

    test('Windows title bar is owned by the app wrapper', () {
      final appSource = readSource('lib/app.dart');
      final playerSource = readSource('lib/ui/pages/player/player_page.dart');
      final responsiveSource = readSource(
        'lib/ui/layouts/responsive_scaffold.dart',
      );

      expect(appSource, contains('CustomTitleBar'));
      expect(playerSource, isNot(contains('CustomTitleBar')));
      expect(responsiveSource, isNot(contains('CustomTitleBar')));
    });

    test('CustomTitleBar skips Tooltip when no Overlay is available', () {
      final source = readSource(
        'lib/ui/widgets/app_bars/custom_title_bar.dart',
      );

      expect(source, contains('Overlay.maybeOf(context)'));
      expect(source, contains('Tooltip('));
    });

    test(
      'PlayerPage clears stale cover backdrop when no cover is available',
      () {
        final source = readSource(
          'lib/ui/widgets/player/blurred_cover_backdrop.dart',
        );

        expect(source, contains('void _clearLoadedImage()'));
        expect(source, contains('_imageProvider = null'));
        expect(source, contains('_loadState.clearLoaded()'));
        expect(source, contains('sourceKey == null || candidates.isEmpty'));
      },
    );

    test(
      'ImageLoadingService reloads local fade images when provider changes',
      () {
        final source = readSource(
          'lib/core/services/image_loading_service.dart',
        );

        expect(source, contains('void didUpdateWidget'));
        expect(source, contains('oldWidget.image != widget.image'));
        expect(source, contains('_stream?.removeListener'));
        expect(source, contains('_error = null'));
        expect(source, contains('_loadImage();'));
      },
    );
  });
}
