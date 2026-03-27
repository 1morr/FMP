import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/track.dart';
import '../../providers/account_provider.dart';
import '../../services/account/bilibili_account_service.dart';
import '../../services/account/netease_account_service.dart';
import '../../services/account/youtube_account_service.dart';

/// Build auth headers from account services directly (non-Riverpod contexts).
Future<Map<String, String>?> buildAuthHeaders(
  SourceType platform, {
  BilibiliAccountService? bilibiliAccountService,
  YouTubeAccountService? youtubeAccountService,
  NeteaseAccountService? neteaseAccountService,
}) async {
  switch (platform) {
    case SourceType.bilibili:
      final cookies = await bilibiliAccountService?.getAuthCookieString();
      if (cookies == null) return null;
      return {'Cookie': cookies};
    case SourceType.youtube:
      return await youtubeAccountService?.getAuthHeaders();
    case SourceType.netease:
      final cookies = await neteaseAccountService?.getAuthCookieString();
      if (cookies == null) return null;
      // Netease /api/ and /eapi/ endpoints need full headers
      return {
        'Cookie': cookies,
        'Origin': 'https://music.163.com',
        'Referer': 'https://music.163.com/',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 '
                'NeteaseMusicDesktop/3.0.18.203152',
      };
  }
}

/// Get auth headers for a platform via Riverpod Ref.
Future<Map<String, String>?> getAuthHeadersForPlatform(
  SourceType platform,
  Ref ref,
) async {
  return buildAuthHeaders(
    platform,
    bilibiliAccountService: ref.read(bilibiliAccountServiceProvider),
    youtubeAccountService: ref.read(youtubeAccountServiceProvider),
    neteaseAccountService: ref.read(neteaseAccountServiceProvider),
  );
}
