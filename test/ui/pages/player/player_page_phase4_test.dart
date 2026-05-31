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
      expect(source, contains('_buildImmersivePlayerLayout'));
      expect(source, contains('_buildDesktopPlayerContent'));
      expect(source, contains('_buildControlSection'));
      expect(
          source, contains('showLyricsActions = isWideLayout || _showLyrics'));
    });

    test('PlayerPage uses a preloaded cover backdrop for all widths', () {
      final playerSource = readSource('lib/ui/pages/player/player_page.dart');
      final imageServiceSource =
          readSource('lib/core/services/image_loading_service.dart');
      final candidatesStart =
          imageServiceSource.indexOf('static List<ImageProvider>');
      final candidatesEnd =
          imageServiceSource.indexOf('/// 加载网络图片', candidatesStart);
      final candidatesSource =
          imageServiceSource.substring(candidatesStart, candidatesEnd);

      expect(playerSource, contains('body: _buildImmersivePlayerLayout('));
      expect(playerSource, contains('flexibleSpace: _buildAppBarBackdrop'));
      expect(playerSource, contains('backgroundColor: Colors.transparent'));
      expect(playerSource, contains('surfaceTintColor: Colors.transparent'));
      expect(playerSource, contains('class _PlayerBackdrop'));
      expect(playerSource, contains('precacheImage'));
      expect(playerSource, contains('Future<bool> _precacheImage'));
      expect(playerSource, contains('onError:'));
      expect(playerSource, contains('PlayerBackdropLoadState'));
      expect(playerSource, contains('loadedKey'));
      expect(playerSource, contains('desiredKey'));
      expect(playerSource,
          contains('ImageLoadingService.imageProviderCandidates'));
      expect(imageServiceSource, contains('imageProviderCandidates'));
      expect(imageServiceSource, contains('CachedNetworkImageProvider'));
      expect(candidatesSource, contains('maxWidth: cacheExtent'));
      expect(candidatesSource, contains('maxHeight: cacheExtent'));
    });

    test('PlayerPage clears stale cover backdrop when no cover is available',
        () {
      final source = readSource('lib/ui/pages/player/player_page.dart');

      expect(source, contains('void _clearLoadedImage()'));
      expect(source, contains('_imageProvider = null'));
      expect(source, contains('_loadState.clearLoaded()'));
      expect(source, contains('sourceKey == null || candidates.isEmpty'));
    });

    test('ImageLoadingService exposes shared precache helper for image users',
        () {
      final imageServiceSource =
          readSource('lib/core/services/image_loading_service.dart');
      final trackDetailSource =
          readSource('lib/ui/widgets/track_detail_panel.dart');

      expect(imageServiceSource, contains('precacheImageCandidates'));
      expect(trackDetailSource,
          contains('ImageLoadingService.precacheImageCandidates'));
      expect(trackDetailSource, isNot(contains('CachedNetworkImageProvider(')));
      expect(trackDetailSource,
          isNot(contains('ThumbnailUrlUtils.getOptimizedUrl(')));
    });

    test('ImageLoadingService reloads local fade images when provider changes',
        () {
      final source = readSource('lib/core/services/image_loading_service.dart');

      expect(source, contains('void didUpdateWidget'));
      expect(source, contains('oldWidget.image != widget.image'));
      expect(source, contains('_stream?.removeListener'));
      expect(source, contains('_error = null'));
      expect(source, contains('_loadImage();'));
    });

    test('PlayerPage keeps AppBar backdrop opacity independent from body', () {
      final playerSource = readSource('lib/ui/pages/player/player_page.dart');

      expect(
        playerSource,
        contains(
          'static const double _bodyBackdropSurfaceOverlayAlpha = 0.60;',
        ),
      );
      expect(
        playerSource,
        contains(
          'static const double _bodyBackdropContainerOverlayAlpha = 0.08;',
        ),
      );
      expect(
        playerSource,
        contains(
          'static const double _appBarBackdropSurfaceOverlayAlpha = 0.30;',
        ),
      );
      expect(
        playerSource,
        contains(
          'static const double _appBarBackdropContainerOverlayAlpha = 0.01;',
        ),
      );
      expect(playerSource, contains('surfaceOverlayAlpha:'));
      expect(playerSource, contains('surfaceContainerOverlayAlpha:'));
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
