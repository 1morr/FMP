import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// 用系統瀏覽器開網址（選單的「在瀏覽器開啟」）。測試 override 成假的。
final webLinksProvider = Provider<WebLinks>((ref) => const WebLinks());

class WebLinks {
  const WebLinks();

  /// 用系統的預設瀏覽器開 [url]，不在 App 裡開；開不了回傳 false。直接
  /// `launchUrl`，不先問 `canLaunchUrl`（那個要另外宣告查詢的 scheme）。
  Future<bool> open(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}
