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
        '$repoRoot/lib/providers/audio/audio_player_selectors.dart',
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
      final backdropSource =
          readSource('lib/ui/widgets/player/blurred_cover_backdrop.dart');

      expect(source, contains('Breakpoints.isDesktop'));
      expect(backdropSource, contains('ImageFilter.blur'));
      expect(source, contains('ImmersivePlayerScaffold('));
      expect(source, contains('_buildDesktopPlayerContent'));
      expect(source, contains('_buildControlSection'));
      expect(
          source, contains('showLyricsActions = isWideLayout || _showLyrics'));
    });

    test('PlayerPage uses a preloaded cover backdrop for all widths', () {
      final playerSource = readSource('lib/ui/pages/player/player_page.dart');
      final backdropSource =
          readSource('lib/ui/widgets/player/blurred_cover_backdrop.dart');
      final trackCoverSource =
          readSource('lib/ui/widgets/images/track_thumbnail.dart');
      final imageServiceSource =
          readSource('lib/core/services/image_loading_service.dart');
      final candidatesStart =
          imageServiceSource.indexOf('static List<ImageProvider>');
      final candidatesEnd =
          imageServiceSource.indexOf('/// 加载网络图片', candidatesStart);
      final candidatesSource =
          imageServiceSource.substring(candidatesStart, candidatesEnd);

      expect(playerSource, contains('body: ImmersivePlayerScaffold('));
      expect(playerSource, contains('appBar: null'));
      expect(playerSource, isNot(contains('appBar: appBar')));
      expect(playerSource, contains('TrackBlurredBackdrop('));
      expect(backdropSource, contains('class BlurredCoverBackdrop'));
      expect(backdropSource, contains('precacheImage'));
      expect(backdropSource, contains('Future<bool> _precacheImage'));
      expect(backdropSource, contains('onError:'));
      expect(backdropSource, contains('BlurredCoverBackdropLoadState'));
      expect(backdropSource, contains('loadedKey'));
      expect(backdropSource, contains('desiredKey'));
      expect(backdropSource, contains('TrackCover.imageProviderCandidates'));
      expect(
        trackCoverSource,
        contains(RegExp(
          r'case TrackCoverVariant\.backdrop:\s*return ImageTargetSizes\.high;',
        )),
      );
      expect(playerSource,
          isNot(contains('ImageLoadingService.imageProviderCandidates')));
      expect(imageServiceSource, contains('imageProviderCandidates'));
      expect(imageServiceSource, contains('CachedNetworkImageProvider'));
      expect(candidatesSource, contains('maxWidth: request.cacheExtent'));
      expect(candidatesSource, contains('maxHeight: request.cacheExtent'));
    });

    test('PlayerPage keeps one backdrop image layer behind the AppBar', () {
      final playerSource = readSource('lib/ui/pages/player/player_page.dart');
      final scaffoldSource =
          readSource('lib/ui/widgets/layout/immersive_player_scaffold.dart');

      expect(playerSource, contains('appBar: null'));
      expect(playerSource, isNot(contains('appBar: appBar')));
      // AppBar 與其 flexibleSpace overlay 由共享 scaffold 建立。
      expect(scaffoldSource, contains('flexibleSpace: _buildAppBarOverlay'));
      expect(
          playerSource, isNot(contains('flexibleSpace: _buildAppBarBackdrop')));
      expect(
        RegExp(r'TrackBlurredBackdrop\(').allMatches(playerSource),
        hasLength(1),
      );
      expect(scaffoldSource, contains('top: _appBarHeight'));
      expect(scaffoldSource, contains('height: _appBarHeight'));
    });

    test('PlayerPage clears stale cover backdrop when no cover is available',
        () {
      final source =
          readSource('lib/ui/widgets/player/blurred_cover_backdrop.dart');

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
          readSource('lib/ui/widgets/panels/track_detail_panel.dart');

      expect(imageServiceSource, contains('precacheImageCandidates'));
      expect(trackDetailSource,
          contains('RadioCoverImage.precacheImageCandidates'));
      expect(trackDetailSource,
          isNot(contains('ImageLoadingService.precacheImageCandidates')));
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

    test('ImmersivePlayerScaffold keeps AppBar overlay opacity independent from body', () {
      final scaffoldSource =
          readSource('lib/ui/widgets/layout/immersive_player_scaffold.dart');
      final playerSource = readSource('lib/ui/pages/player/player_page.dart');
      final radioSource = readSource('lib/ui/pages/radio/radio_player_page.dart');

      // 四個 overlay alpha 常數與 overlay 方法由共享 scaffold 單一持有。
      expect(
        scaffoldSource,
        contains(
          'static const double _bodyBackdropSurfaceOverlayAlpha = 0.60;',
        ),
      );
      expect(
        scaffoldSource,
        contains(
          'static const double _bodyBackdropContainerOverlayAlpha = 0.08;',
        ),
      );
      expect(
        scaffoldSource,
        contains(
          'static const double _appBarBackdropSurfaceOverlayAlpha = 0.50;',
        ),
      );
      expect(
        scaffoldSource,
        contains(
          'static const double _appBarBackdropContainerOverlayAlpha = 0.06;',
        ),
      );
      expect(scaffoldSource, contains('_buildBodyBackdropOverlays(colorScheme)'));
      expect(scaffoldSource, contains('_buildAppBarOverlay(colorScheme)'));
      // 兩頁都不再自帶沉浸式 overlay 常數（去重契約）。
      expect(playerSource, isNot(contains('_bodyBackdropSurfaceOverlayAlpha')));
      expect(radioSource, isNot(contains('_bodyBackdropSurfaceOverlayAlpha')));
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
      final source =
          readSource('lib/ui/widgets/app_bars/custom_title_bar.dart');

      expect(source, contains('Overlay.maybeOf(context)'));
      expect(source, contains('Tooltip('));
    });

    test('TrackDetailPanel uses shared stream selector without broad watch',
        () {
      final source =
          readSource('lib/ui/widgets/panels/track_detail_panel.dart');

      expect(source, isNot(contains('ref.watch(audioControllerProvider)')));
      expect(source, contains('ref.watch(currentStreamMetadataProvider)'));
    });
  });
}
