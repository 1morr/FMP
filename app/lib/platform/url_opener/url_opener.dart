import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 用系統的瀏覽器開網址（「在 GitHub 回報」，ADR 0023 §決定 4）。實作有 Android 與
/// Windows（`url_launcher_opener.dart`），由 `platform.dart` 組裝。
abstract interface class UrlOpener {
  /// 在外部 App 開 [uri]。開不了（沒有能處理的 App、平台拒絕）回 `false`，不拋錯。
  Future<bool> open(Uri uri);
}

/// 平台的網址開啟器；平台沒有這個能力（`PlatformCapabilities.urlOpener` 為假）時為
/// `null`。`main()` 以 `AppPlatform.urlOpener` override；沒 override 就讀會拋錯。
final urlOpenerProvider = Provider<UrlOpener?>(
  (ref) => throw UnimplementedError(
    'urlOpenerProvider is overridden by main() with the platform '
    'implementation',
  ),
);
