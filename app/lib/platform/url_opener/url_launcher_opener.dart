import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fmp/platform/url_opener/url_opener.dart';

/// `url_launcher` 的 `launchUrl` 的形狀；測試換掉它，不碰平台通道。
typedef LaunchUrl = Future<bool> Function(Uri url, {LaunchMode mode});

/// [UrlOpener] 的實作，Android、Windows 與 macOS 共用：差異都在 `url_launcher` 的原生端。
/// 一律交給外部 App（瀏覽器），不在 App 內開 WebView。
final class UrlLauncherOpener implements UrlOpener {
  const UrlLauncherOpener([this._launch = launchUrl]);

  final LaunchUrl _launch;

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await _launch(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }
}
