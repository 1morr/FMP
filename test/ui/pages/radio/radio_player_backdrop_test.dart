import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RadioPlayerPage backdrop', () {
    String readSource(String relativePath) {
      return File(relativePath).readAsStringSync();
    }

    test('uses the shared blurred backdrop for body and app bar', () {
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
      expect(
        radioPlayer,
        contains('flexibleSpace: _buildAppBarBackdrop(station, colorScheme)'),
      );
      expect(radioPlayer, contains('backgroundColor: Colors.transparent'));
      expect(radioPlayer, contains('surfaceTintColor: Colors.transparent'));
      expect(radioPlayer, contains('RadioBlurredBackdrop('));
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
