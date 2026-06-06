import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/widgets/feedback/network_status_banner.dart';

void main() {
  group('resolveNetworkStatusBannerKind', () {
    test('returns noNetwork only when global connectivity is unavailable', () {
      expect(
        resolveNetworkStatusBannerKind(
          isConnected: false,
          hasPlaybackNetworkError: false,
        ),
        NetworkStatusBannerKind.noNetwork,
      );
    });

    test('returns playbackNetworkError when playback fails but network is up',
        () {
      expect(
        resolveNetworkStatusBannerKind(
          isConnected: true,
          hasPlaybackNetworkError: true,
        ),
        NetworkStatusBannerKind.playbackNetworkError,
      );
    });

    test('prefers noNetwork when both connectivity and playback fail', () {
      expect(
        resolveNetworkStatusBannerKind(
          isConnected: false,
          hasPlaybackNetworkError: true,
        ),
        NetworkStatusBannerKind.noNetwork,
      );
    });
  });
}
