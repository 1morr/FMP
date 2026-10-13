import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/url_opener/url_launcher_opener.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  final uri = Uri.parse('https://example.test/issues/new');

  // 一律交給外部 App（瀏覽器），不在 App 內開 WebView。
  test('opens the address in an external application', () async {
    Uri? openedUri;
    LaunchMode? openedMode;
    final opener = UrlLauncherOpener((
      url, {
      mode = LaunchMode.platformDefault,
    }) async {
      openedUri = url;
      openedMode = mode;
      return true;
    });

    expect(await opener.open(uri), isTrue);
    expect(openedUri, uri);
    expect(openedMode, LaunchMode.externalApplication);
  });

  test('reports false when nothing could open it', () async {
    final opener = UrlLauncherOpener(
      (url, {mode = LaunchMode.platformDefault}) async => false,
    );

    expect(await opener.open(uri), isFalse);
  });

  test('a platform failure is false, not an exception', () async {
    final opener = UrlLauncherOpener(
      (url, {mode = LaunchMode.platformDefault}) async =>
          throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    );

    expect(await opener.open(uri), isFalse);
  });
}
