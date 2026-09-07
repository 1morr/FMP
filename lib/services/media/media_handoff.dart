import 'dart:io';

import '../../data/sources/source_http_policy.dart';

class MediaHandoffRequest {
  const MediaHandoffRequest({
    required this.sourceType,
    required this.url,
    this.streamResolutionAuth,
    this.rangeStart,
  });

  final String sourceType;
  final Uri url;

  /// 音源帳號的 header，僅用於**串流解析**（見 `SourceAuthContext.authForPlay`）。
  ///
  /// 位元組請求刻意不帶它：網易的媒體 URL 本身就是簽名過的，音質在 eapi 解析
  /// 當下就由帳號決定了，CDN 不需要 Cookie。保留這個欄位是為了讓呼叫端不必為
  /// 播放與下載準備兩份請求物件。
  final Map<String, String>? streamResolutionAuth;

  final int? rangeStart;
}

class MediaHandoffResult {
  const MediaHandoffResult({required this.url, required this.headers});

  final Uri url;
  final Map<String, String> headers;
}

abstract interface class MediaHandoff {
  Future<MediaHandoffResult> preparePlayback(MediaHandoffRequest request);

  MediaHandoffResult prepareDownloadHop(MediaHandoffRequest request);
}

class DefaultMediaHandoff implements MediaHandoff {
  const DefaultMediaHandoff();

  @override
  Future<MediaHandoffResult> preparePlayback(
    MediaHandoffRequest request,
  ) async {
    return _prepareHeaders(request);
  }

  @override
  MediaHandoffResult prepareDownloadHop(MediaHandoffRequest request) {
    return _prepareHeaders(request);
  }

  MediaHandoffResult _prepareHeaders(MediaHandoffRequest request) {
    final headers = SourceHttpPolicy.mediaHeaders(request.sourceType);
    final rangeStart = request.rangeStart;
    if (rangeStart != null && rangeStart > 0) {
      headers[HttpHeaders.rangeHeader] = 'bytes=$rangeStart-';
    }

    return MediaHandoffResult(url: request.url, headers: headers);
  }
}
