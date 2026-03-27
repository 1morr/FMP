import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/track.dart';
import '../../data/sources/source_exception.dart';
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
      return {'Cookie': cookies};
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

/// Execute an action anonymously first, retry with auth on permission error.
///
/// If the action fails with a non-permission error, rethrows immediately.
/// If the action fails with a permission error but user is not logged in, rethrows.
Future<T> withAuthRetry<T>({
  required Future<T> Function(Map<String, String>? authHeaders) action,
  required SourceType platform,
  required Ref ref,
}) async {
  try {
    return await action(null);
  } on SourceApiException catch (e) {
    if (!e.isPermissionDenied && !e.requiresLogin) rethrow;

    final headers = await getAuthHeadersForPlatform(platform, ref);
    if (headers == null) rethrow;

    return await action(headers);
  }
}

/// Variant for non-Riverpod contexts (services without Ref).
/// Caller provides the auth header getter directly.
Future<T> withAuthRetryDirect<T>({
  required Future<T> Function(Map<String, String>? authHeaders) action,
  required Future<Map<String, String>?> Function() getAuthHeaders,
}) async {
  try {
    return await action(null);
  } on SourceApiException catch (e) {
    if (!e.isPermissionDenied && !e.requiresLogin) rethrow;

    final headers = await getAuthHeaders();
    if (headers == null) rethrow;

    return await action(headers);
  }
}
