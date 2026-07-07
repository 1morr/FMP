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
      final scaffoldSource =
          readSource('lib/ui/widgets/layout/immersive_player_scaffold.dart');
      final sharedBackdrop =
          readSource('lib/ui/widgets/player/blurred_cover_backdrop.dart');

      expect(
        radioPlayer,
        contains(
          "import '../../widgets/player/blurred_cover_backdrop.dart';",
        ),
      );
      expect(radioPlayer, contains('body: ImmersivePlayerScaffold('));
      expect(radioPlayer, contains('appBar: null'));
      expect(radioPlayer, isNot(contains('appBar: appBar')));
      // AppBar、overlay 常數與方法由共享 scaffold 建立/持有。
      expect(scaffoldSource, contains('flexibleSpace: _buildAppBarOverlay'));
      expect(scaffoldSource, contains('backgroundColor: Colors.transparent'));
      expect(scaffoldSource, contains('surfaceTintColor: Colors.transparent'));
      expect(scaffoldSource, contains('top: _appBarHeight'));
      expect(scaffoldSource, contains('height: _appBarHeight'));
      expect(scaffoldSource, contains('_buildBodyBackdropOverlays(colorScheme)'));
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
      expect(
        RegExp(r'RadioBlurredBackdrop\(').allMatches(radioPlayer),
        hasLength(1),
      );
      expect(radioPlayer, contains('RadioCoverImage('));
      // 電台頁不再自帶沉浸式骨架常數（去重契約）。
      expect(radioPlayer, isNot(contains('_radioPlayerAppBarHeight')));

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
