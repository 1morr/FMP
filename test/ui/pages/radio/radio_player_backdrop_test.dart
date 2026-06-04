import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RadioPlayerPage backdrop', () {
    String readSource(String relativePath) {
      return File(relativePath).readAsStringSync();
    }

    test('uses one shared blurred backdrop behind the AppBar', () {
      final radioPlayer =
          readSource('lib/ui/pages/radio/radio_player_page.dart');
      final sharedBackdrop =
          readSource('lib/ui/widgets/player/blurred_cover_backdrop.dart');

      expect(
        radioPlayer,
        contains(
          "import '../../widgets/player/blurred_cover_backdrop.dart';",
        ),
      );
      expect(radioPlayer, contains('body: _buildImmersiveRadioLayout('));
      expect(radioPlayer, contains('appBar: null'));
      expect(radioPlayer, contains('appBar: appBar'));
      expect(radioPlayer, contains('flexibleSpace: _buildAppBarOverlay'));
      expect(
          radioPlayer, isNot(contains('flexibleSpace: _buildAppBarBackdrop')));
      expect(radioPlayer, contains('backgroundColor: Colors.transparent'));
      expect(radioPlayer, contains('surfaceTintColor: Colors.transparent'));
      expect(
        RegExp(r'RadioBlurredBackdrop\(').allMatches(radioPlayer),
        hasLength(1),
      );
      expect(radioPlayer, contains('top: _radioPlayerAppBarHeight'));
      expect(radioPlayer, contains('height: _radioPlayerAppBarHeight'));
      expect(radioPlayer, contains('_buildBodyBackdropOverlays(colorScheme)'));
      expect(
        radioPlayer,
        contains(
          'static const double _appBarBackdropSurfaceOverlayAlpha = 0.50;',
        ),
      );
      expect(
        radioPlayer,
        contains(
          'static const double _appBarBackdropContainerOverlayAlpha = 0.06;',
        ),
      );
      expect(radioPlayer, contains('RadioCoverImage('));

      expect(sharedBackdrop, contains('class RadioBlurredBackdrop'));
      expect(sharedBackdrop, contains('class TrackBlurredBackdrop'));
      expect(
          sharedBackdrop, contains('ImageFilter.blur(sigmaX: 48, sigmaY: 48)'));
      expect(sharedBackdrop, contains('AnimatedSwitcher'));
      expect(sharedBackdrop, contains('BlurredCoverBackdropLoadState'));
    });

    test('radio covers expose high-sized backdrop image candidates', () {
      final radioCover =
          readSource('lib/ui/widgets/images/radio_cover_image.dart');

      expect(radioCover, contains('RadioCoverVariant.backdrop'));
      expect(
        radioCover,
        contains(RegExp(
          r'case RadioCoverVariant\.backdrop:\s*return ImageTargetSizes\.high;',
        )),
      );
      expect(radioCover, contains('imageProviderCandidates'));
      expect(radioCover, contains('RadioCoverVariant.hero'));
    });
  });
}
